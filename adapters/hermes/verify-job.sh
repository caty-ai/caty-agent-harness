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

trim_line() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

ensure_log() {
  if [[ ! -e "$log_path" ]]; then
    printf '%s\n' '# VERIFY log — append-only verifier verdict history' >"$log_path"
  fi
}

append_log() {
  local verdict=$1
  local reason=$2
  local timestamp
  local step_field=''

  # VERIFY_STEP (optional): plan-step number for step-scoped re-injection
  # (task-runner only re-injects findings whose step matches the current step;
  # entries without a step field are never re-injected).
  if [[ -n "${VERIFY_STEP:-}" ]]; then
    step_field=" | step=${VERIFY_STEP}"
  fi
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  reason=$(trim_line "$reason")
  ensure_log
  printf -- '- %s | task=%s%s | verifier=%s | verdict=%s | %s\n' \
    "$timestamp" "$task_id" "$step_field" "$verifier_id" "$verdict" "$reason" >>"$log_path"
}

exit_for_verdict() {
  case "$1" in
    pass)
      exit 0
      ;;
    fail|rubric-invalid)
      exit 1
      ;;
    blocked-missing-artifact)
      exit 3
      ;;
    inconclusive|needs-human)
      exit 4
      ;;
    *)
      exit 4
      ;;
  esac
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
  derived_verify_step=$(python3 - "$bundle_dir/state.json" <<'PY' 2>/dev/null || true
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
    else:
        raise ValueError
except Exception:
    pass
PY
)
  if [[ "$derived_verify_step" =~ ^[1-9][0-9]*$ ]]; then
    VERIFY_STEP=$derived_verify_step
  fi
fi
verifier_cmd=${VERIFIER_CMD:-}
verifier_id=${VERIFIER_ID:-unconfigured}

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
  reason="missing required artifact(s): ${missing[*]}"
  append_log "blocked-missing-artifact" "$reason"
  printf 'VERDICT: blocked-missing-artifact\n'
  exit 3
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

# Reserve a fixed status-line budget per bounded output, then split the
# remaining bytes evenly. Unused shares stay unused so no file can starve its
# siblings or make ordering affect the cap.
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
  reason="verbatim request/rubric exceed Hermes verifier bundle cap (${bundle_max_bytes} bytes) or contain unsupported NUL bytes"
  append_log "needs-human" "$reason"
  printf 'VERDICT: needs-human\n'
  exit 4
elif ((prompt_status == 4)); then
  reason="unsafe required artifact link or file type"
  append_log "blocked-missing-artifact" "$reason"
  printf 'VERDICT: blocked-missing-artifact\n'
  exit 3
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
  verdict="inconclusive"
  reason="call-site=verifier class=transient; wall-clock timeout after ${VERIFY_TIMEOUT_S}s"
elif ((verifier_status > 128)); then
  verdict="inconclusive"
  reason="call-site=verifier class=transient; verifier command was killed (signal $((verifier_status - 128)))"
elif ((verifier_status != 0)); then
  failure_class=$(classify_failure "$verifier_status" "$verifier_stderr")
  verdict="needs-human"
  reason="call-site=verifier class=$failure_class; verifier command exited $verifier_status"
else
  verifier_output=$(cat "$verifier_stdout_file")
  parsed=$(
    printf '%s\n' "$verifier_output" | awk '
      /^VERDICT:/ {
        verdict_line = $0
        reason_line = ""
        if (getline next_line > 0) {
          reason_line = next_line
        }
      }
      END {
        if (verdict_line != "") {
          print verdict_line
          print reason_line
        }
      }
    '
  )

  if [[ -z "$parsed" ]]; then
    verdict="inconclusive"
    reason="verifier response missing VERDICT line"
  else
    verdict_line=$(printf '%s\n' "$parsed" | sed -n '1p')
    reason=$(printf '%s\n' "$parsed" | sed -n '2p')
    verdict=${verdict_line#VERDICT: }
    case "$verdict" in
      pass|fail|inconclusive|rubric-invalid|needs-human|blocked-missing-artifact)
        if [[ -z "$(trim_line "$reason")" ]]; then
          reason="verifier response missing one-line reason"
        fi
        ;;
      *)
        reason="verifier returned invalid verdict: $verdict"
        verdict="inconclusive"
        ;;
    esac
  fi
fi

append_log "$verdict" "$reason"
cat "$verifier_stderr" >&2
printf 'VERDICT: %s\n' "$verdict"
exit_for_verdict "$verdict"
