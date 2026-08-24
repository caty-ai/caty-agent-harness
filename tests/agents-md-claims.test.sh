#!/bin/bash
# AGENTS.md claim-drift check (#155).
#
# AGENTS.md duplicates a small number of facts whose sources live elsewhere in
# the repository (workflow triggers, the adapter-contract scope, make targets,
# the required-check list). Each such fact carries a machine-readable marker:
#
#   <!-- claim: <type> <args...> -->
#
# This suite evaluates every marker against its source and fails when they
# disagree. It is fail-closed: zero evaluated claims is a failure, an unknown
# claim type is a failure, and a workflow file or make target mentioned in the
# prose without a covering marker is a failure.
#
# Claim vocabulary:
#   make-target <name>              Makefile defines <name> as a target
#   contract-scope <adapter>...     adapters/CONTRACT.md names exactly these
#                                   adapters in its normative-scope sentence
#   workflow-on <file> <event>...   each event is a top-level trigger of
#                                   .github/workflows/<file>
#   workflow-not-on <file> <event>... each event is NOT a trigger of <file>
#   required-check <job> / <check>  <job> is a job id in a pull_request-
#                                   triggered workflow of this repository.
#                                   When the branch-protection API is readable
#                                   (maintainer machines), the full claimed set
#                                   must equal the protected contexts exactly.
#
# Bash 3.2+; no dependencies beyond what the repository already requires.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

pass_count=0
fail_count=0
TMP=$(mktemp -d "${TMPDIR:-/tmp}/agents-md-claims-test.XXXXXX")

log() {
  printf '%s\n' "$*"
}

pass() {
  pass_count=$(( pass_count + 1 ))
  log "PASS $1"
}

fail() {
  fail_count=$(( fail_count + 1 ))
  log "FAIL $1: $2"
}

cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT HUP INT TERM

# ---------------------------------------------------------------------------
# Checker core. Everything below operates on a repository root passed as $1 so
# the same code path runs against throwaway fixtures and the real repository.
# ---------------------------------------------------------------------------

# Top-level trigger events of a workflow file, one per line.
# Handles the three forms used here: block map, inline list, bare scalar.
workflow_events() {
  awk '
    /^on:[[:space:]]*$/ { inon = 1; next }
    /^on:[[:space:]]*\[/ {
      line = $0
      sub(/^on:[[:space:]]*\[/, "", line); sub(/\].*/, "", line)
      count = split(line, items, ",")
      for (i = 1; i <= count; i++) {
        gsub(/[[:space:]]/, "", items[i])
        if (items[i] != "") print items[i]
      }
      exit
    }
    /^on:[[:space:]]+[a-z_]+[[:space:]]*(#.*)?$/ {
      line = $0; sub(/^on:[[:space:]]+/, "", line)
      sub(/[[:space:]]*#.*/, "", line); gsub(/[[:space:]]/, "", line)
      print line; exit
    }
    inon && /^[^[:space:]#]/ { inon = 0 }
    inon && /^[[:space:]]+[a-z_]+:/ {
      match($0, /^[[:space:]]*/)
      if (! event_indent) event_indent = RLENGTH
      if (RLENGTH == event_indent) {
        k = $1; sub(/:.*/, "", k); print k
      }
    }
  ' "$1"
}

# Job ids of a workflow file, one per line.
workflow_jobs() {
  awk '
    /^jobs:[[:space:]]*$/ { injobs = 1; next }
    injobs && /^[^[:space:]#]/ { injobs = 0 }
    injobs && /^[[:space:]]+[A-Za-z0-9_-]+:/ {
      match($0, /^[[:space:]]*/)
      if (! job_indent) job_indent = RLENGTH
      if (RLENGTH == job_indent) {
        k = $1; sub(/:.*/, "", k); print k
      }
    }
  ' "$1"
}

# All claim markers of an AGENTS.md, with the wrapper stripped.
extract_claims() {
  awk '
    /^<!-- claim: [a-z-]+( [^ ].*)? -->$/ {
      line = $0
      sub(/^<!-- claim: /, "", line)
      sub(/ -->$/, "", line)
      print line
    }
  ' "$1"
}

output_has_line() {
  local output=$1
  local expected=$2
  printf '%s\n' "$output" | grep -qxF -- "$expected"
}

# check_claims <root> — evaluates every claim in <root>/AGENTS.md.
# Prints one "claim-error: ..." line per violation; returns 1 if any.
check_claims() {
  local root=$1
  local agents="$root/AGENTS.md"
  local errors=0
  local claims_checked=0

  if [ ! -f "$agents" ]; then
    log "claim-error: $agents does not exist"
    return 1
  fi

  # --- relative links resolve (global, no marker needed) ------------------
  local links_checked=0
  local link target
  while IFS= read -r link; do
    case "$link" in
      http://*|https://*|mailto:*|'#'*) continue ;;
    esac
    target=${link%%#*}
    [ -n "$target" ] || continue
    links_checked=$(( links_checked + 1 ))
    if [ ! -e "$root/$target" ]; then
      log "claim-error: relative link does not resolve: $link"
      errors=$(( errors + 1 ))
    fi
  done <<EOF
$({ grep -oE '\]\([^)]+\)' "$agents" || true; } | sed -e 's/^](//' -e 's/)$//')
EOF
  if [ "$links_checked" -eq 0 ]; then
    log "claim-error: zero relative links found - refusing vacuous green"
    errors=$(( errors + 1 ))
  fi

  # --- marked claims ------------------------------------------------------
  local malformed
  while IFS= read -r malformed; do
    [ -n "$malformed" ] || continue
    log "claim-error: malformed claim marker: $malformed"
    errors=$(( errors + 1 ))
  done <<EOF
$(awk 'index($0, "<!-- claim:") && $0 !~ /^<!-- claim: [a-z-]+( [^ ].*)? -->$/ { print }' "$agents")
EOF

  local claim ctype args
  while IFS= read -r claim; do
    [ -n "$claim" ] || continue
    claims_checked=$(( claims_checked + 1 ))
    case "$claim" in
      *' '*) ctype=${claim%% *}; args=${claim#* } ;;
      *) ctype=$claim; args= ;;
    esac
    case "$ctype" in

      make-target)
        if ! printf '%s\n' "$args" | grep -qE '^[A-Za-z0-9_.-]+$'; then
          log "claim-error: make-target: invalid arguments: $args"
          errors=$(( errors + 1 ))
        elif ! grep -qE "^${args}([[:space:]]+[^:]*)?:" "$root/Makefile" 2>/dev/null; then
          log "claim-error: make-target '$args' not defined in Makefile"
          errors=$(( errors + 1 ))
        fi
        ;;

      contract-scope)
        local sentence scope_words adapter dir dirname listed
        if ! printf '%s\n' "$args" \
          | grep -qE '^[A-Za-z0-9_.-]+( [A-Za-z0-9_.-]+)*$'; then
          log "claim-error: contract-scope: invalid arguments: $args"
          errors=$(( errors + 1 ))
          continue
        fi
        sentence=$(awk 'tolower($0) ~ /normative for/ { print; exit }' \
          "$root/adapters/CONTRACT.md" 2>/dev/null \
          | tr 'A-Z' 'a-z' | sed 's/claude code/claude-code/g')
        if [ -z "$sentence" ]; then
          log "claim-error: contract-scope: no 'normative for' sentence in adapters/CONTRACT.md"
          errors=$(( errors + 1 ))
        else
          scope_words=$(printf '%s\n' "$sentence" | tr -cs 'a-z0-9_-' '\n')
          for adapter in $args; do
            if [ ! -d "$root/adapters/$adapter" ]; then
              log "claim-error: contract-scope: claimed adapter directory does not exist: $adapter"
              errors=$(( errors + 1 ))
            fi
            if ! printf '%s\n' "$scope_words" | grep -qxF "$adapter"; then
              log "claim-error: contract-scope: '$adapter' claimed but absent from CONTRACT.md scope sentence"
              errors=$(( errors + 1 ))
            fi
          done
          for dir in "$root"/adapters/*/; do
            dirname=$(basename "$dir")
            listed=0
            for adapter in $args; do
              [ "$adapter" = "$dirname" ] && listed=1
            done
            if [ "$listed" -eq 0 ]; then
              if printf '%s\n' "$scope_words" | grep -qxF "$dirname"; then
                log "claim-error: contract-scope: '$dirname' appears in CONTRACT.md scope sentence but is not claimed"
                errors=$(( errors + 1 ))
              fi
            fi
          done
        fi
        ;;

      workflow-on|workflow-not-on)
        local wfile events ev found
        if ! printf '%s\n' "$args" \
          | grep -qE '^[A-Za-z0-9_.-]+( [a-z_]+)+$'; then
          log "claim-error: $ctype: invalid arguments: $args"
          errors=$(( errors + 1 ))
          continue
        fi
        wfile=${args%% *}
        if [ ! -f "$root/.github/workflows/$wfile" ]; then
          log "claim-error: $ctype: no such workflow file: $wfile"
          errors=$(( errors + 1 ))
        else
          events=$(workflow_events "$root/.github/workflows/$wfile")
          if [ -z "$events" ]; then
            log "claim-error: $ctype: cannot parse triggers of $wfile"
            errors=$(( errors + 1 ))
          else
            for ev in ${args#* }; do
              found=0
              case "
$events
" in
                *"
$ev
"*) found=1 ;;
              esac
              if [ "$ctype" = "workflow-on" ] && [ "$found" -eq 0 ]; then
                log "claim-error: workflow-on: $wfile does not trigger on '$ev' (actual: $(printf '%s' "$events" | tr '\n' ' '))"
                errors=$(( errors + 1 ))
              fi
              if [ "$ctype" = "workflow-not-on" ] && [ "$found" -eq 1 ]; then
                log "claim-error: workflow-not-on: $wfile DOES trigger on '$ev'"
                errors=$(( errors + 1 ))
              fi
            done
          fi
        fi
        ;;

      required-check)
        local caller_job wf wf_ok
        if ! printf '%s\n' "$args" \
          | grep -qE '^[A-Za-z0-9_-]+[[:space:]]+/[[:space:]]+[A-Za-z0-9_-]+$'; then
          log "claim-error: required-check: invalid arguments: $args"
          errors=$(( errors + 1 ))
          continue
        fi
        caller_job=$(printf '%s' "$args" | sed 's|[[:space:]]*/.*||')
        wf_ok=0
        for wf in "$root"/.github/workflows/*.yml; do
          [ -f "$wf" ] || continue
          if workflow_jobs "$wf" | grep -qxF "$caller_job"; then
            if workflow_events "$wf" | grep -qxF "pull_request"; then
              wf_ok=1
              break
            fi
          fi
        done
        if [ "$wf_ok" -eq 0 ]; then
          log "claim-error: required-check: '$caller_job' is not a job id of any pull_request-triggered workflow"
          errors=$(( errors + 1 ))
        fi
        ;;

      *)
        log "claim-error: unknown claim type '$ctype' - add it to the checker or remove the marker"
        errors=$(( errors + 1 ))
        ;;
    esac
  done <<EOF
$(extract_claims "$agents")
EOF

  # --- fail closed --------------------------------------------------------
  if [ "$claims_checked" -eq 0 ]; then
    log "claim-error: zero claims checked - refusing vacuous green (fail-closed)"
    errors=$(( errors + 1 ))
  fi

  # --- coverage guard: prose mentions without a marker --------------------
  # A workflow file named in the prose is a trigger claim; a `make <target>`
  # in the prose is an existence claim. Naming one without a marker fails.
  local mention
  while IFS= read -r mention; do
    [ -n "$mention" ] || continue
    if [ ! -f "$root/.github/workflows/$mention" ]; then
      log "claim-error: coverage: $mention is mentioned but no such workflow file exists"
      errors=$(( errors + 1 ))
    elif ! extract_claims "$agents" | grep -qE "^workflow-(on|not-on) $mention( |$)"; then
      log "claim-error: coverage: $mention is mentioned but carries no workflow-on/workflow-not-on claim"
      errors=$(( errors + 1 ))
    fi
  done <<EOF
$(awk '
  {
    line = $0
    while (match(line, /[A-Za-z0-9_-]+\.(yml|yaml)/)) {
      before = substr(line, 1, RSTART - 1)
      mention = substr(line, RSTART, RLENGTH)
      line = substr(line, RSTART + RLENGTH)
      nextchar = substr(line, 1, 1)
      if (before !~ /[A-Za-z0-9_.\/-]$/ \
          && nextchar !~ /[A-Za-z0-9_\/-]/ \
          && line !~ /^\.[A-Za-z0-9_-]/) print mention
    }
  }
' "$agents" | sort -u)
EOF

  while IFS= read -r mention; do
    [ -n "$mention" ] || continue
    if ! extract_claims "$agents" | grep -qxF "make-target $mention"; then
      log "claim-error: coverage: 'make $mention' is mentioned but carries no make-target claim"
      errors=$(( errors + 1 ))
    fi
  done <<EOF
$({ grep -oE 'make [A-Za-z0-9_.][A-Za-z0-9_.-]*' "$agents" || true; } | sed 's/^make //' | sort -u)
EOF

  if [ -f "$root/adapters/CONTRACT.md" ] \
    && grep -qi 'normative for' "$root/adapters/CONTRACT.md" \
    && ! extract_claims "$agents" | grep -qE '^contract-scope( |$)'; then
    log "claim-error: coverage: adapters/CONTRACT.md contains a 'normative for' line but AGENTS.md carries no contract-scope claim"
    errors=$(( errors + 1 ))
  fi

  while IFS= read -r mention; do
    [ -n "$mention" ] || continue
    if ! extract_claims "$agents" | grep -qxF "required-check $mention"; then
      log "claim-error: coverage: '$mention' is mentioned but carries no required-check claim"
      errors=$(( errors + 1 ))
    fi
  done <<EOF
$({ grep -oE '`[A-Za-z0-9_-]+[[:space:]]+/[[:space:]]+[A-Za-z0-9_-]+`' "$agents" || true; } \
  | sed -e 's/^`//' -e 's/`$//' \
  | awk '{ print $1 " / " $3 }' | sort -u)
EOF

  log "claims-checked=$claims_checked links-checked=$links_checked"
  [ "$errors" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Fixture builder for negative cases.
# ---------------------------------------------------------------------------

build_fixture() {
  local dir=$1
  rm -rf "$dir"
  mkdir -p "$dir/.github/workflows" "$dir/adapters/alpha-ad" "$dir/adapters/beta-ad" "$dir/docs"
  printf 'This contract is normative for the Alpha-Ad adapter.\n' >"$dir/adapters/CONTRACT.md"
  printf 'placeholder\n' >"$dir/docs/guide.md"
  cat >"$dir/Makefile" <<'MK'
test:
	@true
MK
  cat >"$dir/.github/workflows/gate.yml" <<'WF'
name: Gate
on:
  pull_request:
jobs:
  gate:
    runs-on: ubuntu-latest
    steps:
      - run: true
WF
  cat >"$dir/AGENTS.md" <<'MD'
# fixture map

See [docs/guide.md](docs/guide.md). Verify with `make test`.
The gate runs on every PR via gate.yml.
The prose-only example path docs/config.yaml is not a workflow mention.

<!-- claim: make-target test -->
<!-- claim: contract-scope alpha-ad -->
<!-- claim: workflow-on gate.yml pull_request -->
<!-- claim: workflow-not-on gate.yml push -->
<!-- claim: required-check gate / inner -->
MD
}

# ---------------------------------------------------------------------------
# Cases
# ---------------------------------------------------------------------------

FX="$TMP/fixture"

# 1. A consistent fixture passes.
build_fixture "$FX"
if out=$(check_claims "$FX"); then
  pass fixture-consistent-passes
else
  fail fixture-consistent-passes "expected pass, got: $out"
fi

# 2. Inline-list and scalar workflow trigger forms are parsed explicitly. The
#    real repository covers the block-map form.
cat >"$FX/.github/workflows/inline.yml" <<'WF'
name: Inline
on: [pull_request, workflow_dispatch]
WF
cat >"$FX/.github/workflows/scalar.yml" <<'WF'
name: Scalar
on: push
WF
inline_events=$(workflow_events "$FX/.github/workflows/inline.yml")
scalar_events=$(workflow_events "$FX/.github/workflows/scalar.yml")
if [ "$inline_events" = "$(printf 'pull_request\nworkflow_dispatch')" ] \
  && [ "$scalar_events" = "push" ]; then
  pass workflow-trigger-syntaxes-supported
else
  fail workflow-trigger-syntaxes-supported \
    "inline=[$(printf '%s' "$inline_events" | tr '\n' ';')] scalar=[$scalar_events]"
fi

# 3. Trigger drift: the workflow moves off pull_request; the claim still says
#    pull_request. Both the workflow-on claim and the required-check claim
#    must catch it.
build_fixture "$FX"
sed -i.bak 's/^  pull_request:/  push:/' "$FX/.github/workflows/gate.yml" && rm -f "$FX/.github/workflows/gate.yml.bak"
if out=$(check_claims "$FX"); then
  fail drift-trigger-fails "trigger drift passed undetected"
else
  if output_has_line "$out" "claim-error: workflow-on: gate.yml does not trigger on 'pull_request' (actual: push)" \
    && output_has_line "$out" "claim-error: workflow-not-on: gate.yml DOES trigger on 'push'" \
    && output_has_line "$out" "claim-error: required-check: 'gate' is not a job id of any pull_request-triggered workflow"; then
    pass drift-trigger-fails
  else
    fail drift-trigger-fails "failed for the wrong reason: $out"
  fi
fi

# 4. Contract-scope drift, both directions.
build_fixture "$FX"
printf 'This contract is normative for the Alpha-Ad and Beta-Ad adapters.\n' >"$FX/adapters/CONTRACT.md"
if out=$(check_claims "$FX"); then
  fail drift-scope-widened-fails "scope widening passed undetected"
else
  if output_has_line "$out" "claim-error: contract-scope: 'beta-ad' appears in CONTRACT.md scope sentence but is not claimed"; then
    pass drift-scope-widened-fails
  else
    fail drift-scope-widened-fails "failed for the wrong reason: $out"
  fi
fi

build_fixture "$FX"
printf 'This contract is normative for the Beta-Ad adapter.\n' >"$FX/adapters/CONTRACT.md"
if out=$(check_claims "$FX"); then
  fail drift-scope-narrowed-fails "scope narrowing passed undetected"
else
  if output_has_line "$out" "claim-error: contract-scope: 'alpha-ad' claimed but absent from CONTRACT.md scope sentence"; then
    pass drift-scope-narrowed-fails
  else
    fail drift-scope-narrowed-fails "failed for the wrong reason: $out"
  fi
fi

# 5. Fail-closed: an AGENTS.md with no markers at all is a failure even
#    though nothing it says is wrong.
build_fixture "$FX"
cat >"$FX/AGENTS.md" <<'MD'
# fixture map

See [docs/guide.md](docs/guide.md).
MD
if out=$(check_claims "$FX"); then
  fail fail-closed-zero-claims "zero claims passed"
else
  if output_has_line "$out" "claim-error: zero claims checked - refusing vacuous green (fail-closed)"; then
    pass fail-closed-zero-claims
  else
    fail fail-closed-zero-claims "failed for the wrong reason: $out"
  fi
fi

# 6. Unknown claim type fails loudly.
build_fixture "$FX"
printf '<!-- claim: sha-of-truth abc123 -->\n' >>"$FX/AGENTS.md"
if out=$(check_claims "$FX"); then
  fail unknown-claim-type-fails "unknown claim type passed"
else
  if output_has_line "$out" "claim-error: unknown claim type 'sha-of-truth' - add it to the checker or remove the marker"; then
    pass unknown-claim-type-fails
  else
    fail unknown-claim-type-fails "failed for the wrong reason: $out"
  fi
fi

# 7. A dead relative link fails.
build_fixture "$FX"
rm "$FX/docs/guide.md"
if out=$(check_claims "$FX"); then
  fail dead-link-fails "dead relative link passed"
else
  if output_has_line "$out" "claim-error: relative link does not resolve: docs/guide.md"; then
    pass dead-link-fails
  else
    fail dead-link-fails "failed for the wrong reason: $out"
  fi
fi

# 8. Missing make target fails.
build_fixture "$FX"
printf 'all:\n\t@true\n' >"$FX/Makefile"
if out=$(check_claims "$FX"); then
  fail missing-make-target-fails "missing make target passed"
else
  if output_has_line "$out" "claim-error: make-target 'test' not defined in Makefile"; then
    pass missing-make-target-fails
  else
    fail missing-make-target-fails "failed for the wrong reason: $out"
  fi
fi

# 9. Coverage guard: mentioning a .yaml workflow file with no covering claim
#    fails, while the docs/config.yaml path in every fixture remains ignored.
build_fixture "$FX"
cp "$FX/.github/workflows/gate.yml" "$FX/.github/workflows/extra.yaml"
printf 'Also see extra.yaml for the extra gate.\n' >>"$FX/AGENTS.md"
if out=$(check_claims "$FX"); then
  fail coverage-unmarked-workflow-fails "unmarked workflow mention passed"
else
  if output_has_line "$out" "claim-error: coverage: extra.yaml is mentioned but carries no workflow-on/workflow-not-on claim"; then
    pass coverage-unmarked-workflow-fails
  else
    fail coverage-unmarked-workflow-fails "failed for the wrong reason: $out"
  fi
fi

# 10. Coverage guard: mentioning `make <target>` with no covering claim fails.
build_fixture "$FX"
printf 'Also run `make lint` before pushing.\n' >>"$FX/AGENTS.md"
if out=$(check_claims "$FX"); then
  fail coverage-unmarked-make-fails "unmarked make mention passed"
else
  if output_has_line "$out" "claim-error: coverage: 'make lint' is mentioned but carries no make-target claim"; then
    pass coverage-unmarked-make-fails
  else
    fail coverage-unmarked-make-fails "failed for the wrong reason: $out"
  fi
fi

# ---------------------------------------------------------------------------
# 11. Coverage guard: a mentioned workflow with no source file fails even when
#     its workflow claim markers are also gone.
# ---------------------------------------------------------------------------

build_fixture "$FX"
rm "$FX/.github/workflows/gate.yml"
sed -i.bak '/claim: workflow-on gate.yml/d; /claim: workflow-not-on gate.yml/d' "$FX/AGENTS.md" \
  && rm -f "$FX/AGENTS.md.bak"
if out=$(check_claims "$FX"); then
  fail coverage-missing-workflow-fails "missing workflow mention passed"
else
  if output_has_line "$out" "claim-error: coverage: gate.yml is mentioned but no such workflow file exists"; then
    pass coverage-missing-workflow-fails
  else
    fail coverage-missing-workflow-fails "failed for the wrong reason: $out"
  fi
fi

# 12. An unsupported flow-map trigger form fails as unparseable for both
#     positive and negative trigger claims.
build_fixture "$FX"
cat >"$FX/.github/workflows/gate.yml" <<'WF'
name: Gate
on: { pull_request: }
jobs:
  gate:
    runs-on: ubuntu-latest
    steps:
      - run: true
WF
if out=$(check_claims "$FX"); then
  fail workflow-flow-map-fails "flow-map triggers passed"
else
  if output_has_line "$out" "claim-error: workflow-on: cannot parse triggers of gate.yml" \
    && output_has_line "$out" "claim-error: workflow-not-on: cannot parse triggers of gate.yml"; then
    pass workflow-flow-map-fails
  else
    fail workflow-flow-map-fails "failed for the wrong reason: $out"
  fi
fi

# 13. A normative contract source requires at least one contract-scope marker.
build_fixture "$FX"
sed -i.bak '/claim: contract-scope alpha-ad/d' "$FX/AGENTS.md" && rm -f "$FX/AGENTS.md.bak"
if out=$(check_claims "$FX"); then
  fail coverage-missing-contract-scope-fails "missing contract-scope marker passed"
else
  if output_has_line "$out" "claim-error: coverage: adapters/CONTRACT.md contains a 'normative for' line but AGENTS.md carries no contract-scope claim"; then
    pass coverage-missing-contract-scope-fails
  else
    fail coverage-missing-contract-scope-fails "failed for the wrong reason: $out"
  fi
fi

# 14. A backticked required-check context in prose requires its marker.
build_fixture "$FX"
sed -i.bak '/claim: required-check gate \/ inner/d' "$FX/AGENTS.md" && rm -f "$FX/AGENTS.md.bak"
printf 'The required context is `gate / inner`.\n' >>"$FX/AGENTS.md"
if out=$(check_claims "$FX"); then
  fail coverage-unmarked-required-check-fails "unmarked required-check context passed"
else
  if output_has_line "$out" "claim-error: coverage: 'gate / inner' is mentioned but carries no required-check claim"; then
    pass coverage-unmarked-required-check-fails
  else
    fail coverage-unmarked-required-check-fails "failed for the wrong reason: $out"
  fi
fi

# 15. Uppercase and underscore are part of the make-target mention grammar.
build_fixture "$FX"
printf 'Also run `make TEST_ALL` before pushing.\n' >>"$FX/AGENTS.md"
if out=$(check_claims "$FX"); then
  fail coverage-unmarked-uppercase-make-fails "uppercase make mention passed"
else
  if output_has_line "$out" "claim-error: coverage: 'make TEST_ALL' is mentioned but carries no make-target claim"; then
    pass coverage-unmarked-uppercase-make-fails
  else
    fail coverage-unmarked-uppercase-make-fails "failed for the wrong reason: $out"
  fi
fi

# ---------------------------------------------------------------------------
# 16. The real repository's AGENTS.md passes against its real sources.
# ---------------------------------------------------------------------------

if out=$(check_claims "$ROOT"); then
  pass real-agents-md-consistent
else
  fail real-agents-md-consistent "$out"
fi

# 17. Best effort, maintainer machines only: when the branch-protection API is
#     readable, the claimed required-check set must equal the protected
#     contexts exactly. CI tokens cannot read this endpoint; that is not a
#     bypass of the suite - the source-level half of the claim ran above.
repo_url=$(git -C "$ROOT" config --get remote.origin.url 2>/dev/null || true)
repo_slug=$(printf '%s\n' "$repo_url" \
  | sed -e 's|^.*github.com[:/]||' -e 's|\.git$||')
if [ -n "$repo_slug" ] && command -v gh >/dev/null 2>&1 \
  && protected=$(gh api "repos/$repo_slug/branches/main/protection/required_status_checks" \
      --jq '.contexts[]' 2>/dev/null); then
  claimed=$(extract_claims "$ROOT/AGENTS.md" \
    | awk '/^required-check / { sub(/^required-check /, ""); print }' | sort)
  if [ "$(printf '%s\n' "$protected" | sort)" = "$claimed" ]; then
    pass required-checks-match-branch-protection
  else
    fail required-checks-match-branch-protection \
      "claimed [$(printf '%s' "$claimed" | tr '\n' ';')] != protected [$(printf '%s' "$protected" | sort | tr '\n' ';')]"
  fi
else
  log "note: branch-protection API not readable here; required-check claims validated against workflow sources only"
fi

log "TOTAL pass=$pass_count fail=$fail_count"
if [ "$fail_count" -ne 0 ]; then
  exit 1
fi
