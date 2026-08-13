#!/bin/bash
# EV-005 admission validity test (translation-rules.md §5)
# Usage: validate-task.sh <task-dir> --repo <local-clone-path>
# pre_fix tree: donecheck must FAIL 5/5. fix tree: donecheck must PASS 5/5.
# Every run must leave the replica clean (read-only rule R7).
set -u
LC_ALL=C; export LC_ALL

TASK_DIR=""; REPO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    *) TASK_DIR="$1"; shift ;;
  esac
done
[ -n "$TASK_DIR" ] && [ -n "$REPO" ] || { echo "usage: validate-task.sh <task-dir> --repo <local-clone>" >&2; exit 2; }
TASK_DIR="$(cd "$TASK_DIR" && pwd)" || exit 2
REPO="$(cd "$REPO" && pwd)" || exit 2
[ -f "$TASK_DIR/meta.json" ] || { echo "E: no meta.json in $TASK_DIR" >&2; exit 2; }
[ -f "$TASK_DIR/donecheck.sh" ] || { echo "E: no donecheck.sh in $TASK_DIR" >&2; exit 2; }

meta() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2],""))' "$TASK_DIR/meta.json" "$1"; }
TASK_ID=$(meta id)
PRE=$(meta pre_fix); FIX=$(meta fix)
SYNTH=$(meta synthetic)
if [ "$SYNTH" = "True" ] || [ "$SYNTH" = "true" ]; then
  # synthetic tasks validate against base_sha (must FAIL) and a bundled solution patch (must PASS)
  PRE=$(meta base_sha)
  FIX=""
  [ -f "$TASK_DIR/solution.patch" ] || { echo "E: synthetic task without solution.patch" >&2; exit 2; }
fi
[ -n "$PRE" ] || { echo "E: no pre-tree SHA in meta.json" >&2; exit 2; }
TIMEOUT_S=$(meta timeout_s); [ -n "$TIMEOUT_S" ] || TIMEOUT_S=120

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$SELF_DIR/validate-logs"; mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/$TASK_ID.log"; : > "$LOG"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ev005-validate-XXXXXX") || exit 2
trap 'rm -rf "$WORK"' EXIT

build_replica() { # $1=sha $2=dest ; history-zero copy (R9)
  mkdir -p "$2"
  git -C "$REPO" archive "$1" | tar -x -C "$2" || return 1
  git -C "$2" init -q &&
  git -C "$2" -c user.name=ev005 -c user.email=ev005@local add -A &&
  git -C "$2" -c user.name=ev005 -c user.email=ev005@local commit -qm "task snapshot" || return 1
}

run_one() { # $1=tree-dir $2=label $3=run-idx ; echoes donecheck exit code
  local rc t0 t1
  cp "$TASK_DIR/donecheck.sh" "$1/.ev005-donecheck.sh"
  [ -d "$TASK_DIR/fixtures" ] && cp -R "$TASK_DIR/fixtures" "$1/.ev005-fixtures"
  git -C "$1" -c user.name=ev005 -c user.email=ev005@local add -A >/dev/null 2>&1
  git -C "$1" -c user.name=ev005 -c user.email=ev005@local commit -qm "inject donecheck" >/dev/null 2>&1
  t0=$(date +%s)
  ( cd "$1" && bash .ev005-donecheck.sh ) >>"$LOG" 2>&1 &
  local pid=$!
  ( sleep "$TIMEOUT_S" && kill -9 "$pid" 2>/dev/null ) & local kpid=$!
  wait "$pid" 2>/dev/null; rc=$?
  kill "$kpid" 2>/dev/null; wait "$kpid" 2>/dev/null
  t1=$(date +%s)
  if [ -n "$(git -C "$1" status --porcelain)" ]; then
    echo "RUN $TASK_ID $2 $3 exit=$rc dur=$((t1-t0))s DIRTY-TREE(R7 violation)" | tee -a "$LOG"
    return 3
  fi
  echo "RUN $TASK_ID $2 $3 exit=$rc dur=$((t1-t0))s" >> "$LOG"
  return "$rc"
}

verdict=PASS
expect() { # $1=label(pre|fix) $2=expected(0|nonzero)
  local i rc dir
  for i in 1 2 3 4 5; do
    dir="$WORK/$1-$i"
    if [ "$1" = "fix" ] && [ -n "$FIX" ]; then
      build_replica "$FIX" "$dir" || { echo "E: replica build failed (fix)"; verdict=FAIL; return; }
    else
      build_replica "$PRE" "$dir" || { echo "E: replica build failed ($1)"; verdict=FAIL; return; }
    fi
    if [ "$1" = "fix" ] && [ -z "$FIX" ]; then
      ( cd "$dir" && git apply "$TASK_DIR/solution.patch" ) || { echo "E: solution.patch failed"; verdict=FAIL; return; }
      git -C "$dir" -c user.name=ev005 -c user.email=ev005@local add -A >/dev/null 2>&1
      git -C "$dir" -c user.name=ev005 -c user.email=ev005@local commit -qm "apply solution" >/dev/null 2>&1
    fi
    run_one "$dir" "$1" "$i"; rc=$?
    if [ "$2" = "0" ] && [ "$rc" -ne 0 ]; then verdict=FAIL; echo "UNEXPECTED $1 run$i exit=$rc (want 0)"; fi
    if [ "$2" = "nonzero" ] && [ "$rc" -eq 0 ]; then verdict=FAIL; echo "UNEXPECTED $1 run$i exit=0 (want fail)"; fi
  done
}

echo "== validate $TASK_ID pre=$PRE fix=${FIX:-patch} repo=$REPO ==" | tee -a "$LOG"
expect "pre" "nonzero"
expect "fix" "0"
echo "VERDICT $TASK_ID $verdict" | tee -a "$LOG"
[ "$verdict" = "PASS" ]
