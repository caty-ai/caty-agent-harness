#!/usr/bin/env bash
set -euo pipefail

# VERIFIER_CMD must be exactly one absolute wrapper-script path with fresh
# conformance evidence. Legacy multi-token commands are rejected.

usage() {
  printf 'Usage: verify-job.sh <artifact-bundle-dir>\n' >&2
}

infra_fail() {
  printf 'verify-job infra error: %s\n' "$1" >&2
  exit 5
}

record_exit_code() {
  local record_path=$1

  python3 - "$record_path" <<'PY'
import json
import sys

verdict = json.load(open(sys.argv[1], encoding="utf-8")).get("verdict", "")
mapping = {
    "pass": 0,
    "fail": 1,
    "rubric-invalid": 1,
    "blocked-missing-artifact": 3,
    "inconclusive": 4,
    "needs-human": 4,
    "contract-violation": 6,
}
print(mapping.get(verdict, 4))
PY
}

emit_record() {
  local record_path=$1

  python3 - "$record_path" <<'PY'
import json
import sys

record_path = sys.argv[1]
with open(record_path, encoding="utf-8") as f:
    record = json.load(f)

print(f"VERDICT: {record['verdict']}")
print(record["reason"])
PY
}

reconcile_log() {
  python3 - "$workspace_root" "$bundle_dir" "$task_id" <<'PY'
import fcntl
import json
import os
import re
import stat
import sys
import unicodedata

workspace_root, bundle_dir, task_id = sys.argv[1:4]
header = "# VERIFY log — append-only verifier verdict history\n"
allowed_verdicts = {
    "pass",
    "fail",
    "rubric-invalid",
    "blocked-missing-artifact",
    "inconclusive",
    "needs-human",
    "contract-violation",
}
timestamp_re = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")
directory_flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
file_nofollow = getattr(os, "O_NOFOLLOW", 0)

class UnsafePath(Exception):
    pass

def same_inode(left, right):
    return (left.st_dev, left.st_ino) == (right.st_dev, right.st_ino)

def open_directory(path_or_name, parent_fd=None):
    before = os.stat(path_or_name, dir_fd=parent_fd, follow_symlinks=False)
    if not stat.S_ISDIR(before.st_mode):
        raise UnsafePath(f"not a real directory: {path_or_name}")
    fd = os.open(path_or_name, directory_flags, dir_fd=parent_fd)
    opened = os.fstat(fd)
    if not same_inode(before, opened):
        os.close(fd)
        raise UnsafePath(f"directory changed while opening: {path_or_name}")
    return fd

def safe_text(value):
    return isinstance(value, str) and not any(
        unicodedata.category(character) in ("Cc", "Cf") for character in value
    )

def physical_lines(text):
    # project() terminates records with an ASCII LF. Use that same byte-level
    # boundary for deduplication so Unicode separators remain record text.
    lines = {line + "\n" for line in text.split("\n")[:-1]}
    if text and not text.endswith("\n"):
        lines.add(text.rsplit("\n", 1)[-1] + "\n")
    return lines

def read_complete_record(parent_fd):
    try:
        before = os.stat("verify.json", dir_fd=parent_fd, follow_symlinks=False)
        if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1 or 65536 < before.st_size:
            return None
        fd = os.open("verify.json", os.O_RDONLY | file_nofollow, dir_fd=parent_fd)
        try:
            opened = os.fstat(fd)
            if not same_inode(before, opened) or not stat.S_ISREG(opened.st_mode) or opened.st_nlink != 1:
                return None
            with os.fdopen(fd, "r", encoding="utf-8", closefd=False) as source:
                record = json.load(source)
        finally:
            os.close(fd)
    except (OSError, UnicodeError, json.JSONDecodeError):
        return None

    if not isinstance(record, dict) or not {
        "verdict", "reason", "verifier_id", "step", "ts"
    }.issubset(record):
        return None
    verdict = record["verdict"]
    reason = record["reason"]
    verifier_id = record["verifier_id"]
    step = record["step"]
    timestamp = record["ts"]
    if not isinstance(verdict, str) or verdict not in allowed_verdicts:
        return None
    if not safe_text(reason) or not reason.strip():
        return None
    if not safe_text(verifier_id) or not verifier_id:
        return None
    if not safe_text(timestamp) or timestamp_re.fullmatch(timestamp) is None:
        return None
    if step is not None and (isinstance(step, bool) or not isinstance(step, int) or step <= 0):
        return None
    return record

def project(record):
    step_field = "" if record["step"] is None else f" | step={record['step']}"
    return (
        f"- {record['ts']} | task={task_id}{step_field} | verifier={record['verifier_id']} | "
        f"verdict={record['verdict']} | {record['reason']}\n"
    )

def numeric_key(name):
    significant = name.lstrip("0") or "0"
    return (len(significant), significant, name)

workspace_fd = bundle_fd = attempts_fd = loop_fd = None
try:
    workspace_fd = open_directory(workspace_root)
    bundle_fd = open_directory(bundle_dir)
    records = []
    root_record = read_complete_record(bundle_fd)
    numeric_attempt_seen = False

    try:
        attempts_before = os.stat("attempts", dir_fd=bundle_fd, follow_symlinks=False)
    except FileNotFoundError:
        attempts_before = None
    if attempts_before is not None:
        if not stat.S_ISDIR(attempts_before.st_mode):
            raise UnsafePath("bundle attempts entry is not a real directory")
        attempts_fd = open_directory("attempts", bundle_fd)
        for name in sorted(os.listdir(attempts_fd)):
            if re.fullmatch(r"[0-9]+", name) is None:
                continue
            try:
                attempt_before = os.stat(name, dir_fd=attempts_fd, follow_symlinks=False)
                if not stat.S_ISDIR(attempt_before.st_mode):
                    continue
                attempt_fd = open_directory(name, attempts_fd)
            except (OSError, UnsafePath):
                continue
            numeric_attempt_seen = True
            try:
                record = read_complete_record(attempt_fd)
            finally:
                os.close(attempt_fd)
            if record is not None:
                records.append((numeric_key(name), record["ts"], f"attempts/{name}/verify.json", record))
    if not numeric_attempt_seen and root_record is not None:
        records.append(((-1, "", ""), root_record["ts"], "verify.json", root_record))

    loop_fd = open_directory("loop", workspace_fd)
    log_flags = os.O_RDWR | os.O_CREAT | os.O_APPEND | file_nofollow
    log_fd = os.open("VERIFY.log.md", log_flags, 0o600, dir_fd=loop_fd)
    opened_log = os.fstat(log_fd)
    if not stat.S_ISREG(opened_log.st_mode) or opened_log.st_nlink != 1:
        os.close(log_fd)
        raise UnsafePath("VERIFY.log.md is not a single-link regular file")
    with os.fdopen(log_fd, "r+b") as log:
        fcntl.flock(log.fileno(), fcntl.LOCK_EX)
        existing_data = log.read()
        existing_lines = physical_lines(existing_data.decode("utf-8"))
        if not existing_data:
            log.write(header.encode("utf-8"))
            existing_lines.add(header)
        elif not existing_data.endswith(b"\n"):
            log.write(b"\n")
        appended_lines = []
        for _, _, _, record in sorted(records, key=lambda item: (item[1], item[2])):
            line = project(record)
            if line not in existing_lines:
                log.write(line.encode("utf-8"))
                existing_lines.add(line)
                appended_lines.append(line)
        if appended_lines and records:
            latest_line = project(max(records, key=lambda item: item[0])[3])
            if appended_lines[-1] != latest_line:
                # Append-only repair can discover an older missing attempt after a
                # newer projection already exists. Re-project the newest attempt so
                # recovery never leaves an older verdict as this bundle's tail.
                log.write(latest_line.encode("utf-8"))
        log.flush()
        os.fsync(log.fileno())
except (OSError, UnicodeError, UnsafePath) as error:
    print(f"verify-job log reconciliation error: {error}", file=sys.stderr)
    raise SystemExit(7)
finally:
    for fd in (attempts_fd, bundle_fd, loop_fd, workspace_fd):
        if fd is not None:
            os.close(fd)
PY
}

reconcile_log_best_effort() {
  if ! reconcile_log; then
    printf '%s\n' \
      'verify-job warning: VERIFY.log.md remains stale; authoritative verify.json is unaffected' >&2
  fi
}

write_record() {
  local record_path=$1
  local verdict=$2
  local reason=$3
  python3 - "$bundle_dir" "$record_path" "$verdict" "$reason" "$verifier_id" "${VERIFY_STEP:-}" <<'PY'
import json
import os
import re
import secrets
import stat
import sys
import unicodedata
from datetime import datetime, timezone

bundle_dir, record_path, verdict, reason, verifier_id, step_text = sys.argv[1:7]
directory_flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
file_nofollow = getattr(os, "O_NOFOLLOW", 0)
record_name = "verify.json"
tmp_name = f".{record_name}.tmp.{secrets.token_hex(8)}"

class UnsafePath(Exception):
    pass

def same_inode(left, right):
    return (left.st_dev, left.st_ino) == (right.st_dev, right.st_ino)

def open_directory(path_or_name, parent_fd=None):
    before = os.stat(path_or_name, dir_fd=parent_fd, follow_symlinks=False)
    if not stat.S_ISDIR(before.st_mode):
        raise UnsafePath(f"not a real directory: {path_or_name}")
    fd = os.open(path_or_name, directory_flags, dir_fd=parent_fd)
    opened = os.fstat(fd)
    if not same_inode(before, opened):
        os.close(fd)
        raise UnsafePath(f"directory changed while opening: {path_or_name}")
    return fd

def validate_membership():
    current_bundle = os.stat(bundle_dir, follow_symlinks=False)
    if not same_inode(current_bundle, os.fstat(bundle_fd)):
        raise UnsafePath("bundle directory changed before record replacement")
    if attempts_fd is not None:
        current_attempts = os.stat("attempts", dir_fd=bundle_fd, follow_symlinks=False)
        if not same_inode(current_attempts, os.fstat(attempts_fd)):
            raise UnsafePath("attempts directory changed before record replacement")
        current_attempt = os.stat(attempt_name, dir_fd=attempts_fd, follow_symlinks=False)
        if not same_inode(current_attempt, os.fstat(target_fd)):
            raise UnsafePath("attempt directory changed before record replacement")

step = None
if re.fullmatch(r"[1-9][0-9]*", step_text or "") and len(step_text) <= 18:
    try:
        step = int(step_text)
    except ValueError:
        step = None
sanitized_reason = "".join(
    character for character in reason
    if unicodedata.category(character) not in ("Cc", "Cf")
)
sanitized_reason = sanitized_reason.rstrip()
sanitized_verifier_id = "".join(
    character for character in verifier_id
    if unicodedata.category(character) not in ("Cc", "Cf")
).rstrip()
payload = (
    json.dumps(
        {
            "verdict": verdict,
            "reason": sanitized_reason,
            "verifier_id": sanitized_verifier_id or "unconfigured",
            "step": step,
            "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        },
        indent=2,
        sort_keys=True,
    )
    + "\n"
).encode("utf-8")

bundle_fd = attempts_fd = target_fd = None
created_inode = None
replaced = False
try:
    relative_record = os.path.relpath(record_path, bundle_dir)
    parts = relative_record.split(os.sep)
    bundle_fd = open_directory(bundle_dir)
    if parts == [record_name]:
        target_fd = os.dup(bundle_fd)
        attempt_name = None
    elif (
        len(parts) == 3
        and parts[0] == "attempts"
        and re.fullmatch(r"[0-9]+", parts[1]) is not None
        and parts[2] == record_name
    ):
        attempt_name = parts[1]
        attempts_fd = open_directory("attempts", bundle_fd)
        target_fd = open_directory(attempt_name, attempts_fd)
    else:
        raise UnsafePath("resolved record path is outside the bundle record locations")

    validate_membership()
    tmp_fd = os.open(
        tmp_name,
        os.O_WRONLY | os.O_CREAT | os.O_EXCL | file_nofollow,
        0o600,
        dir_fd=target_fd,
    )
    with os.fdopen(tmp_fd, "wb") as output:
        output.write(payload)
        output.flush()
        os.fsync(output.fileno())
        created_inode = os.fstat(output.fileno())
    validate_membership()
    os.replace(tmp_name, record_name, src_dir_fd=target_fd, dst_dir_fd=target_fd)
    replaced = True
    validate_membership()
    installed = os.stat(record_name, dir_fd=target_fd, follow_symlinks=False)
    if not same_inode(installed, created_inode) or not stat.S_ISREG(installed.st_mode):
        raise UnsafePath("installed record changed during replacement")
    os.fsync(target_fd)
except (OSError, UnsafePath) as error:
    try:
        if replaced and created_inode is not None:
            installed = os.stat(record_name, dir_fd=target_fd, follow_symlinks=False)
            if same_inode(installed, created_inode):
                os.unlink(record_name, dir_fd=target_fd)
        elif target_fd is not None:
            os.unlink(tmp_name, dir_fd=target_fd)
    except OSError:
        pass
    print(f"verify-job record write error: {error}", file=sys.stderr)
    raise SystemExit(7)
finally:
    for fd in (target_fd, attempts_fd, bundle_fd):
        if fd is not None:
            os.close(fd)
PY
}

finish_with_record() {
  local verdict=$1
  local reason=$2

  local record_status=0
  write_record "$verify_record_path" "$verdict" "$reason" || record_status=$?
  if ((record_status != 0)); then
    infra_fail "record target changed or is unsafe"
  fi
  # Test-only crash point models termination after the authoritative rename and
  # before projection into the lagging derived log.
  if [[ "${HERMES_VERIFY_TEST_INTERRUPT_AFTER_RECORD:-0}" = 1 ]]; then
    exit 97
  fi
  reconcile_log_best_effort
  emit_record "$verify_record_path"
  exit "$(record_exit_code "$verify_record_path")"
}

resolve_verify_step_from_state() {
  python3 - "$1" <<'PY' 2>/dev/null || true
import json
import math
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as f:
        current_step = json.load(f).get("current_step")
    if isinstance(current_step, bool):
        raise ValueError
    if isinstance(current_step, int):
        print(current_step)
    elif isinstance(current_step, float) and math.isfinite(current_step) and current_step.is_integer():
        print(int(current_step))
except Exception:
    pass
PY
}

resolve_verify_record_path() {
  python3 - "$bundle_dir" "${ATTEMPT_DIR:-}" <<'PY'
import os
import re
import sys

bundle_dir = os.path.realpath(sys.argv[1])
attempt_dir = sys.argv[2]
attempts_root = os.path.join(bundle_dir, "attempts")

def safe_attempt_record(candidate: str):
    if not candidate:
        return None
    try:
        real = os.path.realpath(candidate)
    except OSError:
        return None
    if re.fullmatch(r"[0-9]+", os.path.basename(real)) and os.path.isdir(real):
        prefix = attempts_root + os.sep
        if real.startswith(prefix):
            return os.path.join(real, "verify.json")
    return None

def is_openable_directory(path: str):
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        fd = os.open(path, flags)
    except OSError:
        return False
    os.close(fd)
    return True

def reject(reason: str):
    print(f"verify-job record path error: {reason}", file=sys.stderr)
    raise SystemExit(7)

if attempt_dir:
    candidate = os.path.normpath(os.path.abspath(attempt_dir))
    if os.path.basename(os.path.dirname(candidate)) != "attempts" or os.path.islink(candidate):
        reject("explicit ATTEMPT_DIR contains a linked path component")
    selected = safe_attempt_record(candidate)
    if selected is None:
        reject("explicit ATTEMPT_DIR is not a real numeric directory inside the bundle attempts directory")
    print(selected)
    raise SystemExit(0)

if os.path.lexists(attempts_root):
    if os.path.islink(attempts_root) or not os.path.isdir(attempts_root):
        reject("bundle attempts entry is not a real directory")
    numeric_dirs = []
    try:
        with os.scandir(attempts_root) as entries:
            for entry in entries:
                if re.fullmatch(r"[0-9]+", entry.name) is None:
                    continue
                if entry.is_symlink():
                    reject(f"numeric attempt entry is not a real directory: {entry.name}")
                if not entry.is_dir(follow_symlinks=False) or not is_openable_directory(entry.path):
                    continue
                record_path = safe_attempt_record(entry.path)
                if record_path is None:
                    reject(f"numeric attempt directory escaped bundle containment: {entry.name}")
                significant = entry.name.lstrip("0") or "0"
                numeric_dirs.append((len(significant), significant, entry.name, record_path))
    except OSError:
        reject("bundle attempts directory cannot be opened")
    if numeric_dirs:
        numeric_dirs.sort()
        print(numeric_dirs[-1][3])
        raise SystemExit(0)

print(os.path.join(bundle_dir, "verify.json"))
PY
}

summarize_timeout_tail() {
  python3 - "$1" "$2" <<'PY'
import re
import sys
import os

stdout_path, stderr_path = sys.argv[1:3]
MAX_BYTES = 8192

def summarize(path: str) -> str:
    try:
        size = os.path.getsize(path)
        with open(path, "rb") as f:
            if size > MAX_BYTES:
                f.seek(size - MAX_BYTES)
            data = f.read(MAX_BYTES)
    except OSError:
        return "<missing>"
    text = data.decode("utf-8", errors="replace")
    lines = text.splitlines()[-10:]
    if not lines:
        return "<empty>"
    cleaned = []
    for line in lines:
        line = "".join(" " if ord(ch) < 32 or ord(ch) == 127 else ch for ch in line)
        line = re.sub(r"\s+", " ", line).strip()
        if line:
            cleaned.append(line)
    if not cleaned:
        return "<blank>"
    joined = " || ".join(cleaned)
    if len(joined) > 240:
        joined = "..." + joined[-237:]
    return joined

print(f"stdout_tail={summarize(stdout_path)}; stderr_tail={summarize(stderr_path)}")
PY
}

parse_provider_output() {
  python3 - "$1" <<'PY'
import json
import re
import shlex
import sys
import unicodedata

path = sys.argv[1]
allowed = (
    "pass",
    "fail",
    "inconclusive",
    "rubric-invalid",
    "needs-human",
    "blocked-missing-artifact",
)
verdict_re = re.compile(r"^VERDICT: ([a-z-]+)$")
marker_re = re.compile(r"VERDICT\s*:")

def emit(verdict: str, reason: str):
    print("parsed_verdict=%s" % shlex.quote(verdict))
    print("parsed_reason=%s" % shlex.quote(reason))

def contract(reason: str):
    emit("contract-violation", f"call-site=verifier class=contract-violation; {reason}")
    raise SystemExit(0)

def sanitize_reason(line: str) -> str:
    cleaned = "".join(
        ch for ch in line
        if unicodedata.category(ch) not in ("Cc", "Cf")
    )
    return cleaned.rstrip()

try:
    raw = open(path, "rb").read()
except OSError:
    contract("provider output could not be read")

if b"\x00" in raw:
    contract("provider output contains a NUL byte")

try:
    text = raw.decode("utf-8")
except UnicodeDecodeError:
    contract("provider output is not valid UTF-8")

raw_lines = text.split("\n")
# NFKC folds confusables before counting markers: U+00A0 becomes ASCII space,
# U+FF1A becomes ':', and we also strip '\r' so CRLF cannot hide marker
# position or fabricate a distinct reason line.
normalized_lines = [unicodedata.normalize("NFKC", line.replace("\r", "")) for line in raw_lines]
marker_count = sum(len(marker_re.findall(line)) for line in normalized_lines)
if marker_count == 0:
    contract("provider output is missing the verdict marker")
if marker_count > 1:
    contract("provider output contains multiple verdict markers after normalization")

match = verdict_re.fullmatch(normalized_lines[0])
if match is None:
    if any(verdict_re.fullmatch(line) for line in normalized_lines[1:]):
        contract("provider output placed the verdict marker outside line 1")
    contract("provider output line 1 is not exactly VERDICT: <allowed>")

verdict = match.group(1)
if verdict not in allowed:
    contract(f"provider output used an unknown verdict: {verdict}")

if len(normalized_lines) < 2:
    contract("provider output is missing the required line-2 reason")
reason = sanitize_reason(normalized_lines[1])
if reason == "" or reason.strip() == "":
    contract("provider output line 2 reason is empty")

emit(verdict, reason)
PY
}

if (($# != 1)); then
  usage
  exit 2
fi

if [[ ! -d "$1" || -L "$1" ]]; then
  usage
  exit 2
fi

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$repo_root/scripts/lib-classify.sh"
source "$repo_root/scripts/lib-bounded.sh"
source "$repo_root/scripts/lib-wrapper-conformance.sh"
source "$repo_root/scripts/lib-pause.sh"
VERIFY_TIMEOUT_S=$(resolve_timeout_env VERIFY_TIMEOUT_S 300)
VERIFY_GRACE_S=$(resolve_timeout_env VERIFY_GRACE_S 10 1)

# A verifier grace at or above its timeout silently makes cleanup outlive the verification window.
if (( VERIFY_GRACE_S >= VERIFY_TIMEOUT_S )); then
  printf 'verify-job.sh: ordering invariant failed: VERIFY_GRACE_S(value=%s) < VERIFY_TIMEOUT_S(value=%s)\n' \
    "$VERIFY_GRACE_S" "$VERIFY_TIMEOUT_S" >&2
  exit 2
fi
bundle_dir=$(caty_pause_canonical_workspace "$1" 2>/dev/null) || {
  usage
  exit 2
}
workspace_root=$(caty_pause_canonical_workspace "$bundle_dir/../../.." 2>/dev/null) || {
  usage
  exit 2
}
pause_state=$(caty_pause_workspace_state "$workspace_root")
if [[ "$pause_state" != enabled ]]; then
  caty_pause_status_record "$workspace_root" hermes-verify-job
  exit 0
fi
task_id=$(basename "$bundle_dir")
if [[ -z "${VERIFY_STEP:-}" && -f "$bundle_dir/state.json" ]]; then
  derived_verify_step=$(resolve_verify_step_from_state "$bundle_dir/state.json")
  if [[ "$derived_verify_step" =~ ^[1-9][0-9]*$ ]]; then
    VERIFY_STEP=$derived_verify_step
  fi
fi
verifier_cmd=${VERIFIER_CMD:-}
verifier_id=${VERIFIER_ID:-unconfigured}
verify_record_status=0
verify_record_path=$(resolve_verify_record_path) || verify_record_status=$?
if ((verify_record_status != 0)); then
  infra_fail "unsafe verify record target"
fi

verifier_stderr=
verifier_stdout_file=
# shellcheck disable=SC2329
cleanup_verify_job() {
  rm -f "${verifier_stderr:-}" "${verifier_stdout_file:-}"
  wrapper_conformance_cleanup_stage "$WRAPPER_CONFORMANCE_STAGE_DIR"
}
trap cleanup_verify_job EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if ! wrapper_conformance_gate verifier VERIFIER_CMD "$verifier_cmd"; then
  infra_fail "wrapper conformance failed: $WRAPPER_CONFORMANCE_REASON"
fi
verifier_id=${VERIFIER_ID:-$WRAPPER_CONFORMANCE_WRAPPER_PATH}
verifier_argv=("$WRAPPER_CONFORMANCE_STAGED_PATH")
reconcile_log_best_effort
if [[ "${HERMES_VERIFY_TEST_STOP_AFTER_RECONCILE:-0}" = 1 ]]; then
  exit 98
fi

required_files=(
  request.md
  rubric.md
  result.md
  manifest.md
  evidence.md
  metadata.json
)

missing=()
for file in "${required_files[@]}"; do
  if [[ ! -f "$bundle_dir/$file" || -L "$bundle_dir/$file" ]]; then
    missing+=("$file")
  fi
done

if ((${#missing[@]} > 0)); then
  finish_with_record "blocked-missing-artifact" "missing required artifact(s): ${missing[*]}"
fi

# Keep the whole request below Linux MAX_ARG_STRLEN (128KiB per argument).
# The override exists for adapter integration tests and constrained deployments.
bundle_max_bytes=${HERMES_VERIFY_BUNDLE_MAX_BYTES:-100000}
case "$bundle_max_bytes" in
  ''|*[!0-9]*)
    infra_fail "HERMES_VERIFY_BUNDLE_MAX_BYTES must be an integer from 1024 to 120000"
    ;;
esac
if ! normalized_bundle_max=$(python3 - "$bundle_max_bytes" <<'PY'
import sys

value = int(sys.argv[1], 10)
if not 1024 <= value <= 120000:
    raise SystemExit(1)
print(value)
PY
); then
  infra_fail "HERMES_VERIFY_BUNDLE_MAX_BYTES must be an integer from 1024 to 120000"
fi
bundle_max_bytes=$normalized_bundle_max

prompt_status=0
prompt=$(python3 - "$repo_root/templates/VERIFY-BUNDLE.tmpl.md" "$bundle_dir" "$bundle_max_bytes" <<'PY'
import os
import re
import stat
import sys

template_path, bundle_dir, cap_text = sys.argv[1:4]
cap = int(cap_text)
template = open(template_path, "rb").read()

def read_single_link_regular(name):
    path = os.path.join(bundle_dir, name)
    try:
        before = os.lstat(path)
        if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
            raise OSError
        flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
        fd = os.open(path, flags)
        try:
            opened = os.fstat(fd)
            if (
                not stat.S_ISREG(opened.st_mode)
                or opened.st_nlink != 1
                or (before.st_dev, before.st_ino) != (opened.st_dev, opened.st_ino)
            ):
                raise OSError
            with os.fdopen(fd, "rb", closefd=False) as source:
                return source.read()
        finally:
            os.close(fd)
    except OSError:
        raise SystemExit(4)

request = read_single_link_regular("request.md")
rubric = read_single_link_regular("rubric.md")
if b"\x00" in request or b"\x00" in rubric:
    raise SystemExit(3)

output_names = ("result.md", "manifest.md", "evidence.md")
outputs = {}
for name in output_names:
    path = os.path.abspath(os.path.join(bundle_dir, name))
    raw = read_single_link_regular(name).replace(b"\x00", b"\xef\xbf\xbd")
    pointer = ("[source: %s]\n" % path).encode("utf-8")
    outputs[name] = (raw, pointer)

tokens = {
    b"{{BUNDLE_MAX_BYTES}}": str(cap).encode("ascii"),
    b"{{REQUEST_MD}}": request,
    b"{{RUBRIC_MD}}": rubric,
    b"{{RESULT_SECTION}}": b"",
    b"{{MANIFEST_SECTION}}": b"",
    b"{{EVIDENCE_SECTION}}": b"",
}
pattern = re.compile(b"|".join(re.escape(token) for token in tokens))

def render(values):
    return pattern.sub(lambda match: values[match.group(0)], template)

status_reserve = 128
planning = dict(tokens)
for token, name in (
    (b"{{RESULT_SECTION}}", "result.md"),
    (b"{{MANIFEST_SECTION}}", "manifest.md"),
    (b"{{EVIDENCE_SECTION}}", "evidence.md"),
):
    planning[token] = outputs[name][1]
fixed = len(render(planning)) + status_reserve * len(output_names)
if fixed > cap:
    raise SystemExit(3)
excerpt_cap = (cap - fixed) // len(output_names)

values = dict(tokens)
for token, name in (
    (b"{{RESULT_SECTION}}", "result.md"),
    (b"{{MANIFEST_SECTION}}", "manifest.md"),
    (b"{{EVIDENCE_SECTION}}", "evidence.md"),
):
    raw, pointer = outputs[name]
    if len(raw) <= excerpt_cap:
        excerpt = raw
        status = "[complete: %d bytes]\n" % len(raw)
    else:
        tail = raw[-excerpt_cap:] if excerpt_cap else b""
        while tail and 0x80 <= tail[0] <= 0xBF:
            tail = tail[1:]
        excerpt = tail.decode("utf-8", errors="ignore").encode("utf-8")
        status = "[truncated: showing final %d of %d bytes]\n" % (len(excerpt), len(raw))
    status_bytes = status.encode("ascii")
    if len(status_bytes) > status_reserve:
        raise SystemExit(3)
    values[token] = pointer + status_bytes + excerpt

prompt = render(values)
if len(prompt) > cap:
    raise SystemExit(3)
sys.stdout.buffer.write(prompt)
PY
) || prompt_status=$?

if ((prompt_status == 3)); then
  finish_with_record \
    "needs-human" \
    "verbatim request/rubric exceed Hermes verifier bundle cap (${bundle_max_bytes} bytes) or contain unsupported NUL bytes"
elif ((prompt_status == 4)); then
  finish_with_record "blocked-missing-artifact" "unsafe required artifact link or file type"
elif ((prompt_status != 0)); then
  infra_fail "failed to assemble verifier bundle"
fi

verifier_stderr=$(mktemp "${TMPDIR:-/tmp}/verify-job.stderr.XXXXXX")
verifier_stdout_file=$(mktemp "${TMPDIR:-/tmp}/verify-job.stdout.XXXXXX")

set +e
FABLE_CONFORMING_PROVIDER_PATH="$WRAPPER_CONFORMANCE_STAGED_PROVIDER_PATH" \
run_bounded "$VERIFY_TIMEOUT_S" "$VERIFY_GRACE_S" "${verifier_argv[@]}" "$prompt" \
  >"$verifier_stdout_file" 2>"$verifier_stderr"
verifier_status=$?
set -e
cat "$verifier_stderr" >&2

if ((verifier_status == 124)); then
  timeout_tail=$(summarize_timeout_tail "$verifier_stdout_file" "$verifier_stderr")
  finish_with_record \
    "inconclusive" \
    "call-site=verifier class=transient; wall-clock timeout after ${VERIFY_TIMEOUT_S}s; ${timeout_tail}"
elif ((verifier_status > 128)); then
  finish_with_record \
    "inconclusive" \
    "call-site=verifier class=transient; verifier command was killed (signal $((verifier_status - 128)))"
elif ((verifier_status != 0)); then
  failure_class=$(classify_failure "$verifier_status" "$verifier_stderr")
  finish_with_record \
    "needs-human" \
    "call-site=verifier class=$failure_class; verifier command exited $verifier_status"
fi

eval "$(parse_provider_output "$verifier_stdout_file")"
finish_with_record "$parsed_verdict" "$parsed_reason"
