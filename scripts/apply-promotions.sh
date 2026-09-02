#!/usr/bin/env bash
set -u

usage() {
  printf 'usage: apply-promotions.sh --workspace <path> [--auto-capability-facts] [--approve <theme-id>]... [--approve-file <path>]...\n' >&2
  printf '       apply-promotions.sh --workspace <path> --rollback <theme-id> --reason <ref>\n' >&2
}

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
# shellcheck disable=SC1091
source "$repo_root/scripts/lib-pause.sh"
# shellcheck disable=SC1091
source "$repo_root/scripts/lib-state-fold.sh"
# lib-state-fold is also a standalone library and enables errexit.  Apply owns
# the documented {0,1,2} exit map and inspects every failure explicitly.
set +e

workspace=
auto_capability_facts=0
rollback_id=
rollback_reason=
usage_error=0
cli_approvals=
approval_manifests=

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace)
      if [[ $# -ge 2 && -z "$workspace" ]]; then workspace=$2; shift 2; else usage_error=1; break; fi
      ;;
    --auto-capability-facts)
      if [[ "$auto_capability_facts" -eq 0 ]]; then auto_capability_facts=1; shift; else usage_error=1; break; fi
      ;;
    --approve)
      if [[ $# -ge 2 ]]; then cli_approvals=$cli_approvals$2$'\n'; shift 2; else usage_error=1; break; fi
      ;;
    --approve-file)
      if [[ $# -ge 2 ]]; then approval_manifests=$approval_manifests$2$'\n'; shift 2; else usage_error=1; break; fi
      ;;
    --rollback)
      if [[ $# -ge 2 && -z "$rollback_id" ]]; then rollback_id=$2; shift 2; else usage_error=1; break; fi
      ;;
    --reason)
      if [[ $# -ge 2 && -z "$rollback_reason" ]]; then rollback_reason=$2; shift 2; else usage_error=1; break; fi
      ;;
    *) usage_error=1; break ;;
  esac
done

if [[ "$usage_error" -ne 0 || -z "$workspace" ]]; then usage; exit 2; fi
if [[ -n "$rollback_id" ]]; then
  if [[ -z "$rollback_reason" || "$auto_capability_facts" -ne 0 || -n "$cli_approvals" || -n "$approval_manifests" ]]; then
    usage
    exit 2
  fi
elif [[ -n "$rollback_reason" ]]; then
  usage
  exit 2
fi

workspace=$(caty_pause_canonical_workspace "$workspace" 2>/dev/null) || { usage; exit 2; }
if ! caty_pause_validate_initialized_workspace "$workspace"; then
  printf 'apply-promotions: workspace layout is untrusted\n' >&2
  exit 1
fi
pause_state=$(caty_pause_workspace_state "$workspace")
index_decision_table=$(cat <<'EOF'
promoted terminal
rolled-back terminal
duplicate-content terminal
hygiene terminal
parse terminal
superseded terminal
supersedes-not-owned terminal
k-below-2 terminal
weeks-below-min terminal
stub-exists terminal
awaiting-approval pending
section-full pending
volume-guard pending
supersedes-ambiguous pending
EOF
)
reason_token_list=$(cat <<'EOF'
hygiene
parse
rollback-refused
input-untrusted
already-applied
duplicate-content
superseded
supersedes-not-owned
supersedes-ambiguous
awaiting-approval
unknown-approval
k-below-2
weeks-below-min
section-full
volume-guard
stub-exists
stub-replay
stub-dirty
caps-read-failed
lock-busy
skipped-paused
already-rolled-back
config
EOF
)

index_decision_state() {
  local token=${1-}
  awk -v token="$token" '$1 == token { print $2; found=1; exit } END { if (!found) exit 1 }' <<EOF
$index_decision_table
EOF
}

terminal_decision() { [[ "$(index_decision_state "${1-}" 2>/dev/null)" == terminal ]]; }
pending_decision() { [[ "$(index_decision_state "${1-}" 2>/dev/null)" == pending ]]; }

umask 077
promotions_dir=$workspace/loop/promotions
state_file=$workspace/STATE.md
apply_log=$promotions_dir/apply.log
apply_index=$promotions_dir/apply-index.tsv
apply_lock_dir=$promotions_dir/.apply.lock
promotions_lock_dir=$promotions_dir/.lock
skills_root=$workspace/skills
staging_root=$workspace/skills/_staging
if [[ ! -d "$skills_root" || -L "$skills_root" ]]; then
  printf 'apply-promotions: skills path is untrusted\n' >&2
  exit 1
fi
if [[ -L "$staging_root" || ( -e "$staging_root" && ! -d "$staging_root" ) ]]; then
  printf 'apply-promotions: staging path is untrusted\n' >&2
  exit 1
fi
if [[ -L "$promotions_dir" || ( -e "$promotions_dir" && ! -d "$promotions_dir" ) ]]; then
  printf 'apply-promotions: promotions path is untrusted\n' >&2
  exit 1
fi
mkdir -p "$promotions_dir" || exit 1
if [[ ( -e "$apply_log" && ( ! -f "$apply_log" || -L "$apply_log" ) ) \
  || ( -e "$apply_index" && ( ! -f "$apply_index" || -L "$apply_index" ) ) ]]; then
  printf 'apply-promotions: apply ledger path is untrusted\n' >&2
  exit 1
fi

apply_lock_owned=0
promotions_lock_owned=0
tmp_root=
receipts=
results=
promoted_count=0
rolled_back_count=0
skipped_count=0
pending_count=0

# Invoked by traps below.
# shellcheck disable=SC2329
cleanup() {
  if [[ "${STATE_FOLD_LOCK_OWNED:-0}" -eq 1 ]]; then release_state_lock; fi
  if [[ "$promotions_lock_owned" -eq 1 ]]; then rm -rf "$promotions_lock_dir"; promotions_lock_owned=0; fi
  if [[ "$apply_lock_owned" -eq 1 ]]; then rm -rf "$apply_lock_dir"; apply_lock_owned=0; fi
  [[ -n "$tmp_root" ]] && rm -rf "$tmp_root"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

parse_decimal_config() {
  local raw=${1-} minimum=$2 maximum=${3-} parsed
  case "$raw" in ''|*[!0-9]*) return 1 ;; esac
  parsed=$((10#$raw)) 2>/dev/null || return 1
  (( parsed >= minimum )) || return 1
  if [[ -n "$maximum" ]] && (( parsed > maximum )); then return 1; fi
  printf '%s\n' "$parsed"
}

parse_positive_decimal() { parse_decimal_config "${1-}" 1; }

max_per_section=${APPLY_MAX_PER_SECTION:-20}
max_auto=${APPLY_MAX_AUTO:-10}
apply_lock_attempts=${APPLY_LOCK_ATTEMPTS:-3}
promotions_lock_attempts=${APPLY_PROMOTIONS_LOCK_ATTEMPTS:-3}
state_lock_attempts=${APPLY_STATE_LOCK_ATTEMPTS:-30}
lock_sleep=${APPLY_LOCK_SLEEP_S:-1}
state_lock_sleep=${APPLY_STATE_LOCK_SLEEP_S:-1}
lock_stale=${APPLY_LOCK_STALE_S:-1800}

max_per_section=$(parse_positive_decimal "$max_per_section") || { printf 'apply-promotions: invalid positive decimal configuration\n' >&2; exit 2; }
max_auto=$(parse_positive_decimal "$max_auto") || { printf 'apply-promotions: invalid positive decimal configuration\n' >&2; exit 2; }
apply_lock_attempts=$(parse_positive_decimal "$apply_lock_attempts") || { printf 'apply-promotions: invalid positive decimal configuration\n' >&2; exit 2; }
promotions_lock_attempts=$(parse_positive_decimal "$promotions_lock_attempts") || { printf 'apply-promotions: invalid positive decimal configuration\n' >&2; exit 2; }
state_lock_attempts=$(parse_positive_decimal "$state_lock_attempts") || { printf 'apply-promotions: invalid positive decimal configuration\n' >&2; exit 2; }
lock_stale=$(parse_positive_decimal "$lock_stale") || { printf 'apply-promotions: invalid positive decimal configuration\n' >&2; exit 2; }
case "$lock_sleep" in ''|*[!0-9]*) printf 'apply-promotions: invalid lock sleep\n' >&2; exit 2 ;; esac
case "$state_lock_sleep" in ''|*[!0-9]*) printf 'apply-promotions: invalid state lock sleep\n' >&2; exit 2 ;; esac

run_ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
run_date=${run_ts%%T*}
apply_id=$(date -u '+%Y%m%dT%H%M%SZ')-$$

safe_receipt_value() {
  case "${1-}" in ''|*[!A-Za-z0-9._+:#/@=-]*) return 1 ;; esac
}

append_direct() {
  # Shell >> opens regular files with O_APPEND.  This is intentionally used only
  # for append-only receipts, never for STATE.md or apply-index.tsv.
  printf '%s\n' "$1" >>"$apply_log"
}

lock_mtime() {
  stat -c '%Y' "$1" 2>/dev/null || stat -f '%m' "$1" 2>/dev/null || printf '0\n'
}

take_mkdir_lock() {
  local path=$1 label=$2 attempts_limit=$3 attempts=0 now mtime age
  while (( attempts < attempts_limit )); do
    if mkdir "$path" 2>/dev/null; then
      printf '%s %s\n' "$$" "$label" >"$path/pid"
      return 0
    fi
    attempts=$((attempts + 1))
    now=$(date -u '+%s')
    mtime=$(lock_mtime "$path")
    case "$mtime" in ''|*[!0-9]*) mtime=0 ;; esac
    age=$((now - mtime))
    if (( age > lock_stale )); then rm -rf "$path"; continue; fi
    (( attempts < attempts_limit )) && sleep "$lock_sleep"
  done
  return 1
}

take_apply_lock() {
  if take_mkdir_lock "$apply_lock_dir" apply-promotions "$apply_lock_attempts"; then apply_lock_owned=1; return 0; fi
  return 1
}

take_promotions_lock() {
  if take_mkdir_lock "$promotions_lock_dir" apply-promotions "$promotions_lock_attempts"; then promotions_lock_owned=1; return 0; fi
  return 1
}

release_promotions_lock() {
  if [[ "$promotions_lock_owned" -eq 1 ]]; then rm -rf "$promotions_lock_dir"; promotions_lock_owned=0; fi
}

summary_with_reason() {
  local reason=$1 summary token token_count
  summary="decision=run-summary applyid=$apply_id promoted=$promoted_count rolled-back=$rolled_back_count skipped=$skipped_count pending=$pending_count"
  while IFS= read -r token || [[ -n "$token" ]]; do
    [[ -n "$token" ]] || continue
    if [[ -n "${results:-}" && -f "$results" ]]; then
      token_count=$(awk -F '\t' -v token="$token" '$3 == "skipped" && $4 == token {n++} END {print n+0}' "$results")
    else
      token_count=0
    fi
    summary="$summary skipped-$token=$token_count"
  done <<EOF
$reason_token_list
EOF
  printf '%s reason=%s\n' "$summary" "$reason"
}

append_summary_line() {
  local summary_line=$1
  if [[ "${2:-0}" -eq 1 ]] && take_promotions_lock; then
    append_direct "$summary_line"
    release_promotions_lock
  else
    append_direct "$summary_line"
  fi
}

lock_busy_summary() {
  append_summary_line "$(summary_with_reason lock-busy)" "${1:-0}"
}

if ! take_apply_lock; then lock_busy_summary; exit 1; fi

if [[ "$pause_state" != enabled ]]; then
  paused_summary="decision=run-summary applyid=$apply_id promoted=0 rolled-back=0 skipped=1 pending=0"
  while IFS= read -r token || [[ -n "$token" ]]; do
    [[ -n "$token" ]] || continue
    if [[ "$token" == skipped-paused ]]; then
      paused_summary="$paused_summary skipped-$token=1"
    else
      paused_summary="$paused_summary skipped-$token=0"
    fi
  done <<EOF
$reason_token_list
EOF
  paused_summary="$paused_summary reason=skipped-paused"
  if take_promotions_lock; then append_direct "$paused_summary"; release_promotions_lock
  else append_direct "$paused_summary"
  fi
  exit 0
fi

tmp_root=$(mktemp -d "$workspace/.apply-promotions.XXXXXX") || exit 1

conf=$workspace/loop/review.conf
recurrence_unit=sessions
promote_min_k=2
promote_min_weeks=0
config_invalid=0
carriage_return=$(printf '\r')
if [[ ! -f "$conf" || -L "$conf" ]]; then
  config_invalid=1
else
  while IFS= read -r config_line || [[ -n "$config_line" ]]; do
    config_line=${config_line%"$carriage_return"}
    config_line=${config_line#"${config_line%%[![:space:]]*}"}
    case "$config_line" in
      recurrence_unit=*) recurrence_unit=${config_line#recurrence_unit=} ;;
      promote_min_k=*) promote_min_k=${config_line#promote_min_k=} ;;
      promote_min_weeks=*) promote_min_weeks=${config_line#promote_min_weeks=} ;;
    esac
  done <"$conf"
fi
promote_min_k=$(parse_decimal_config "$promote_min_k" 1) || config_invalid=1
promote_min_weeks=$(parse_decimal_config "$promote_min_weeks" 0) || config_invalid=1
case "$recurrence_unit" in sessions|weeks) ;; *) config_invalid=1 ;; esac
if [[ "$config_invalid" -ne 0 ]]; then
  printf 'apply-promotions: invalid review configuration\n' >&2
  results=$tmp_root/config-results
  printf '%s\t%s\t%s\t%s\n' - - skipped config >"$results"
  skipped_count=1
  append_summary_line "$(summary_with_reason config)" 1
  exit 2
fi

approval_file=$tmp_root/approvals
: >"$approval_file"
if [[ -n "$cli_approvals" ]]; then printf '%s' "$cli_approvals" >>"$approval_file"; fi

while IFS= read -r manifest || [[ -n "$manifest" ]]; do
  [[ -n "$manifest" ]] || continue
  if [[ ! -f "$manifest" || -L "$manifest" ]]; then
    printf 'apply-promotions: approval manifest must be a regular non-symlink file: %s\n' "$manifest" >&2
    exit 1
  fi
  if ! python3 -B - "$manifest" "$approval_file" <<'PY'
from pathlib import Path
import re, sys
p = Path(sys.argv[1])
try:
    text = p.read_text(encoding="utf-8", errors="strict")
except (OSError, UnicodeError):
    raise SystemExit(1)
with open(sys.argv[2], "a", encoding="utf-8", newline="\n") as out:
    for raw in text.splitlines():
        if not raw or raw.startswith("#"):
            continue
        if not re.fullmatch(r"[A-Za-z0-9._+:#/-]+", raw):
            raise SystemExit(1)
        out.write(raw + "\n")
PY
  then
    printf 'apply-promotions: invalid approval manifest\n' >&2
    exit 1
  fi
done <<EOF
$approval_manifests
EOF

while IFS= read -r approval || [[ -n "$approval" ]]; do
  [[ -n "$approval" ]] || continue
  if ! safe_receipt_value "$approval" || [[ "$approval" == *'@'* || "$approval" == *'='* ]]; then
    printf 'apply-promotions: invalid approval value\n' >&2
    exit 2
  fi
done <"$approval_file"
LC_ALL=C sort -u "$approval_file" >"$tmp_root/approvals.sorted"
mv "$tmp_root/approvals.sorted" "$approval_file"

if [[ -n "$rollback_id" ]]; then
  if [[ ! "$rollback_id" =~ ^theme-[0-9]{8}T[0-9]{6}Z-[0-9]+-[0-9]{3}$ ]] \
    || [[ ! "$rollback_reason" =~ ^[A-Za-z0-9._+:#/-]+$ ]]; then
    usage
    exit 2
  fi
fi

snapshot_candidates() {
  local path base count=0
  : >"$tmp_root/input-paths"
  : >"$tmp_root/trusted-inputs"
  : >"$tmp_root/untrusted-inputs"
  for path in "$promotions_dir"/candidates-*.md; do
    [[ -e "$path" || -L "$path" ]] || continue
    base=${path##*/}
    if [[ "$base" =~ ^candidates-[0-9]{8}T[0-9]{6}Z-[0-9]+\.md$ ]]; then
      printf '%s\n' "$base" >>"$tmp_root/input-paths"
      count=$((count + 1))
      if [[ -f "$path" && ! -L "$path" ]]; then
        cp "$path" "$tmp_root/$base" || return 1
        printf '%s\n' "$base" >>"$tmp_root/trusted-inputs"
      else
        printf '%s\n' "$base" >>"$tmp_root/untrusted-inputs"
      fi
    fi
  done
  LC_ALL=C sort -o "$tmp_root/input-paths" "$tmp_root/input-paths"
  LC_ALL=C sort -o "$tmp_root/trusted-inputs" "$tmp_root/trusted-inputs"
  LC_ALL=C sort -o "$tmp_root/untrusted-inputs" "$tmp_root/untrusted-inputs"
  printf '%s\n' "$count" >"$tmp_root/input-count"
  append_direct "decision=run-start applyid=$apply_id inputs=$count"
  if [[ -e "$apply_index" ]]; then
    [[ -f "$apply_index" && ! -L "$apply_index" ]] || return 1
    cp "$apply_index" "$tmp_root/index.snapshot" || return 1
  else
    : >"$tmp_root/index.snapshot"
  fi
  if [[ -e "$apply_log" ]]; then
    [[ -f "$apply_log" && ! -L "$apply_log" ]] || return 1
    cp "$apply_log" "$tmp_root/log.snapshot" || return 1
  else
    : >"$tmp_root/log.snapshot"
  fi
}

if ! take_promotions_lock; then lock_busy_summary; exit 1; fi
if ! snapshot_candidates; then
  release_promotions_lock
  append_direct "decision=run-summary applyid=$apply_id promoted=0 skipped=1 pending=0 reason=input-untrusted"
  exit 1
fi
release_promotions_lock

# Surface incomplete prior runs without treating the operator log as authority.
python3 -B - "$tmp_root/log.snapshot" "$apply_id" <<'PY'
import re, sys
starts, summaries = [], set()
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    m = re.search(r"(?:^| )decision=run-start applyid=([0-9]{8}T[0-9]{6}Z-[0-9]+)(?: |$)", line)
    if m: starts.append(m.group(1))
    m = re.search(r"(?:^| )decision=run-summary applyid=([0-9]{8}T[0-9]{6}Z-[0-9]+)(?: |$)", line)
    if m: summaries.add(m.group(1))
for item in starts:
    if item != sys.argv[2] and item not in summaries:
        print("dangling-run-start=" + item)
PY

parse_dir=$tmp_root/parsed
mkdir -p "$parse_dir"
if ! python3 -B - "$tmp_root" "$parse_dir" <<'PY'
from pathlib import Path
import json, re, sys, unicodedata

root, out = Path(sys.argv[1]), Path(sys.argv[2])
theme_re = re.compile(r"theme-([0-9]{8}T[0-9]{6}Z-[0-9]+)-([0-9]{3})\Z")
week_re = re.compile(r"[0-9]{4}-W[0-9]{2}(?:,[0-9]{4}-W[0-9]{2})*\Z")
reviewer_re = re.compile(r"[A-Za-z0-9._+-]+\Z")
banned = ("source:", "reviewer:", "weeks:", "k=", "approver:", "invalidated-by:",
          "confirmations:", "dedup_key:", "mech_check:", "<!--", "-->")

def write_record(seq, values, status, filename):
    d = out / f"block.{seq:06d}"
    d.mkdir()
    values = dict(values)
    values["status"] = status
    values["filename"] = filename
    for key, value in values.items():
        if isinstance(value, list):
            (d / key).write_text("".join(x + "\n" for x in value), encoding="utf-8")
        else:
            (d / key).write_text(str(value) + "\n", encoding="utf-8")

seq = 0
for filename in (root / "trusted-inputs").read_text().splitlines():
    filename_match = re.fullmatch(r"candidates-([0-9]{8}T[0-9]{6}Z-[0-9]+)\.md", filename)
    if not filename_match:
        seq += 1; write_record(seq, {"id":"-", "class":"-"}, "parse", filename); continue
    file_runid = filename_match.group(1)
    try:
        text = (root / filename).read_text(encoding="utf-8", errors="strict").replace("\r\n", "\n")
    except (OSError, UnicodeError):
        seq += 1; write_record(seq, {"id":"-", "class":"-"}, "parse", filename); continue
    lines = text.splitlines()
    starts = [i for i, line in enumerate(lines) if line.startswith("## ")]
    header_ok = len(lines) >= 4 and lines[0] == "# Raw review candidates" and lines[1] == "" \
        and lines[2] == "runid: " + file_runid and lines[3].startswith("reviewer: ") \
        and ((not starts and len(lines) == 4) or (starts and starts[0] == 5 and lines[4] == ""))
    if not starts:
        if not header_ok:
            seq += 1; write_record(seq, {"id":"-", "class":"-"}, "parse", filename)
        continue
    starts.append(len(lines))
    for n in range(len(starts)-1):
        block = lines[starts[n]:starts[n+1]]
        while block and block[-1] == "": block.pop()
        seq += 1
        raw_id = block[0][3:] if block and block[0].startswith("## ") else "-"
        vals = {"id": raw_id, "class":"-", "theme":"", "reviewer":"", "weeks":"",
                "k":"0", "week-k":"0", "supersedes":"", "members":[], "evidence":[], "slug":""}
        ok = header_ok and len(block) >= 13
        expected = ("theme: ", "class: ", "reviewer: ", "run-weeks: ", "run-k: ", "promote: ")
        if ok and all(block[i+1].startswith(prefix) for i, prefix in enumerate(expected)):
            vals["theme"] = block[1][7:]
            vals["class"] = block[2][7:]
            vals["reviewer"] = block[3][10:]
            run_weeks = block[4][11:]
            run_k = block[5][7:]
            promote = block[6][9:]
            at = 7
            if at < len(block) and block[at].startswith("supersedes: "):
                vals["supersedes"] = block[at][12:]; at += 1
            ok = ok and at + 5 < len(block) and block[at].startswith("weeks: ")
            if ok: vals["weeks"] = block[at][7:]; at += 1
            ok = ok and block[at].startswith("union-k: ")
            union_k = block[at][9:] if ok else ""; at += 1
            ok = ok and at < len(block) and block[at] == "members:"; at += 1
            members = []
            while ok and at < len(block) and block[at].startswith("- "):
                members.append(block[at][2:]); at += 1
            hashes = []
            while ok and at < len(block) and block[at].startswith("member-hash: "):
                hashes.append(block[at][13:]); at += 1
            ok = ok and at < len(block) and block[at] == "evidence: |"; at += 1
            evidence = block[at:]
            ok = ok and all(line.startswith("  ") and line[2:] for line in evidence)
            evidence = [line[2:] for line in evidence]
            vals["members"], vals["evidence"] = members, evidence
            ok = ok and vals["class"] in {"capability-fact","rule","skill"}
            ok = ok and promote in {"yes","not-yet"} and union_k.isdigit()
            ok = ok and bool(week_re.fullmatch(run_weeks)) and bool(members) and bool(hashes) and bool(evidence)
        if not ok:
            write_record(seq, vals, "parse", filename); continue
        hygienic = True
        m = theme_re.fullmatch(raw_id)
        if not m or m.group(1) != file_runid: hygienic = False
        theme = vals["theme"]
        if not theme or len(theme.encode("utf-8")) > 240 or theme[0] in "#-" or theme[0].isspace(): hygienic = False
        if any(
            unicodedata.category(c) == "Cc"
            or unicodedata.bidirectional(c) in {"LRE", "RLE", "LRO", "RLO", "PDF", "LRI", "RLI", "FSI", "PDI"}
            or ord(c) == 127
            for c in theme
        ) or any(token in theme for token in banned):
            hygienic = False
        if not reviewer_re.fullmatch(vals["reviewer"]): hygienic = False
        if not week_re.fullmatch(vals["weeks"]): hygienic = False
        if vals["supersedes"] and not theme_re.fullmatch(vals["supersedes"]): hygienic = False
        if any(not x for x in vals["members"]) or any(not x for x in vals["evidence"]): hygienic = False
        normalized_run_k = "0"
        if re.fullmatch(r"[0-9]+", run_k):
            normalized_run_k = run_k.lstrip("0") or "0"
            member_limit = str(len(vals["members"]))
            if len(normalized_run_k) > len(member_limit) \
               or (len(normalized_run_k) == len(member_limit) and normalized_run_k > member_limit):
                hygienic = False
        else:
            hygienic = False
        distinct_weeks = sorted(set(vals["weeks"].split(','))) if vals["weeks"] else []
        vals["weeks"] = ",".join(distinct_weeks)
        vals["k"] = normalized_run_k
        vals["week-k"] = str(len(distinct_weeks))
        if m:
            vals["slug"] = m.group(1) + "-" + m.group(2)
        write_record(seq, vals, "ok" if hygienic else "hygiene", filename)
PY
then
  printf 'apply-promotions: candidate parsing failed\n' >&2
  append_direct "decision=run-summary applyid=$apply_id promoted=0 skipped=1 pending=0 skipped-parse=1 reason=parse"
  exit 1
fi

index_work=$tmp_root/index.work
cp "$tmp_root/index.snapshot" "$index_work" || exit 1
if ! INDEX_DECISION_TABLE="$index_decision_table" python3 -B - "$index_work" <<'PY'
import os, re, sys
theme = re.compile(r"theme-[0-9]{8}T[0-9]{6}Z-[0-9]+-[0-9]{3}\Z")
applyid = re.compile(r"[0-9]{8}T[0-9]{6}Z-[0-9]+\Z")
ts = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\Z")
sha = re.compile(r"(?:-|[0-9a-f]{64})\Z")
classes = {"capability-fact","rule","skill"}
decisions = {line.split()[0] for line in os.environ["INDEX_DECISION_TABLE"].splitlines() if line.strip()}
seen=set()
for raw in open(sys.argv[1], encoding="utf-8", errors="strict"):
    row=raw.rstrip("\n").split("\t")
    if len(row)!=6 or not theme.fullmatch(row[0]) or row[0] in seen or row[1] not in classes \
       or row[2] not in decisions or not applyid.fullmatch(row[3]) or not sha.fullmatch(row[4]) \
       or not ts.fullmatch(row[5]):
        raise SystemExit(1)
    seen.add(row[0])
PY
then
  printf 'apply-promotions: apply-index.tsv is torn or grammar-invalid\n' >&2
  append_direct "decision=run-summary applyid=$apply_id promoted=0 skipped=1 pending=0 reason=parse"
  exit 1
fi

index_row() { awk -F '\t' -v id="$1" '$1 == id {print; exit}' "$index_work"; }
index_decision() { index_row "$1" | awk -F '\t' '{print $3}'; }
index_class() { index_row "$1" | awk -F '\t' '{print $2}'; }
index_sha() { index_row "$1" | awk -F '\t' '{print $5}'; }

index_upsert() {
  local id=$1 class=$2 decision=$3 sha=$4 next=$tmp_root/index.next
  if ! index_decision_state "$decision" >/dev/null 2>&1; then
    printf 'apply-promotions: refusing invalid index decision %s\n' "$decision" >&2
    return 1
  fi
  case "$(index_decision "$id")" in
    promoted)
      if pending_decision "$decision"; then
        printf 'apply-promotions: refusing promoted-to-pending downgrade for %s\n' "$id" >&2
        return 1
      fi
      ;;
    rolled-back)
      if [[ "$decision" != rolled-back ]]; then
        printf 'apply-promotions: refusing rolled-back rewrite for %s\n' "$id" >&2
        return 1
      fi
      ;;
  esac
  awk -F '\t' -v OFS='\t' -v id="$id" '$1 != id {print}' "$index_work" >"$next" || return 1
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$class" "$decision" "$apply_id" "$sha" "$run_ts" >>"$next"
  LC_ALL=C sort -t '	' -k1,1 "$next" >"$index_work" || return 1
}

receipts=$tmp_root/receipts
results=$tmp_root/results
: >"$receipts"; : >"$results"; : >"$tmp_root/promoted-ids"; : >"$tmp_root/seen-ids"
promoted_count=0
rolled_back_count=0
skipped_count=0
pending_count=0
decision_k=-
decision_unit=-

record_result() {
  local id=$1 class=$2 decision=$3 reason=$4 note=$5 approver=$6 target=$7 sha=$8 persist=${9:-1} force=${10:-0}
  local old new_index_decision transition=0 receipt_theme=$id receipt_class=$class
  old=
  if [[ "$id" =~ ^theme-[0-9]{8}T[0-9]{6}Z-[0-9]+-[0-9]{3}$ ]]; then old=$(index_decision "$id"); fi
  new_index_decision=$decision
  [[ "$decision" == skipped ]] && new_index_decision=$reason
  if [[ "$persist" -eq 1 && "$id" =~ ^theme-[0-9]{8}T[0-9]{6}Z-[0-9]+-[0-9]{3}$ \
    && "$class" =~ ^(capability-fact|rule|skill)$ ]]; then
    index_decision_state "$new_index_decision" >/dev/null 2>&1 || {
      printf 'apply-promotions: refusing invalid persisted decision %s\n' "$new_index_decision" >&2
      return 1
    }
    [[ "$old" != "$new_index_decision" ]] && transition=1
    index_upsert "$id" "$class" "$new_index_decision" "$sha" || return 1
  elif [[ "$persist" -eq 1 ]]; then
    transition=1
  fi
  [[ "$id" =~ ^theme-[0-9]{8}T[0-9]{6}Z-[0-9]+-[0-9]{3}$ ]] || receipt_theme=-
  [[ "$class" =~ ^(capability-fact|rule|skill)$ ]] || receipt_class=-
  printf 'theme=%s decision=%s reason=%s\n' "$receipt_theme" "$decision" "$reason"
  printf '%s\t%s\t%s\t%s\n' "$receipt_theme" "$receipt_class" "$decision" "$reason" >>"$results"
  if [[ "$decision" == promoted ]]; then promoted_count=$((promoted_count + 1)); else skipped_count=$((skipped_count + 1)); fi
  if pending_decision "$new_index_decision"; then pending_count=$((pending_count + 1)); fi
  if [[ "$transition" -eq 1 || "$force" -eq 1 ]]; then
    printf 'ts=%s applyid=%s theme=%s class=%s decision=%s reason=%s note=%s k=%s unit=%s approver=%s target=%s line_sha=%s\n' \
      "$run_ts" "$apply_id" "$receipt_theme" "$receipt_class" "$decision" "$reason" "$note" \
      "$decision_k" "$decision_unit" "$approver" "$target" "$sha" >>"$receipts"
  fi
}

append_receipts_and_summary_direct() {
  local line reason=$1
  if [[ -f "$receipts" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -n "$line" ]] || continue
      append_direct "$line"
    done <"$receipts"
  fi
  append_direct "$(summary_with_reason "$reason")"
}

state_headings_and_counts() {
  awk -v output="$1" '
    function flush() {
      if (section == "verified") verified_count = count
      else if (section == "rules") rules_count = count
      count = 0; section = ""; preamble = 0
    }
    /^## / {
      flush()
      if (index($0, "## Verified facts") == 1) { section="verified"; verified_heads++; preamble=1 }
      else if (index($0, "## General rules") == 1) { section="rules"; rules_heads++; preamble=1 }
      next
    }
    section != "" {
      if (preamble && ($0 ~ /^[[:space:]]*$/ || $0 ~ /^[[:space:]]*<!--.*-->[[:space:]]*$/)) next
      preamble=0; count++
    }
    END {
      flush()
      if (verified_heads != 1 || rules_heads != 1) exit 1
      print verified_count + 0, rules_count + 0 > output
    }
  ' "$state_tmp"
}

state_append_line() {
  local heading=$1 line=$2 out=$tmp_root/state.next
  awk -v heading="$heading" -v line="$line" '
    BEGIN {inside=0; inserted=0}
    /^## / {
      if (inside && !inserted) {print line; inserted=1}
      inside=(index($0, heading)==1)
      print; next
    }
    {print}
    END {if (inside && !inserted) print line}
  ' "$state_tmp" >"$out" || return 1
  mv "$out" "$state_tmp"
}

canonical_stamp_count() {
  local id=$1 heading=${2-}
  awk -v id="$id" -v wanted="$heading" '
    function canonical(line, pattern) {
      pattern="^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] .* \\(source: " id "; reviewer: [A-Za-z0-9._+-]+; weeks: [0-9][0-9][0-9][0-9]-W[0-9][0-9](,[0-9][0-9][0-9][0-9]-W[0-9][0-9])*; k=[0-9]+(; unit=(sessions|weeks))?; approver: (alpha|auto)\\)( invalidated-by: [A-Za-z0-9._+:#/-]+)*$"
      return line ~ pattern
    }
    /^## / {inside=(wanted=="" || index($0,wanted)==1); next}
    inside && canonical($0) {count++}
    END {print count + 0}
  ' "$state_tmp"
}

literal_target_count() { awk -v id="$1" 'index($0,id)>0 {n++} END{print n+0}' "$state_tmp"; }

state_annotate_line() {
  local old_id=$1 new_id=$2 out=$tmp_root/state.next
  awk -v old_id="$old_id" -v new_id="$new_id" '
    function canonical(line, pattern) {
      pattern="^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] .* \\(source: " old_id "; reviewer: [A-Za-z0-9._+-]+; weeks: [0-9][0-9][0-9][0-9]-W[0-9][0-9](,[0-9][0-9][0-9][0-9]-W[0-9][0-9])*; k=[0-9]+(; unit=(sessions|weeks))?; approver: (alpha|auto)\\)( invalidated-by: [A-Za-z0-9._+:#/-]+)*$"
      return line ~ pattern
    }
    canonical($0) {
      matched++
      if (index($0, "invalidated-by: " new_id) == 0) $0=$0 " invalidated-by: " new_id
    }
    {print}
    END {if (matched != 1) exit 2}
  ' "$state_tmp" >"$out" || { rm -f "$out"; return 1; }
  mv "$out" "$state_tmp"
}

state_normalized_content_exists() {
  python3 -B - "$state_tmp" "$1" "$2" <<'PY'
import re, sys
path, heading, wanted = sys.argv[1:]
trailer = re.compile(r" \(source: theme-[0-9]{8}T[0-9]{6}Z-[0-9]+-[0-9]{3}; reviewer: [A-Za-z0-9._+-]+; weeks: [0-9]{4}-W[0-9]{2}(?:,[0-9]{4}-W[0-9]{2})*; k=[0-9]+(?:; unit=(?:sessions|weeks))?; approver: (?:alpha|auto)\)(?: invalidated-by: [A-Za-z0-9._+:#/-]+)?$")
def norm(s):
    s=re.sub(r"^- [0-9]{4}-[0-9]{2}-[0-9]{2} ","",s)
    s=trailer.sub("",s)
    return " ".join(s.split())
inside=False
for raw in open(path, encoding="utf-8", errors="strict"):
    line=raw.rstrip("\n")
    if line.startswith("## "):
        inside=line.startswith(heading)
    elif inside and norm(line)==norm(wanted):
        raise SystemExit(0)
raise SystemExit(1)
PY
}

sha_line() {
  if command -v sha256sum >/dev/null 2>&1; then printf '%s' "$1" | sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
  else return 1
  fi
}

write_stub_template() {
  local block=$1 destination=$2
  python3 -B - "$block" "$destination" <<'PY'
from pathlib import Path
import json, sys
b, out = Path(sys.argv[1]), Path(sys.argv[2])
one=lambda name: (b/name).read_text(encoding="utf-8").rstrip("\n")
members=(b/"members").read_text(encoding="utf-8").splitlines()
text = "\n".join([
    "---",
    "name: " + json.dumps(one("slug"), ensure_ascii=False),
    "description: " + json.dumps(one("theme"), ensure_ascii=False),
    "source: " + one("id"),
    "members: " + json.dumps(members, ensure_ascii=False),
    "status: draft",
    "trigger: manual",
    "---",
    "",
    "# Draft skill",
    "",
    one("theme"),
    "",
])
with out.open("w", encoding="utf-8", newline="\n") as fh:
    fh.write(text)
PY
}

stub_is_canonical() {
  python3 -B - "$1" "$2" "$3" <<'PY'
from pathlib import Path
import json, sys
path, theme_id, slug = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
try:
    raw = path.read_text(encoding="utf-8", errors="strict")
    lines = raw.splitlines()
    if len(lines) != 12:
        raise ValueError
    if lines[0] != "---" or lines[3] != "source: " + theme_id:
        raise ValueError
    if lines[5:10] != ["status: draft", "trigger: manual", "---", "", "# Draft skill"]:
        raise ValueError
    if lines[10] != "":
        raise ValueError
    if not lines[1].startswith("name: ") or not lines[2].startswith("description: ") or not lines[4].startswith("members: "):
        raise ValueError
    name = json.loads(lines[1][6:])
    description = json.loads(lines[2][13:])
    members = json.loads(lines[4][9:])
    if name != slug or not isinstance(description, str) or not description or lines[11] != description:
        raise ValueError
    if not isinstance(members, list) or not members or any(not isinstance(x, str) or not x for x in members):
        raise ValueError
    expected = "\n".join(["---", "name: " + json.dumps(name, ensure_ascii=False),
        "description: " + json.dumps(description, ensure_ascii=False), "source: " + theme_id,
        "members: " + json.dumps(members, ensure_ascii=False), "status: draft", "trigger: manual",
        "---", "", "# Draft skill", "", description, ""])
    if raw != expected:
        raise ValueError
except (OSError, UnicodeError, ValueError, TypeError):
    raise SystemExit(1)
PY
}

build_graph_files() {
  python3 -B - "$parse_dir" "$tmp_root/ambiguous" "$tmp_root/order" "$tmp_root/superseded-by" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1]); ambiguous=Path(sys.argv[2]); order=Path(sys.argv[3]); by=Path(sys.argv[4])
blocks=[]; id_to_block={}; edge={}; victims={}
for d in sorted(root.glob("block.*")):
    if (d/"status").read_text().strip()!="ok": continue
    i=(d/"id").read_text().strip(); s=(d/"supersedes").read_text().strip()
    blocks.append((d.name,i,s)); id_to_block[i]=d.name
    if s: edge[i]=s; victims.setdefault(s,[]).append(i)
amb=set()
for victim, superseders in victims.items():
    if len(superseders)>1: amb.add(victim); amb.update(superseders)
for node in edge:
    if node in victims: amb.add(node); amb.add(edge[node]); amb.update(victims[node])
for start in edge:
    seen=[]; cur=start
    while cur in edge:
        if cur in seen:
            cycle=seen[seen.index(cur):]; amb.update(cycle); amb.update(edge[x] for x in cycle); break
        seen.append(cur); cur=edge[cur]
with ambiguous.open("w") as f:
    for i in sorted(amb): f.write(i+"\n")
with by.open("w") as f:
    for victim, superseders in sorted(victims.items()):
        if len(superseders)==1: f.write(victim+"\t"+superseders[0]+"\n")
remaining={i:(name,s) for name,i,s in blocks}; emitted=[]
while remaining:
    ready=[i for i,(name,s) in remaining.items() if i in amb or not any(x in remaining for x in victims.get(i,[]))]
    if not ready: ready=list(remaining)
    for i in sorted(ready, key=lambda x: remaining[x][0]):
        emitted.append(remaining.pop(i)[0])
with order.open("w") as f:
    for name in emitted: f.write(name+"\n")
PY
}

state_tmp=$tmp_root/STATE.work
if ! take_state_lock "$workspace" apply-promotions "$state_lock_attempts" "$state_lock_sleep"; then
  lock_busy_summary 1
  exit 1
fi
if [[ ! -f "$state_file" || -L "$state_file" ]] || ! cp "$state_file" "$state_tmp"; then
  release_state_lock
  printf 'apply-promotions: STATE.md is not a trusted regular file\n' >&2
  exit 1
fi
chmod 0600 "$state_tmp"

if ! parse_positive_decimal "${STATE_FOLD_VERIFIED_CAP_DEFAULT:-}" >/dev/null \
  || ! parse_positive_decimal "${STATE_FOLD_RULES_CAP_DEFAULT:-}" >/dev/null \
  || ! state_headings_and_counts "$tmp_root/counts"; then
  release_state_lock
  append_summary_line "$(summary_with_reason caps-read-failed)" 1
  exit 1
fi
read -r verified_count rules_count <"$tmp_root/counts"
state_changed=0

abort_under_state_lock() {
  local reason=$1
  skipped_count=$((skipped_count + 1))
  printf '%s\t%s\t%s\t%s\n' - - skipped "$reason" >>"$results"
  release_state_lock
  append_summary_line "$(summary_with_reason "$reason")" 1
  exit 1
}

rollback_operation() {
  local old_decision class stamp_count line current_sha stub_dir stub_file out slug failure_heads
  old_decision=$(index_decision "$rollback_id")
  class=$(index_class "$rollback_id")
  if [[ "$old_decision" == rolled-back ]]; then
    record_result "$rollback_id" "$class" skipped already-rolled-back - - - - 0 1
    return 0
  fi
  if [[ "$old_decision" != promoted || ! "$class" =~ ^(capability-fact|rule|skill)$ ]]; then
    printf 'apply-promotions: rollback target is not an applied theme\n' >&2
    return 1
  fi
  if [[ "$class" == skill ]]; then
    slug=${rollback_id#theme-}
    stub_dir=$staging_root/$slug
    stub_file=$stub_dir/SKILL.md
    if [[ ! -d "$stub_dir" || -L "$stub_dir" || ! -f "$stub_file" || -L "$stub_file" ]] \
      || ! grep -Fxq "source: $rollback_id" "$stub_file" || ! stub_is_canonical "$stub_file" "$rollback_id" "$slug" \
      || [[ "$(find "$stub_dir" -mindepth 1 -maxdepth 1 | wc -l | tr -d '[:space:]')" -ne 1 ]]; then
      record_result "$rollback_id" "$class" skipped stub-dirty - - "$stub_dir" - 0 1
      return 0
    fi
    rm -f "$stub_file" && rmdir "$stub_dir" || return 1
    index_upsert "$rollback_id" "$class" rolled-back - || return 1
    printf 'ts=%s applyid=%s theme=%s class=%s decision=rolled-back reason=- note=- k=- unit=- approver=alpha target=%s line_sha=-\n' \
      "$run_ts" "$apply_id" "$rollback_id" "$class" "$stub_dir" >>"$receipts"
    rolled_back_count=$((rolled_back_count + 1))
    return 0
  fi
  stamp_count=$(canonical_stamp_count "$rollback_id" "")
  if [[ "$stamp_count" -ne 1 ]]; then
    printf 'apply-promotions: rollback stamp count is %s, expected 1\n' "$stamp_count" >&2
    return 1
  fi
  failure_heads=$(grep -c '^## Open failures' "$state_tmp")
  if [[ "$failure_heads" -ne 1 ]]; then
    printf 'apply-promotions: rollback Open failures heading count is %s, expected 1\n' "$failure_heads" >&2
    return 1
  fi
  out=$tmp_root/state.rollback
  awk -v id="$rollback_id" -v ref="$rollback_reason" -v date="$run_date" '
    function canonical(line, pattern) {
      pattern="^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] .* \\(source: " id "; reviewer: [A-Za-z0-9._+-]+; weeks: [0-9][0-9][0-9][0-9]-W[0-9][0-9](,[0-9][0-9][0-9][0-9]-W[0-9][0-9])*; k=[0-9]+(; unit=(sessions|weeks))?; approver: (alpha|auto)\\)( invalidated-by: [A-Za-z0-9._+:#/-]+)*$"
      return line ~ pattern
    }
    function emit_failure() {
      if (!failure_done) {
        print "- " date " Promotion " id " rolled back; review missed " ref ". (source: apply-rollback; invalidated-by: " ref ")"
        failure_done=1
      }
    }
    /^## / {
      if (in_failures) emit_failure()
      in_failures=(index($0,"## Open failures")==1)
      if (in_failures) failure_heads++
      print; next
    }
    {
      if (canonical($0)) {
        matched++
        if (index($0,"invalidated-by: " ref)==0) $0=$0 " invalidated-by: " ref
      }
      print
    }
    END {if (in_failures) emit_failure(); if (matched!=1 || failure_heads!=1) exit 2}
  ' "$state_tmp" >"$out" || { rm -f "$out"; return 1; }
  mv "$out" "$state_tmp" || { rm -f "$out"; return 1; }
  state_changed=1
  line=$(awk -v id="$rollback_id" '
    {pattern="^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] .* \\(source: " id "; reviewer: [A-Za-z0-9._+-]+; weeks: [0-9][0-9][0-9][0-9]-W[0-9][0-9](,[0-9][0-9][0-9][0-9]-W[0-9][0-9])*; k=[0-9]+(; unit=(sessions|weeks))?; approver: (alpha|auto)\\)( invalidated-by: [A-Za-z0-9._+:#/-]+)*$"; if ($0 ~ pattern) {print; exit}}
  ' "$state_tmp")
  current_sha=$(sha_line "$line") || return 1
  index_upsert "$rollback_id" "$class" rolled-back "$current_sha" || return 1
  printf 'ts=%s applyid=%s theme=%s class=%s decision=rolled-back reason=- note=- k=- unit=- approver=alpha target=STATE.md line_sha=%s\n' \
    "$run_ts" "$apply_id" "$rollback_id" "$class" "$current_sha" >>"$receipts"
  rolled_back_count=$((rolled_back_count + 1))
}

if [[ -n "$rollback_id" ]]; then
  if ! rollback_operation; then abort_under_state_lock rollback-refused; fi
else
  build_graph_files || { release_state_lock; exit 1; }
  decision_unit=$recurrence_unit
  section_verified_promotions=0
  section_rules_promotions=0
  auto_promotions=0

  for block in "$parse_dir"/block.*; do
    [[ -d "$block" ]] || continue
    status=$(sed -n '1p' "$block/status")
    [[ "$status" == ok ]] && continue
    id=$(sed -n '1p' "$block/id")
    class=$(sed -n '1p' "$block/class")
    if [[ "$status" == hygiene ]]; then malformed_reason=hygiene; else malformed_reason=parse; fi
    if [[ "$id" =~ ^theme-[0-9]{8}T[0-9]{6}Z-[0-9]+-[0-9]{3}$ ]]; then
      printf '%s\n' "$id" >>"$tmp_root/seen-ids"
      old_decision=$(index_decision "$id")
      if [[ -n "$old_decision" ]] && terminal_decision "$old_decision"; then
        record_result "$id" "$class" skipped "$malformed_reason" - - - - 0 || { release_state_lock; exit 1; }
        continue
      fi
    fi
    record_result "$id" "$class" skipped "$malformed_reason" - - - - 1 || { release_state_lock; exit 1; }
  done
  while IFS= read -r untrusted || [[ -n "$untrusted" ]]; do
    [[ -n "$untrusted" ]] || continue
    record_result - - skipped input-untrusted - - "$untrusted" - 0 1 || { release_state_lock; exit 1; }
  done <"$tmp_root/untrusted-inputs"

  while IFS= read -r block_name || [[ -n "$block_name" ]]; do
    [[ -n "$block_name" ]] || continue
    block=$parse_dir/$block_name
    id=$(sed -n '1p' "$block/id")
    class=$(sed -n '1p' "$block/class")
    theme=$(sed -n '1p' "$block/theme")
    reviewer=$(sed -n '1p' "$block/reviewer")
    weeks=$(sed -n '1p' "$block/weeks")
    run_k=$(sed -n '1p' "$block/k")
    week_k=$(sed -n '1p' "$block/week-k")
    if [[ "$recurrence_unit" == sessions ]]; then k=$run_k; else k=$week_k; fi
    decision_k=$k
    supersedes=$(sed -n '1p' "$block/supersedes")
    slug=$(sed -n '1p' "$block/slug")
    printf '%s\n' "$id" >>"$tmp_root/seen-ids"
    old_decision=$(index_decision "$id")
    approved=0
    grep -Fxq "$id" "$approval_file" && approved=1

    if [[ "$approved" -eq 1 && -n "$old_decision" ]] && terminal_decision "$old_decision"; then
      record_result "$id" "$class" skipped unknown-approval - - - - 0 1 || { release_state_lock; exit 1; }
      continue
    fi
    if [[ -n "$old_decision" ]] && terminal_decision "$old_decision"; then
      record_result "$id" "$class" skipped already-applied - - - "$(index_sha "$id")" 0 || { release_state_lock; exit 1; }
      continue
    fi
    if [[ "$class" == skill ]]; then
      if grep -Fxq "$id" "$tmp_root/ambiguous"; then
        record_result "$id" "$class" skipped supersedes-ambiguous - - "skills/_staging/$slug/SKILL.md" - 1 || { release_state_lock; exit 1; }
        continue
      fi
      superseder=$(awk -F '\t' -v id="$id" '$1==id {print $2; exit}' "$tmp_root/superseded-by")
      if [[ -n "$superseder" ]] && grep -Fxq "$superseder" "$tmp_root/promoted-ids"; then
        record_result "$id" "$class" skipped superseded - - "skills/_staging/$slug/SKILL.md" - 1 || { release_state_lock; exit 1; }
        continue
      fi
    fi

    if [[ "$class" == skill ]]; then
      if [[ "$k" -lt "$promote_min_k" ]]; then
        record_result "$id" "$class" skipped k-below-2 - - - - 1 || { release_state_lock; exit 1; }
        continue
      fi
      if [[ "$week_k" -lt "$promote_min_weeks" ]]; then
        record_result "$id" "$class" skipped weeks-below-min - - - - 1 || { release_state_lock; exit 1; }
        continue
      fi
      stub_dir=$staging_root/$slug
      stub_file=$stub_dir/SKILL.md
      expected=$tmp_root/$block_name.stub
      if [[ ! -e "$staging_root" ]]; then
        mkdir "$staging_root" 2>/dev/null || { release_state_lock; exit 1; }
      fi
      if [[ ! -d "$staging_root" || -L "$staging_root" ]]; then
        record_result "$id" "$class" skipped hygiene - - - - 1 || { release_state_lock; exit 1; }
        continue
      fi
      staging_real=$(cd -P "$staging_root" 2>/dev/null && pwd)
      [[ -n "$staging_real" ]] || {
        record_result "$id" "$class" skipped hygiene - - - - 1 || { release_state_lock; exit 1; }
        continue
      }
      write_stub_template "$block" "$expected" || { release_state_lock; exit 1; }
      stub_reason=-
      if [[ ! -e "$stub_dir" && ! -L "$stub_dir" ]]; then
        if ! mkdir "$stub_dir" 2>/dev/null; then
          record_result "$id" "$class" skipped stub-exists - - "$stub_dir" - 1 || { release_state_lock; exit 1; }
          continue
        fi
        if [[ "${APPLY_TEST_CRASH_AFTER_STUB_MKDIR:-0}" == 1 ]]; then kill -KILL $$; fi
      elif [[ -d "$stub_dir" && ! -L "$stub_dir" && ! -e "$stub_file" \
        && "$(find "$stub_dir" -mindepth 1 -maxdepth 1 | wc -l | tr -d '[:space:]')" -eq 0 ]]; then
        stub_reason=stub-replay
      elif [[ -d "$stub_dir" && ! -L "$stub_dir" && -f "$stub_file" && ! -L "$stub_file" ]] \
        && stub_is_canonical "$stub_file" "$id" "$slug"; then
        stub_reason=stub-replay
      else
        record_result "$id" "$class" skipped stub-exists - - "$stub_dir" - 1 || { release_state_lock; exit 1; }
        continue
      fi
      stub_real=$(cd -P "$stub_dir" 2>/dev/null && pwd)
      [[ -n "$stub_real" ]] || {
        record_result "$id" "$class" skipped hygiene - - "$stub_dir" - 1 || { release_state_lock; exit 1; }
        continue
      }
      case "$stub_real/" in
        "$staging_real"/*) ;;
        *)
          record_result "$id" "$class" skipped hygiene - - "$stub_dir" - 1 || { release_state_lock; exit 1; }
          continue
          ;;
      esac
      atomic_write_file "$expected" "$stub_file" || { release_state_lock; exit 1; }
      record_result "$id" "$class" promoted "$stub_reason" - alpha "skills/_staging/$slug/SKILL.md" - 1 || { release_state_lock; exit 1; }
      printf '%s\n' "$id" >>"$tmp_root/promoted-ids"
      continue
    fi

    if [[ "$class" == capability-fact ]]; then heading='## Verified facts'; target='Verified-facts'; cap=$STATE_FOLD_VERIFIED_CAP_DEFAULT; current_count=$verified_count
    else heading='## General rules'; target='General-rules'; cap=$STATE_FOLD_RULES_CAP_DEFAULT; current_count=$rules_count; fi
    stamp_count=$(canonical_stamp_count "$id" "$heading")
    if [[ "$stamp_count" -gt 1 ]]; then release_state_lock; printf 'apply-promotions: duplicate apply stamp for %s\n' "$id" >&2; exit 1; fi
    if [[ "$stamp_count" -eq 1 ]]; then
      existing_line=$(awk -v id="$id" '
        {pattern="^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] .* \\(source: " id "; reviewer: [A-Za-z0-9._+-]+; weeks: [0-9][0-9][0-9][0-9]-W[0-9][0-9](,[0-9][0-9][0-9][0-9]-W[0-9][0-9])*; k=[0-9]+(; unit=(sessions|weeks))?; approver: (alpha|auto)\\)( invalidated-by: [A-Za-z0-9._+:#/-]+)*$"; if ($0 ~ pattern) {print; exit}}
      ' "$state_tmp")
      existing_sha=$(sha_line "$existing_line") || { release_state_lock; exit 1; }
      index_upsert "$id" "$class" promoted "$existing_sha" || { release_state_lock; exit 1; }
      record_result "$id" "$class" skipped already-applied - - "$target" "$existing_sha" 0 1 || { release_state_lock; exit 1; }
      continue
    fi
    if state_normalized_content_exists "$heading" "$theme"; then
      record_result "$id" "$class" skipped duplicate-content - - "$target" - 1 || { release_state_lock; exit 1; }
      continue
    fi
    if grep -Fxq "$id" "$tmp_root/ambiguous"; then
      record_result "$id" "$class" skipped supersedes-ambiguous - - "$target" - 1 || { release_state_lock; exit 1; }
      continue
    fi
    superseder=$(awk -F '\t' -v id="$id" '$1==id {print $2; exit}' "$tmp_root/superseded-by")
    if [[ -n "$superseder" ]] && grep -Fxq "$superseder" "$tmp_root/promoted-ids"; then
      record_result "$id" "$class" skipped superseded - - "$target" - 1 || { release_state_lock; exit 1; }
      continue
    fi

    note=-
    annotate_target=
    pending_target=
    if [[ -n "$supersedes" ]]; then
      target_stamp_count=$(canonical_stamp_count "$supersedes" "")
      if [[ "$target_stamp_count" -gt 1 ]]; then release_state_lock; printf 'apply-promotions: ambiguous supersedes stamp\n' >&2; exit 1; fi
      target_decision=$(index_decision "$supersedes")
      if [[ "$target_stamp_count" -eq 1 ]]; then
        annotate_target=$supersedes
      elif [[ "$target_decision" == promoted || "$target_decision" == rolled-back ]]; then
        note='supersedes-unresolved'
      elif [[ -n "$target_decision" ]] && ! terminal_decision "$target_decision"; then
        pending_target=$supersedes
      elif [[ "$(literal_target_count "$supersedes")" -gt 0 ]]; then
        record_result "$id" "$class" skipped supersedes-not-owned - - "$target" - 1 || { release_state_lock; exit 1; }
        continue
      elif [[ -z "$target_decision" ]] && ! grep -Fxq "$supersedes" "$tmp_root/seen-ids" \
        && ! find "$parse_dir" -type f -name id -exec grep -Fxq "$supersedes" {} \; -print | grep -q .; then
        note='supersedes-unresolved'
      fi
    fi
    if [[ "$k" -lt "$promote_min_k" ]]; then
      record_result "$id" "$class" skipped k-below-2 "$note" - "$target" - 1 || { release_state_lock; exit 1; }
      continue
    fi
    if [[ "$week_k" -lt "$promote_min_weeks" ]]; then
      record_result "$id" "$class" skipped weeks-below-min "$note" - "$target" - 1 || { release_state_lock; exit 1; }
      continue
    fi
    approver=-
    auto_limit_reached=0
    if [[ "$approved" -eq 1 ]]; then approver=alpha
    elif [[ "$class" == capability-fact && "$auto_capability_facts" -eq 1 ]]; then
      approver=auto
      [[ "$auto_promotions" -ge "$max_auto" ]] && auto_limit_reached=1
    else
      record_result "$id" "$class" skipped awaiting-approval "$note" - "$target" - 1 || { release_state_lock; exit 1; }
      continue
    fi
    if [[ "$current_count" -ge "$cap" ]]; then
      record_result "$id" "$class" skipped section-full "$note" "$approver" "$target" - 1 || { release_state_lock; exit 1; }
      continue
    fi
    if [[ "$class" == capability-fact ]]; then section_promotions=$section_verified_promotions; else section_promotions=$section_rules_promotions; fi
    if [[ "$section_promotions" -ge "$max_per_section" || "$auto_limit_reached" -eq 1 ]]; then
      record_result "$id" "$class" skipped volume-guard "$note" "$approver" "$target" - 1 || { release_state_lock; exit 1; }
      continue
    fi
    line="- $run_date $theme (source: $id; reviewer: $reviewer; weeks: $weeks; k=$k; unit=$recurrence_unit; approver: $approver)"
    state_append_line "$heading" "$line" || { release_state_lock; exit 1; }
    if [[ -n "$annotate_target" ]]; then state_annotate_line "$annotate_target" "$id" || { release_state_lock; exit 1; }; fi
    line_sha=$(sha_line "$line") || { release_state_lock; exit 1; }
    record_result "$id" "$class" promoted - "$note" "$approver" "$target" "$line_sha" 1 || { release_state_lock; exit 1; }
    printf '%s\n' "$id" >>"$tmp_root/promoted-ids"
    if [[ -n "$pending_target" ]]; then
      pending_class=$(index_class "$pending_target")
      [[ "$pending_class" =~ ^(capability-fact|rule|skill)$ ]] || { release_state_lock; exit 1; }
      index_upsert "$pending_target" "$pending_class" superseded - || { release_state_lock; exit 1; }
    fi
    state_changed=1
    if [[ "$class" == capability-fact ]]; then
      verified_count=$((verified_count + 1)); section_verified_promotions=$((section_verified_promotions + 1))
      [[ "$approver" == auto ]] && auto_promotions=$((auto_promotions + 1))
    else
      rules_count=$((rules_count + 1)); section_rules_promotions=$((section_rules_promotions + 1))
    fi
  done <"$tmp_root/order"

  while IFS= read -r approval || [[ -n "$approval" ]]; do
    [[ -n "$approval" ]] || continue
    if ! grep -Fxq "$approval" "$tmp_root/seen-ids"; then
      class=$(index_class "$approval")
      decision_k=-
      decision_unit=-
      record_result "$approval" "$class" skipped unknown-approval - - - - 0 1 || { release_state_lock; exit 1; }
    fi
  done <"$approval_file"
fi

# All live STATE writes are here: after every refusal/guard and while the state
# lock is still held.  The index publish immediately follows in the same hold.
if [[ "$state_changed" -eq 1 ]]; then
  if ! atomic_write_file "$state_tmp" "$state_file"; then release_state_lock; exit 1; fi
fi
if [[ "${APPLY_TEST_CRASH_BETWEEN_STATE_AND_INDEX:-0}" == 1 ]]; then kill -KILL $$; fi
if ! atomic_write_file "$index_work" "$apply_index"; then release_state_lock; exit 1; fi

if [[ "${APPLY_TEST_CRASH_AFTER_PHASE2:-0}" == 1 ]]; then kill -KILL $$; fi
release_state_lock

if [[ "${APPLY_TEST_FORCE_PHASE3_LOCK_BUSY:-0}" == 1 ]]; then
  append_receipts_and_summary_direct lock-busy
  exit 1
fi
if ! take_promotions_lock; then
  append_receipts_and_summary_direct lock-busy
  exit 1
fi
cat "$receipts" >>"$apply_log"
append_direct "$(summary_with_reason -)"
release_promotions_lock
exit 0
