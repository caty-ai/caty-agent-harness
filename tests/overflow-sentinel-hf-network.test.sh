#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_BASE=$(cd "${TMPDIR:-/tmp}" && pwd -P)
TMP_ROOT=$TMP_BASE/caty-overflow-sentinel-hf-network.$$
trap 'rm -rf "$TMP_ROOT"' EXIT
mkdir -p "$TMP_ROOT"
passes=0
failures=0

pass() { printf 'ok - %s\n' "$1"; passes=$((passes + 1)); }
fail_case() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }

run_python_case() {
  local name=$1
  local body=$2
  if ROOT="$ROOT" TMP_ROOT="$TMP_ROOT" CASE_BODY="$body" python3 -B - <<'PY'
import contextlib
import io
import hashlib
import json
import os
import stat
import sys
import time
import urllib.error
from pathlib import Path

sys.path.insert(0, os.path.join(os.environ["ROOT"], "scripts"))
import lib_overflow_sentinel as lib
from lib_overflow_sentinel import *

exec(os.environ["CASE_BODY"], globals(), globals())
PY
  then
    pass "$name"
  else
    fail_case "$name"
  fi
}

run_python_case "network rung write-through returns hf-network-cached and reuses the hashed cache entry" '
root = Path(os.environ["TMP_ROOT"])
cache_dir = root / "cache-reuse"
calls = []

def fetcher(model_id):
    calls.append(model_id)
    return 131072

stderr = io.StringIO()
with contextlib.redirect_stderr(stderr):
    first = resolve_ctx_window(
        None,
        None,
        "org/model",
        hf_network=True,
        hf_cache_dir=str(cache_dir),
        hf_fetcher=fetcher,
    )
    second = resolve_ctx_window(
        None,
        None,
        "org/model",
        hf_network=True,
        hf_cache_dir=str(cache_dir),
        hf_fetcher=lambda _: (_ for _ in ()).throw(RuntimeError("should not refetch")),
    )

assert stderr.getvalue() == ""
assert first == (131072, "hf-network-cached")
assert second == (131072, "hf-network-cached")
assert calls == ["org/model"]
assert stat.S_IMODE(cache_dir.stat().st_mode) == 0o700
cache_entries = list(cache_dir.glob("*.json"))
assert len(cache_entries) == 1
expected_name = hashlib.sha256(b"org/model").hexdigest() + ".json"
assert cache_entries[0].name == expected_name
payload = json.loads(cache_entries[0].read_text(encoding="utf-8"))
assert payload["model_id"] == "org/model"
assert payload["max_position_embeddings"] == 131072
'

run_python_case "local HF config keeps precedence over the opt-in network rung" '
root = Path(os.environ["TMP_ROOT"])
cache_dir = root / "cache-local-wins"
local = root / "local-config.json"
local.write_text(json.dumps({"max_position_embeddings": 64000}), encoding="utf-8")

def fetcher(_):
    raise AssertionError("network rung should not run when local HF config is present")

assert resolve_ctx_window(
    None,
    str(local),
    "org/model",
    hf_network=True,
    hf_cache_dir=str(cache_dir),
    hf_fetcher=fetcher,
) == (64000, "hf-config")
'

run_python_case "network disabled or unset never creates cache and never calls fetcher" '
root = Path(os.environ["TMP_ROOT"])
cache_dir = root / "cache-disabled"
calls = []

def fetcher(_):
    calls.append("called")
    raise AssertionError("fetcher should not run when OVF network is disabled")

assert resolve_ctx_window(
    None,
    None,
    "claude-sonnet-4-5",
    hf_cache_dir=str(cache_dir),
    hf_fetcher=fetcher,
) == (200000, "catalog")
assert resolve_ctx_window(
    None,
    None,
    "claude-sonnet-4-5",
    hf_network=False,
    hf_cache_dir=str(cache_dir),
    hf_fetcher=fetcher,
) == (200000, "catalog")
assert calls == []
assert not cache_dir.exists()
'

run_python_case "network URL uses the exact resolve endpoint" '
assert lib._hf_network_url("org/model") == "https://huggingface.co/org/model/resolve/main/config.json"
assert lib._hf_network_url("org.with.dots/model_name") == "https://huggingface.co/org.with.dots/model_name/resolve/main/config.json"
'

run_python_case "invalid cache content plus fetch failure warns once per failure path and falls through" '
root = Path(os.environ["TMP_ROOT"])
cache_dir = root / "cache-fallback"
cache_dir.mkdir(parents=True)
cache_path = lib._hf_cache_file(cache_dir, "org/model")
cache_path.write_text("{not json}\n", encoding="utf-8")

stderr = io.StringIO()
with contextlib.redirect_stderr(stderr):
    result = resolve_ctx_window(
        None,
        None,
        "org/model",
        hf_network=True,
        hf_cache_dir=str(cache_dir),
        hf_fetcher=lambda _: (_ for _ in ()).throw(OSError("offline")),
    )

log = stderr.getvalue()
assert result == (200000, "default")
assert "cache entry is not readable JSON" in log
assert "offline" in log
'

run_python_case "HTTPError during fetch warns and falls through without creating cache" '
root = Path(os.environ["TMP_ROOT"])
cache_dir = root / "cache-http-error"
stderr = io.StringIO()

def fetcher(_):
    raise urllib.error.HTTPError(
        "https://huggingface.co/org/model/resolve/main/config.json",
        404,
        "not found",
        hdrs=None,
        fp=None,
    )

with contextlib.redirect_stderr(stderr):
    result = resolve_ctx_window(
        None,
        None,
        "org/model",
        hf_network=True,
        hf_cache_dir=str(cache_dir),
        hf_fetcher=fetcher,
    )

assert result == (200000, "default")
assert "HTTP Error 404: not found" in stderr.getvalue()
assert list(cache_dir.glob("*.json")) == []
'

run_python_case "fetched invalid JSON warns and falls through" '
root = Path(os.environ["TMP_ROOT"])
cache_dir = root / "cache-invalid-json"
stderr = io.StringIO()

class FakeResponse:
    def __init__(self, payload):
        self.payload = payload
    def read(self, _):
        return self.payload
    def __enter__(self):
        return self
    def __exit__(self, exc_type, exc, tb):
        return False

def fake_urlopen(request, timeout):
    assert timeout == lib.HF_NETWORK_TIMEOUT_S
    return FakeResponse(b"not json")

old_urlopen = lib.urllib.request.urlopen
lib.urllib.request.urlopen = fake_urlopen
try:
    with contextlib.redirect_stderr(stderr):
        result = resolve_ctx_window(
            None,
            None,
            "org/model",
            hf_network=True,
            hf_cache_dir=str(cache_dir),
        )
finally:
    lib.urllib.request.urlopen = old_urlopen

assert result == (200000, "default")
assert "Expecting value" in stderr.getvalue()
assert list(cache_dir.glob("*.json")) == []
'

run_python_case "fetched JSON without a supported window warns and falls through" '
root = Path(os.environ["TMP_ROOT"])
cache_dir = root / "cache-no-window"
stderr = io.StringIO()

class FakeResponse:
    def __init__(self, payload):
        self.payload = payload
    def read(self, _):
        return self.payload
    def __enter__(self):
        return self
    def __exit__(self, exc_type, exc, tb):
        return False

def fake_urlopen(request, timeout):
    assert timeout == lib.HF_NETWORK_TIMEOUT_S
    return FakeResponse(json.dumps({"architectures": ["TestModel"]}).encode("utf-8"))

old_urlopen = lib.urllib.request.urlopen
lib.urllib.request.urlopen = fake_urlopen
try:
    with contextlib.redirect_stderr(stderr):
        result = resolve_ctx_window(
            None,
            None,
            "org/model",
            hf_network=True,
            hf_cache_dir=str(cache_dir),
        )
finally:
    lib.urllib.request.urlopen = old_urlopen

assert result == (200000, "default")
assert "HF network config has no positive supported context-window field" in stderr.getvalue()
assert list(cache_dir.glob("*.json")) == []
'

run_python_case "invalid model ids and unsafe cache dirs warn and fall through without escaping" '
root = Path(os.environ["TMP_ROOT"])
target = root / "cache-target"
target.mkdir(parents=True)
symlink_dir = root / "cache-link"
if symlink_dir.exists() or symlink_dir.is_symlink():
    symlink_dir.unlink()
symlink_dir.symlink_to(target, target_is_directory=True)

stderr = io.StringIO()
with contextlib.redirect_stderr(stderr):
    invalid_id = resolve_ctx_window(None, None, "bad/id/extra", hf_network=True, hf_cache_dir=str(target))
    empty_cache = resolve_ctx_window(None, None, "org/model", hf_network=True, hf_cache_dir="")
    symlink_cache = resolve_ctx_window(None, None, "org/model", hf_network=True, hf_cache_dir=str(symlink_dir))

log = stderr.getvalue()
assert invalid_id == (200000, "default")
assert empty_cache == (200000, "default")
assert symlink_cache == (200000, "default")
assert "HF model id must be a plain repo id such as namespace/name" in log
assert "HF cache dir must be non-empty" in log
assert "HF cache dir must not be a symlink" in log
'

run_python_case "malicious HF ids are rejected before fetch" '
root = Path(os.environ["TMP_ROOT"])
cache_dir = root / "cache-malicious-id"
calls = []
stderr = io.StringIO()

def fetcher(_):
    calls.append("called")
    raise AssertionError("fetcher should not run for invalid model ids")

with contextlib.redirect_stderr(stderr):
    first = resolve_ctx_window(
        None,
        None,
        "../../x",
        hf_network=True,
        hf_cache_dir=str(cache_dir),
        hf_fetcher=fetcher,
    )
    second = resolve_ctx_window(
        None,
        None,
        "http://evil",
        hf_network=True,
        hf_cache_dir=str(cache_dir),
        hf_fetcher=fetcher,
    )

assert first == (200000, "default")
assert second == (200000, "default")
assert calls == []
log = stderr.getvalue()
assert log.count("HF model id must be a plain repo id such as namespace/name") == 2
'

run_python_case "cache dir mode drift is normalized back to 0700 before cached reuse" '
root = Path(os.environ["TMP_ROOT"])
cache_dir = root / "cache-mode"
cache_dir.mkdir(parents=True)
os.chmod(cache_dir, 0o755)
cache_path = lib._hf_cache_file(cache_dir, "org/model")
cache_path.write_text(json.dumps({
    "schema_version": lib.HF_CACHE_SCHEMA_VERSION,
    "model_id": "org/model",
    "fetched_at": 1,
    "max_position_embeddings": 131072,
}) + "\n", encoding="utf-8")

stderr = io.StringIO()
with contextlib.redirect_stderr(stderr):
    result = resolve_ctx_window(None, None, "org/model", hf_network=True, hf_cache_dir=str(cache_dir))

assert result == (131072, "hf-network-cached")
assert stderr.getvalue() == ""
assert stat.S_IMODE(cache_dir.stat().st_mode) == 0o700
'

run_python_case "hard fetch deadline returns promptly on a blocking fetcher" '
root = Path(os.environ["TMP_ROOT"])
cache_dir = root / "cache-timeout"
started = time.monotonic()
stderr = io.StringIO()

def fetcher(_):
    time.sleep(0.5)
    return 131072

with contextlib.redirect_stderr(stderr):
    result = resolve_ctx_window(
        None,
        None,
        "org/model",
        hf_network=True,
        hf_cache_dir=str(cache_dir),
        hf_fetcher=fetcher,
        hf_fetch_timeout_s=0.05,
    )

elapsed = time.monotonic() - started
assert result == (200000, "default")
assert elapsed < 0.3
assert "HF network fetch exceeded hard timeout" in stderr.getvalue()
'

prep_cache="$TMP_ROOT/prepared-cache"
prep_output=$(python3 -B "$ROOT/scripts/lib_overflow_sentinel.py" prepare-hf-cache "$prep_cache")
prep_mode=$(python3 -B - "$prep_cache" <<'PY'
import os
import stat
import sys
print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode)))
PY
)
if [[ "$prep_output" == "$prep_cache" ]] && [[ "$prep_mode" == "0o700" ]]; then
  pass "prepare-hf-cache creates and normalizes a private cache directory"
else
  fail_case "prepare-hf-cache creates and normalizes a private cache directory"
fi

set +e
python3 -B "$ROOT/scripts/lib_overflow_sentinel.py" prepare-hf-cache "" \
  >"$TMP_ROOT/prepare-empty.out" 2>"$TMP_ROOT/prepare-empty.err"
prepare_empty_rc=$?
set -e
if [[ "$prepare_empty_rc" -eq 2 ]] && grep -Fq 'HF cache dir must be non-empty' "$TMP_ROOT/prepare-empty.err"; then
  pass "prepare-hf-cache exits 2 on an empty cache dir"
else
  fail_case "prepare-hf-cache exits 2 on an empty cache dir"
fi

if (( failures )); then
  printf '%s overflow sentinel HF network test(s) failed; %s passed\n' "$failures" "$passes" >&2
  exit 1
fi
printf '%s overflow sentinel HF network tests passed\n' "$passes"
