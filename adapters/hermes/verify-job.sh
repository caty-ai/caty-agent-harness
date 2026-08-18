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

ensure_log() {
  if [[ ! -e "$log_path" ]]; then
    printf '%s\n' '# VERIFY log — append-only verifier verdict history' >"$log_path"
  fi
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

  python3 - "$record_path" "$log_path" "$task_id" <<'PY'
import json
import sys

record_path, log_path, task_id = sys.argv[1:4]
with open(record_path, encoding="utf-8") as f:
    record = json.load(f)

step = record.get("step")
step_field = ""
if step not in (None, ""):
    step_field = f" | step={step}"

with open(log_path, "a", encoding="utf-8") as log:
    log.write(
        f"- {record['ts']} | task={task_id}{step_field} | verifier={record['verifier_id']} | "
        f"verdict={record['verdict']} | {record['reason']}\n"
    )

print(f"VERDICT: {record['verdict']}")
print(record["reason"])
PY
}

write_record() {
  local record_path=$1
  local verdict=$2
  local reason=$3
  local tmp="$record_path.tmp.$$"

  python3 - "$tmp" "$verdict" "$reason" "$verifier_id" "${VERIFY_STEP:-}" <<'PY'
import json
import sys
import unicodedata
from datetime import datetime, timezone

tmp, verdict, reason, verifier_id, step_text = sys.argv[1:6]
step = None
if step_text:
    step = int(step_text)
sanitized_reason = "".join(
    " " if ch in "\r\n" else ch
    for ch in reason
    if unicodedata.category(ch) not in ("Cc", "Cf")
)
sanitized_reason = sanitized_reason.rstrip()
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(
        {
            "verdict": verdict,
            "reason": sanitized_reason,
            "verifier_id": verifier_id,
            "step": step,
            "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        },
        f,
        indent=2,
        sort_keys=True,
    )
    f.write("\n")
PY
  mv "$tmp" "$record_path"
}

finish_with_record() {
  local verdict=$1
  local reason=$2

  write_record "$verify_record_path" "$verdict" "$reason"
  ensure_log
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
    if os.path.basename(real).isdigit() and os.path.isdir(real):
        prefix = attempts_root + os.sep
        if real.startswith(prefix):
            return os.path.join(real, "verify.json")
    return None

selected = safe_attempt_record(attempt_dir)
if selected:
    print(selected)
    raise SystemExit(0)

if os.path.isdir(attempts_root):
    numeric_dirs = []
    for entry in os.scandir(attempts_root):
        if entry.is_dir() and entry.name.isdigit():
            numeric_dirs.append((int(entry.name), entry.path))
    if numeric_dirs:
        numeric_dirs.sort()
        print(os.path.join(numeric_dirs[-1][1], "verify.json"))
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
        joined = joined[:237] + "..."
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
if not normalized_lines:
    contract("provider output is empty")

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
log_path="$workspace_root/loop/VERIFY.log.md"
task_id=$(basename "$bundle_dir")
if [[ -z "${VERIFY_STEP:-}" && -f "$bundle_dir/state.json" ]]; then
  derived_verify_step=$(resolve_verify_step_from_state "$bundle_dir/state.json")
  if [[ "$derived_verify_step" =~ ^[1-9][0-9]*$ ]]; then
    VERIFY_STEP=$derived_verify_step
  fi
fi
verifier_cmd=${VERIFIER_CMD:-}
verifier_id=${VERIFIER_ID:-unconfigured}
verify_record_path=$(resolve_verify_record_path)

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
VERIFY_TIMEOUT_S=$(resolve_timeout_env VERIFY_TIMEOUT_S 300)
VERIFY_GRACE_S=$(resolve_timeout_env VERIFY_GRACE_S 10 1)

set +e
FABLE_CONFORMING_PROVIDER_PATH="$WRAPPER_CONFORMANCE_STAGED_PROVIDER_PATH" \
run_bounded "$VERIFY_TIMEOUT_S" "$VERIFY_GRACE_S" "${verifier_argv[@]}" "$prompt" \
  >"$verifier_stdout_file" 2>"$verifier_stderr"
verifier_status=$?
set -e

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
