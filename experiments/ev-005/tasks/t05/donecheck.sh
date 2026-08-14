#!/bin/bash
set -u
LC_ALL=C
export LC_ALL

fail=0

pass() {
  printf 'CHECK %s PASS %s\n' "$1" "$2"
}

fail_check() {
  printf 'CHECK %s FAIL %s\n' "$1" "$2"
  fail=1
}

require_file() {
  if [ ! -f "$1" ]; then
    fail_check "$2" "missing file $1"
    return 1
  fi
  return 0
}

check_contains_many() {
  local id reason file pattern
  id=$1
  reason=$2
  file=$3
  shift 3
  require_file "$file" "$id" || return
  for pattern in "$@"; do
    if ! grep -Fq -- "$pattern" "$file"; then
      fail_check "$id" "missing pattern [$pattern] in $file"
      return
    fi
  done
  pass "$id" "$reason"
}

check_contains() {
  check_contains_many "$1" "$2" "$3" "$4"
}

check_absent_many() {
  local id reason file pattern
  id=$1
  reason=$2
  file=$3
  shift 3
  require_file "$file" "$id" || return
  for pattern in "$@"; do
    if grep -Fq -- "$pattern" "$file"; then
      fail_check "$id" "forbidden pattern [$pattern] present in $file"
      return
    fi
  done
  pass "$id" "$reason"
}

check_exact_blob() {
  local id reason path expected actual
  id=$1
  reason=$2
  path=$3
  expected=$4
  require_file "$path" "$id" || return
  actual=$(git hash-object -- "$path" 2>/dev/null) || {
    fail_check "$id" "could not hash $path"
    return
  }
  if [ "$actual" != "$expected" ]; then
    fail_check "$id" "blob hash mismatch for $path"
    return
  fi
  pass "$id" "$reason"
}

check_contains a01 "example task uses a local SVG artifact path" \
  "templates/examples/img-pilot.task.md" 'out/image.svg'
check_contains a02 "example task checks for an SVG root element" \
  "templates/examples/img-pilot.task.md" '<svg xmlns="http://www.w3.org/2000/svg"'
check_contains a03 "example task receipt declares the SVG artifact path" \
  "templates/examples/img-pilot.task.md" '"artifact": "out/image.svg"'
check_contains a04 "example task lists bash as a resource" \
  "templates/examples/img-pilot.task.md" '- bash'
check_contains a05 "example task lists python3 standard library as a resource" \
  "templates/examples/img-pilot.task.md" '- python3 standard library'
check_absent_many a06 "example task drops the old backend dependency name" \
  "templates/examples/img-pilot.task.md" 'LUCA_IMAGE_BACKEND'
check_absent_many a07 "example task drops the old push channel dependency name" \
  "templates/examples/img-pilot.task.md" 'FAMILY_PUSH_CHANNEL'
check_absent_many a08 "example task drops the old PNG artifact path" \
  "templates/examples/img-pilot.task.md" 'image.png'
check_absent_many a09 "example task drops the old scoring step" \
  "templates/examples/img-pilot.task.md" 'vision-rubric scoring'
check_contains a10 "codex install uses the placeholder charter path" \
  "adapters/codex/INSTALL.md" '~/path/to/your/AGENTS.md'
check_contains a11 "codex install includes setup guidance for the placeholder charter path" \
  "adapters/codex/INSTALL.md" "Replace this placeholder with the operator's own"
check_contains a12 "kimi install uses the placeholder charter path" \
  "adapters/kimi/INSTALL.md" '~/path/to/your/AGENTS.md'
check_contains a13 "kimi install includes setup guidance for the placeholder charter path" \
  "adapters/kimi/INSTALL.md" "operator's own agent charter file path during setup."
check_contains a14 "hermes cron example uses a placeholder secrets path" \
  "adapters/hermes/INSTALL.md" '/path/to/secrets/cron.env'
check_contains a15 "hermes cron example uses a placeholder workspace path" \
  "adapters/hermes/INSTALL.md" '/path/to/hermes-home/profiles/example/workspace'
check_contains a16 "task template uses the generic issued_by value" \
  "templates/TASK.tmpl.md" 'issued_by: example-operator'
check_contains a17 "task template uses the generic escalate_to value" \
  "templates/TASK.tmpl.md" 'escalate_to: example-operator'
check_absent_many a18 "task template drops the old issued_by value" \
  "templates/TASK.tmpl.md" 'issued_by: sho-alpha'
check_absent_many a19 "task template drops the old escalate_to value" \
  "templates/TASK.tmpl.md" 'escalate_to: sho'
check_contains a20 "example task uses the generic issued_by value" \
  "templates/examples/img-pilot.task.md" 'issued_by: example-operator'
check_contains a21 "example task uses the generic escalate_to value" \
  "templates/examples/img-pilot.task.md" 'escalate_to: example-operator'
check_absent_many a22 "example task drops the old issued_by value" \
  "templates/examples/img-pilot.task.md" 'issued_by: sho-alpha'
check_absent_many a23 "example task drops the old escalate_to value" \
  "templates/examples/img-pilot.task.md" 'escalate_to: sho'
check_contains a24 "family-updater removes the implicit default reporter path" \
  "scripts/family-updater" 'fma_scripts_dir=${FMA_SCRIPTS_DIR:-}'
check_contains a25 "family-updater warns when the reporter path is omitted" \
  "scripts/family-updater" 'When omitted, reporting is disabled with a warning.'
check_contains a26 "family-updater documents the explicit override for the reporter path" \
  "scripts/family-updater" 'Set FMA_SCRIPTS_DIR or pass --fma-scripts-dir <dir>.'
check_absent_many a27 "family-updater drops the old private default reporter path" \
  "scripts/family-updater" '$HOME/claude-workspace/family-memory-architecture/scripts'
check_contains a28 "updater cron template requires an explicit reporter-path setting" \
  "templates/updater-cron.tmpl.sh" 'FMA_SCRIPTS_DIR is not set; set it to the reporter directory'
check_contains a29 "updater cron template shows a placeholder reporter path" \
  "templates/updater-cron.tmpl.sh" '/path/to/family-memory-architecture/scripts'
check_absent_many a30 "updater cron template drops the old HOME-based failure text" \
  "templates/updater-cron.tmpl.sh" 'HOME is not set; cannot derive default FMA_SCRIPTS_DIR'
check_absent_many a31 "updater cron template no longer derives the reporter path from HOME" \
  "templates/updater-cron.tmpl.sh" 'FMA_SCRIPTS_DIR=${FMA_SCRIPTS_DIR:-"$HOME/claude-workspace/family-memory-architecture/scripts"}'
check_contains a32 "installer wording uses generic remote-home phrasing" \
  "install.sh" 'remote home directory'
check_absent_many a33 "installer wording drops the person-specific remote-home wording" \
  "install.sh" "Claire's STATE.md"
check_contains a34 "probe note says it inspects configured adapter paths" \
  "install.sh" 'inspect configured'
check_contains a35 "probe note says it reads env-supplied external paths" \
  "install.sh" 'env-supplied external ones'
check_contains a36 "probe note says it does not mutate the checked workspace" \
  "install.sh" 'mutate the checked workspace'
check_absent_many a37 "probe note drops the old installer-local inspection wording" \
  "install.sh" 'implementation shipped beside this installer'
check_exact_blob a40 "wrapper-conformance library remains unchanged" \
  "scripts/lib-wrapper-conformance.sh" \
  'a4a51b6e8070c5516607c0081b0beef1e44ba8ce'
check_exact_blob a41 "wrapper-conformance test expectations remain unchanged" \
  "tests/wrapper-conformance.test.sh" \
  '530091f9034e7873647ac3fbf633f452dac2c994'

if [ "$fail" -ne 0 ]; then
  exit 1
fi
exit 0
