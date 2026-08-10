#!/usr/bin/env bash
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT=${TMPDIR:-/tmp}/skill-lint-test.$$
PASS_COUNT=0
FAIL_COUNT=0

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT HUP INT TERM

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'PASS %s\n' "$1"
}

fail_case() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'FAIL %s: %s\n' "$1" "$2"
}

mkdir -p "$TMP_ROOT"
ws=$TMP_ROOT/ws
"$ROOT/scripts/loop-init" --workspace "$ws"
mkdir -p "$ws/skills/_staging/bad-skill" "$ws/skills/good-skill"
cat >"$ws/skills/_staging/bad-skill/SKILL.md" <<'EOF'
---
name: bad-skill
description: this description is deliberately much longer than two hundred characters so the lint contract can prove it reports an overlong loader summary without changing health-check exit status or treating advisory skill authoring defects as missing workspace layout.
status: draft
---

# bad-skill

## Procedure

Do a thing.
EOF
cat >"$ws/skills/good-skill/SKILL.md" <<'EOF'
---
name: good-skill
description: good skill draft
trigger: good
status: draft
---

# good-skill

## Procedure

Do a thing.

## Verification

Check the thing.
EOF

# Multibyte description: 80 three-byte characters = 240 bytes > 200-byte budget,
# proving the budget is measured in BYTES (loader budgets are byte-based).
mkdir -p "$ws/skills/multibyte-skill"
{
  printf '%s\n' '---'
  printf '%s\n' 'name: multibyte-skill'
  printf 'description: '
  i=1
  while [ "$i" -le 80 ]; do
    printf '技'
    i=$((i + 1))
  done
  printf '\n'
  printf '%s\n' 'trigger: multibyte'
  printf '%s\n' 'status: draft'
  printf '%s\n' '---'
  printf '%s\n' ''
  printf '%s\n' '## Verification'
  printf '%s\n' 'Check.'
} >"$ws/skills/multibyte-skill/SKILL.md"

# Empty description + missing name/status frontmatter keys.
mkdir -p "$ws/skills/worse-skill"
cat >"$ws/skills/worse-skill/SKILL.md" <<'EOF'
---
description:
trigger: worse
---

# worse-skill

## Verification

Check.
EOF

mkdir -p "$ws/skills/verified-complete" "$ws/skills/draft-without-verification"
cat >"$ws/skills/verified-complete/SKILL.md" <<'EOF'
---
name: verified-complete
description: verified skill with complete verification metadata
trigger: verified-complete
status: verified
verified_at: 2026-08-10T00:00:00Z
verifier_id: test-verifier
---

# verified-complete

## Verification

Check.
EOF
cat >"$ws/skills/draft-without-verification/SKILL.md" <<'EOF'
---
name: draft-without-verification
description: draft skill without verification metadata
trigger: draft-without-verification
status: draft
---

# draft-without-verification

## Verification

Check.
EOF

output=$("$ROOT/install.sh" --check --workspace "$ws" 2>&1)
rc=$?
baseline_rc=$rc
if [ "$rc" -eq 0 ] \
  && printf '%s\n' "$output" | grep -q 'warning: skill lint: description exceeds 200 bytes: skills/_staging/bad-skill/SKILL.md' \
  && printf '%s\n' "$output" | grep -q 'warning: skill lint: missing ## Verification section: skills/_staging/bad-skill/SKILL.md' \
  && printf '%s\n' "$output" | grep -q 'warning: skill lint: missing trigger: skills/_staging/bad-skill/SKILL.md' \
  && ! printf '%s\n' "$output" | grep -q 'skill lint.*good-skill'; then
  pass "skill lint warns without changing layout-check success"
else
  fail_case "skill lint warns without changing layout-check success" "rc=$rc output=$output"
fi

if printf '%s\n' "$output" | grep -q 'warning: skill lint: description exceeds 200 bytes: skills/multibyte-skill/SKILL.md'; then
  pass "skill description budget is byte-measured for multibyte descriptions"
else
  fail_case "skill description budget is byte-measured for multibyte descriptions" "output=$output"
fi

if printf '%s\n' "$output" | grep -q 'warning: skill lint: missing description: skills/worse-skill/SKILL.md' \
  && printf '%s\n' "$output" | grep -q 'warning: skill lint: missing name: skills/worse-skill/SKILL.md' \
  && printf '%s\n' "$output" | grep -q 'warning: skill lint: missing status: skills/worse-skill/SKILL.md'; then
  pass "empty description and missing name/status are each warned"
else
  fail_case "empty description and missing name/status are each warned" "output=$output"
fi

if ! printf '%s\n' "$output" | grep -q 'skill lint: missing verified_at.*skills/verified-complete/SKILL.md' \
  && ! printf '%s\n' "$output" | grep -q 'skill lint: missing verifier_id.*skills/verified-complete/SKILL.md'; then
  pass "verified skill with verification metadata has no verification-field warnings"
else
  fail_case "verified skill with verification metadata has no verification-field warnings" "output=$output"
fi

if ! printf '%s\n' "$output" | grep -q 'skill lint: missing verified_at.*skills/draft-without-verification/SKILL.md' \
  && ! printf '%s\n' "$output" | grep -q 'skill lint: missing verifier_id.*skills/draft-without-verification/SKILL.md'; then
  pass "draft skill without verification metadata has no verification-field warnings"
else
  fail_case "draft skill without verification metadata has no verification-field warnings" "output=$output"
fi

mkdir -p "$ws/skills/verified-missing"
cat >"$ws/skills/verified-missing/SKILL.md" <<'EOF'
---
name: verified-missing
description: verified skill without verification metadata
trigger: verified-missing
status: verified
---

# verified-missing

## Verification

Check.
EOF

output=$("$ROOT/install.sh" --check --workspace "$ws" 2>&1)
rc=$?
if [ "$rc" -eq "$baseline_rc" ] \
  && printf '%s\n' "$output" | grep -q 'warning: skill lint: missing verified_at for status verified: skills/verified-missing/SKILL.md' \
  && printf '%s\n' "$output" | grep -q 'warning: skill lint: missing verifier_id for status verified: skills/verified-missing/SKILL.md'; then
  pass "verified skill warns for both missing fields without changing check exit status"
else
  fail_case "verified skill warns for both missing fields without changing check exit status" "baseline_rc=$baseline_rc rc=$rc output=$output"
fi

output=$(SKILL_DESC_MAX=10 "$ROOT/install.sh" --check --workspace "$ws" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] \
  && printf '%s\n' "$output" | grep -q 'warning: skill lint: description exceeds 10 bytes: skills/good-skill/SKILL.md'; then
  pass "skill description budget is environment-tunable"
else
  fail_case "skill description budget is environment-tunable" "rc=$rc output=$output"
fi

printf 'Summary: %s PASS, %s FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
