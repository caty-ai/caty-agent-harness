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
import base64
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

REV = "0123456789abcdef0123456789abcdef01234567"
RAW = json.dumps({"max_position_embeddings": 131072}).encode()
PINS = {"org/model": {"revision": REV}}
os.environ.pop("OVF_HF_PINS", None)

def forbidden(*args):
    raise AssertionError("unexpected network/cache access")

# Any unexpected cache miss fails locally, never reaching the real network.
lib.urllib.request.urlopen = forbidden

def cache_entry():
    return {
        "schema_version": 2, "model_id": "org/model", "fetched_at": 1,
        "revision": REV, "payload_sha256": hashlib.sha256(RAW).hexdigest(),
        "payload_b64": base64.b64encode(RAW).decode("ascii"),
        "max_position_embeddings": 131072,
    }

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

def fetcher(model_id, revision):
    calls.append(model_id)
    return json.dumps({"max_position_embeddings": 131072}).encode()

stderr = io.StringIO()
with contextlib.redirect_stderr(stderr):
    first = resolve_ctx_window(
        None,
        None,
        "org/model",
        hf_network=True, hf_pins=PINS,
        hf_cache_dir=str(cache_dir),
        hf_fetcher=fetcher,
    )
    second = resolve_ctx_window(
        None,
        None,
        "org/model",
        hf_network=True, hf_pins=PINS,
        hf_cache_dir=str(cache_dir),
        hf_fetcher=lambda _, revision: (_ for _ in ()).throw(RuntimeError("should not refetch")),
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

def fetcher(_, revision):
    raise AssertionError("network rung should not run when local HF config is present")

assert resolve_ctx_window(
    None,
    str(local),
    "org/model",
    hf_network=True, hf_pins=PINS,
    hf_cache_dir=str(cache_dir),
    hf_fetcher=fetcher,
) == (64000, "hf-config")
'

run_python_case "network disabled or unset never creates cache and never calls fetcher" '
root = Path(os.environ["TMP_ROOT"])
cache_dir = root / "cache-disabled"
calls = []

def fetcher(_, revision):
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
assert lib._hf_network_url("org/model", REV) == f"https://huggingface.co/org/model/resolve/{REV}/config.json"
assert lib._hf_network_url("org.with.dots/model_name", REV) == f"https://huggingface.co/org.with.dots/model_name/resolve/{REV}/config.json"
assert lib._hf_network_url("org/model", None) == "https://huggingface.co/org/model/resolve/main/config.json"
from unittest import TestCase
with TestCase().assertRaisesRegex(ValueError, "HF revision must be a 40-hex commit SHA"):
    lib._hf_network_url("org/model", "main")
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
        hf_network=True, hf_pins=PINS,
        hf_cache_dir=str(cache_dir),
        hf_fetcher=lambda _, revision: (_ for _ in ()).throw(OSError("offline")),
    )

log = stderr.getvalue()
assert result == (200000, "default")
assert "cache entry is not readable JSON" in log
assert "offline" in log
'

run_python_case "cached entry at the exact size cap is accepted" '
root = Path(os.environ["TMP_ROOT"])
cache_dir = root / "cache-exact-cap"
cache_dir.mkdir(parents=True)
cache_path = lib._hf_cache_file(cache_dir, "org/model")
payload = {
    **cache_entry(),
    "schema_version": lib.HF_CACHE_SCHEMA_VERSION,
    "model_id": "org/model",
    "fetched_at": 1,
    "max_position_embeddings": 131072,
    "padding": "",
}
raw = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
payload["padding"] = "x" * (lib.HF_CACHE_MAX_BYTES - len(raw))
raw = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
assert len(raw) == lib.HF_CACHE_MAX_BYTES
cache_path.write_bytes(raw)

stderr = io.StringIO()
with contextlib.redirect_stderr(stderr):
    result = resolve_ctx_window(
        None,
        None,
        "org/model",
        hf_network=True, hf_pins=PINS,
        hf_cache_dir=str(cache_dir),
    )

assert result == (131072, "hf-network-cached")
assert stderr.getvalue() == ""
'

run_python_case "oversized cached entry warns and falls through" '
root = Path(os.environ["TMP_ROOT"])
cache_dir = root / "cache-oversize"
cache_dir.mkdir(parents=True)
cache_path = lib._hf_cache_file(cache_dir, "org/model")
cache_path.write_bytes(b"x" * (lib.HF_CACHE_MAX_BYTES + 1))

stderr = io.StringIO()
with contextlib.redirect_stderr(stderr):
    result = resolve_ctx_window(
        None,
        None,
        "org/model",
        hf_network=True, hf_pins=PINS,
        hf_cache_dir=str(cache_dir),
        hf_fetcher=lambda _, revision: (_ for _ in ()).throw(OSError("offline")),
    )

assert result == (200000, "default")
log = stderr.getvalue()
assert "cache entry exceeds size limit" in log
assert "offline" in log
'

run_python_case "HTTPError during fetch warns and falls through without creating cache" '
root = Path(os.environ["TMP_ROOT"])
cache_dir = root / "cache-http-error"
stderr = io.StringIO()

def fetcher(_, revision):
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
        hf_network=True, hf_pins=PINS,
        hf_cache_dir=str(cache_dir),
        hf_fetcher=fetcher,
    )

assert result == (200000, "default")
assert "HTTP Error 404: not found" in stderr.getvalue()
assert list(cache_dir.glob("*.json")) == []
'

run_python_case "oversized fetched payload warns and falls through" '
root = Path(os.environ["TMP_ROOT"])
cache_dir = root / "cache-fetch-oversize"
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
    return FakeResponse(b"x" * (lib.HF_NETWORK_MAX_BYTES + 1))

old_urlopen = lib.urllib.request.urlopen
lib.urllib.request.urlopen = fake_urlopen
try:
    with contextlib.redirect_stderr(stderr):
        result = resolve_ctx_window(
            None,
            None,
            "org/model",
            hf_network=True, hf_pins=PINS,
            hf_cache_dir=str(cache_dir),
        )
finally:
    lib.urllib.request.urlopen = old_urlopen

assert result == (200000, "default")
assert "HF network config exceeds size limit" in stderr.getvalue()
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
            hf_network=True, hf_pins=PINS,
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
            hf_network=True, hf_pins=PINS,
            hf_cache_dir=str(cache_dir),
        )
finally:
    lib.urllib.request.urlopen = old_urlopen

assert result == (200000, "default")
assert "HF network config has no positive supported context-window field" in stderr.getvalue()
assert list(cache_dir.glob("*.json")) == []
'

run_python_case "cache entry symlinks are rejected and fall through" '
root = Path(os.environ["TMP_ROOT"])
cache_dir = root / "cache-entry-symlink"
cache_dir.mkdir(parents=True)
os.chmod(cache_dir, 0o700)
target = root / "cache-entry-target.json"
target.write_text(json.dumps({
    **cache_entry(),
    "schema_version": lib.HF_CACHE_SCHEMA_VERSION,
    "model_id": "org/model",
    "fetched_at": 1,
    "max_position_embeddings": 131072,
}) + "\n", encoding="utf-8")
cache_path = lib._hf_cache_file(cache_dir, "org/model")
cache_path.symlink_to(target)

stderr = io.StringIO()
with contextlib.redirect_stderr(stderr):
    result = resolve_ctx_window(
        None,
        None,
        "org/model",
        hf_network=True, hf_pins=PINS,
        hf_cache_dir=str(cache_dir),
        hf_fetcher=lambda _, revision: (_ for _ in ()).throw(OSError("offline")),
    )

assert result == (200000, "default")
log = stderr.getvalue()
assert "cache entry must be a non-symlink regular file" in log
assert "offline" in log
'

run_python_case "cached model mismatches warn and fall through" '
root = Path(os.environ["TMP_ROOT"])
cache_dir = root / "cache-model-mismatch"
cache_dir.mkdir(parents=True)
cache_path = lib._hf_cache_file(cache_dir, "org/model")
cache_path.write_text(json.dumps({
    **cache_entry(),
    "schema_version": lib.HF_CACHE_SCHEMA_VERSION,
    "model_id": "other/model",
    "fetched_at": 1,
    "max_position_embeddings": 131072,
}) + "\n", encoding="utf-8")

stderr = io.StringIO()
with contextlib.redirect_stderr(stderr):
    result = resolve_ctx_window(
        None,
        None,
        "org/model",
        hf_network=True, hf_pins=PINS,
        hf_cache_dir=str(cache_dir),
        hf_fetcher=lambda _, revision: (_ for _ in ()).throw(OSError("offline")),
    )

assert result == (200000, "default")
log = stderr.getvalue()
assert "cache entry model mismatch" in log
assert "offline" in log
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
    invalid_id = resolve_ctx_window(None, None, "bad/id/extra", hf_network=True, hf_pins=PINS, hf_cache_dir=str(target))
    empty_cache = resolve_ctx_window(None, None, "org/model", hf_network=True, hf_pins=PINS, hf_cache_dir="")
    symlink_cache = resolve_ctx_window(None, None, "org/model", hf_network=True, hf_pins=PINS, hf_cache_dir=str(symlink_dir))

log = stderr.getvalue()
assert invalid_id == (200000, "default")
assert empty_cache == (200000, "default")
assert symlink_cache == (200000, "default")
assert "HF model id must be a plain repo id such as namespace/name" in log
assert "HF cache dir must be non-empty" in log
assert "HF cache dir must not be a symlink" in log
'

run_python_case "symlinked ancestors are accepted for cache prep and network reuse" '
root = Path(os.environ["TMP_ROOT"])
real_parent = root / "real-parent"
real_parent.mkdir(parents=True)
linked_parent = root / "linked-parent"
linked_parent.symlink_to(real_parent, target_is_directory=True)
cache_dir = linked_parent / "nested" / "cache"
calls = []

def fetcher(model_id, revision):
    calls.append(model_id)
    return json.dumps({"max_position_embeddings": 131072}).encode()

prepared = lib.prepare_hf_cache_dir(str(cache_dir))
stderr = io.StringIO()
with contextlib.redirect_stderr(stderr):
    first = resolve_ctx_window(
        None,
        None,
        "org/model",
        hf_network=True, hf_pins=PINS,
        hf_cache_dir=str(cache_dir),
        hf_fetcher=fetcher,
    )
    second = resolve_ctx_window(
        None,
        None,
        "org/model",
        hf_network=True, hf_pins=PINS,
        hf_cache_dir=str(cache_dir),
        hf_fetcher=lambda _, revision: (_ for _ in ()).throw(RuntimeError("should not refetch")),
    )

assert prepared == cache_dir
assert first == (131072, "hf-network-cached")
assert second == (131072, "hf-network-cached")
assert stderr.getvalue() == ""
assert calls == ["org/model"]
assert cache_dir.is_dir()
assert stat.S_IMODE(cache_dir.stat().st_mode) == 0o700
'

run_python_case "malicious HF ids are rejected before fetch" '
root = Path(os.environ["TMP_ROOT"])
cache_dir = root / "cache-malicious-id"
calls = []
stderr = io.StringIO()

def fetcher(_, revision):
    calls.append("called")
    raise AssertionError("fetcher should not run for invalid model ids")

with contextlib.redirect_stderr(stderr):
    first = resolve_ctx_window(
        None,
        None,
        "../../x",
        hf_network=True, hf_pins=PINS,
        hf_cache_dir=str(cache_dir),
        hf_fetcher=fetcher,
    )
    second = resolve_ctx_window(
        None,
        None,
        "http://evil",
        hf_network=True, hf_pins=PINS,
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
    **cache_entry(),
    "schema_version": lib.HF_CACHE_SCHEMA_VERSION,
    "model_id": "org/model",
    "fetched_at": 1,
    "max_position_embeddings": 131072,
}) + "\n", encoding="utf-8")

stderr = io.StringIO()
with contextlib.redirect_stderr(stderr):
    result = resolve_ctx_window(None, None, "org/model", hf_network=True, hf_pins=PINS, hf_cache_dir=str(cache_dir))

assert result == (131072, "hf-network-cached")
assert stderr.getvalue() == ""
assert stat.S_IMODE(cache_dir.stat().st_mode) == 0o700
'

run_python_case "hard fetch deadline returns promptly on a blocking fetcher" '
root = Path(os.environ["TMP_ROOT"])
cache_dir = root / "cache-timeout"
started = time.monotonic()
stderr = io.StringIO()

def fetcher(_, revision):
    time.sleep(0.5)
    return json.dumps({"max_position_embeddings": 131072}).encode()

with contextlib.redirect_stderr(stderr):
    result = resolve_ctx_window(
        None,
        None,
        "org/model",
        hf_network=True, hf_pins=PINS,
        hf_cache_dir=str(cache_dir),
        hf_fetcher=fetcher,
        hf_fetch_timeout_s=0.05,
    )

elapsed = time.monotonic() - started
assert result == (200000, "default")
assert elapsed < 0.3
assert "HF network fetch exceeded hard timeout" in stderr.getvalue()
'

run_python_case "revision pin match binds URL fetcher and v2 cache payload" '
from types import MappingProxyType
class PinDict(dict):
    pass
cache_dir = Path(os.environ["TMP_ROOT"]) / "revision-pin"
calls = []
def fetcher(model_id, revision):
    calls.append((model_id, revision))
    return RAW
for pins in (MappingProxyType({"org/model": PinDict(revision=REV)}),
             {"org/model": MappingProxyType({"revision": REV})}):
    assert resolve_ctx_window(None, None, " org/model ", hf_network=True, hf_pins=pins,
        hf_cache_dir=str(cache_dir), hf_fetcher=fetcher) == (131072, "hf-network-cached")
assert calls == [("org/model", REV)]
assert lib._hf_network_url("org/model", REV) == f"https://huggingface.co/org/model/resolve/{REV}/config.json"
entry = json.loads(lib._hf_cache_file(cache_dir, "org/model").read_text())
assert entry["revision"] == REV and entry["schema_version"] == 2
assert entry["payload_sha256"] == hashlib.sha256(RAW).hexdigest()
assert base64.b64decode(entry["payload_b64"]) == RAW
# The human-readable field cannot override the verified payload.
entry["max_position_embeddings"] = 7
lib.atomic_write_private_json(lib._hf_cache_file(cache_dir, "org/model"), entry)
assert lib._read_hf_network_cache(lib._hf_cache_file(cache_dir, "org/model"), "org/model", PINS["org/model"]) == 131072
'

run_python_case "sha256 pin match accepts raw bytes at resolve main" '
cache_dir = Path(os.environ["TMP_ROOT"]) / "sha-pin"
pins = {"org/model": {"sha256": hashlib.sha256(RAW).hexdigest()}}
calls = []
def fetcher(model_id, revision):
    calls.append((model_id, revision))
    return RAW
assert resolve_ctx_window(None, None, "org/model", hf_network=True, hf_pins=pins,
    hf_cache_dir=str(cache_dir), hf_fetcher=fetcher) == (131072, "hf-network-cached")
assert calls == [("org/model", None)]
assert lib._hf_network_url("org/model", None) == "https://huggingface.co/org/model/resolve/main/config.json"
assert json.loads(lib._hf_cache_file(cache_dir, "org/model").read_text())["revision"] is None
'

run_python_case "sha256 pin mismatch warns with model id and never caches" '
cache_dir = Path(os.environ["TMP_ROOT"]) / "sha-mismatch"
stderr = io.StringIO()
with contextlib.redirect_stderr(stderr):
    result = resolve_ctx_window(None, None, "org/model", hf_network=True,
        hf_pins={"org/model": {"sha256": "0" * 64}}, hf_cache_dir=str(cache_dir),
        hf_fetcher=lambda model, revision: RAW)
assert result == (200000, "default")
assert "checksum mismatch for org/model" in stderr.getvalue()
assert list(cache_dir.iterdir()) == []
'

run_python_case "unpinned explicit table refuses fetch and cache access" '
cache_dir = Path(os.environ["TMP_ROOT"]) / "unpinned-explicit"
lib._read_hf_network_cache = forbidden
stderr = io.StringIO()
with contextlib.redirect_stderr(stderr):
    result = resolve_ctx_window(None, None, "Org/Model", hf_network=True, hf_pins={},
        hf_cache_dir=str(cache_dir), hf_fetcher=forbidden)
assert result == (200000, "default")
assert all(fragment in stderr.getvalue() for fragment in ("unpinned", "OVF_HF_PINS", "Org/Model"))
assert not cache_dir.exists()
'

run_python_case "unpinned unset environment refuses fetch and cache access" '
cache_dir = Path(os.environ["TMP_ROOT"]) / "unpinned-env"
lib._read_hf_network_cache = forbidden
stderr = io.StringIO()
with contextlib.redirect_stderr(stderr):
    result = resolve_ctx_window(None, None, "org/model", hf_network=True,
        hf_cache_dir=str(cache_dir), hf_fetcher=forbidden)
assert result == (200000, "default")
assert all(fragment in stderr.getvalue() for fragment in ("unpinned", "OVF_HF_PINS", "org/model"))
assert not cache_dir.exists()
'

run_python_case "invalid pin tables reject parsing and disable the environment rung" '
cases = [
    ("{", "valid JSON"),
    ("[]", "JSON object"),
    (json.dumps({"org/model": {"revision": "z" * 40}}), "org/model: revision"),
    (json.dumps({"org/model": {"sha256": "f" * 63}}), "org/model: sha256"),
    (json.dumps({"org/model": {"unknown": REV}}), "org/model: unknown field unknown"),
    (json.dumps({"org/model": {}}), "org/model: at least one revision or sha256"),
    (json.dumps({"org/model": []}), "org/model: revision/sha256 fields"),
    ("{\"org/model\":{\"revision\":\"" + REV + "\"},\" org/model \":{\"revision\":\"" + REV + "\"}}", "org/model: duplicate model id"),
    ("{\"org/model\":{\"revision\":\"" + REV + "\",\"revision\":\"" + REV + "\"}}", "org/model: duplicate field revision"),
    (json.dumps({"bad/id/extra": {"revision": REV}}), "bad/id/extra"),
    (json.dumps({"org/model": {"revision": 123}}), "org/model: revision"),
]
cache_dir = Path(os.environ["TMP_ROOT"]) / "invalid-pins"
for raw, fragment in cases:
    try:
        parse_hf_pins(raw)
    except ValueError as exc:
        assert fragment in str(exc), (fragment, str(exc))
    else:
        raise AssertionError(raw)
    os.environ["OVF_HF_PINS"] = raw
    stderr = io.StringIO()
    try:
        with contextlib.redirect_stderr(stderr):
            result = resolve_ctx_window(None, None, "org/model", hf_network=True,
                hf_cache_dir=str(cache_dir), hf_fetcher=forbidden)
    finally:
        os.environ.pop("OVF_HF_PINS", None)
    assert result == (200000, "default")
    assert "OVF_HF_PINS rejected" in stderr.getvalue() and fragment in stderr.getvalue()
assert not cache_dir.exists()
'

run_python_case "injected pin tables with non-string keys or non-mapping values are rejected" '
cache_dir = Path(os.environ["TMP_ROOT"]) / "invalid-injected-pins"
calls = []
def must_not_be_called(*args):
    calls.append(args)
    raise AssertionError("unexpected fetch or cache access")
lib.prepare_hf_cache_dir = must_not_be_called
lib._read_hf_network_cache = must_not_be_called
for pins in (
    {123: {"revision": REV}},
    {"org/model": "abc"},
    {123: {"revision": REV}, "org/model": {"revision": REV}},
    {"org/model": [("revision", REV)]},
    {"org/model": {123: REV}},
    {"org/model": {"revision": 123}},
):
    stderr = io.StringIO()
    with contextlib.redirect_stderr(stderr):
        result = resolve_ctx_window(None, None, "org/model", hf_network=True,
            hf_cache_dir=str(cache_dir), hf_fetcher=must_not_be_called, hf_pins=pins)
    assert result[1] in ("default", "catalog"), result
    assert "OVF_HF_PINS rejected" in stderr.getvalue(), stderr.getvalue()
    assert calls == [], calls
    assert not cache_dir.exists()
'

run_python_case "pin parser preserves model case normalizes hex and accepts empty surface" '
assert parse_hf_pins(None) == parse_hf_pins("") == parse_hf_pins("  ") == {}
table = parse_hf_pins(json.dumps({" Org/Model ": {"revision": REV.upper()},
    "org/model": {"sha256": "A" * 64}}))
assert table == {"Org/Model": {"revision": REV}, "org/model": {"sha256": "a" * 64}}
'

run_python_case "stale cache revision is rejected refetched and overwritten" '
cache_dir = Path(os.environ["TMP_ROOT"]) / "stale-revision"
calls = []
def fetcher(model_id, revision):
    calls.append(revision)
    return RAW
for revision in (REV, "b" * 40, None, REV):
    pin = {"sha256": hashlib.sha256(RAW).hexdigest()}
    if revision is not None:
        pin["revision"] = revision
    stderr = io.StringIO()
    with contextlib.redirect_stderr(stderr):
        assert resolve_ctx_window(None, None, "org/model", hf_network=True,
            hf_pins={"org/model": pin}, hf_cache_dir=str(cache_dir),
            hf_fetcher=fetcher) == (131072, "hf-network-cached")
    if len(calls) > 1:
        assert "cache entry revision mismatch" in stderr.getvalue()
    assert json.loads(lib._hf_cache_file(cache_dir, "org/model").read_text())["revision"] == revision
assert calls == [REV, "b" * 40, None, REV]
'

run_python_case "altered cache payload with old digest is rejected and refetched" '
cache_dir = Path(os.environ["TMP_ROOT"]) / "altered-payload"
assert resolve_ctx_window(None, None, "org/model", hf_network=True, hf_pins=PINS,
    hf_cache_dir=str(cache_dir), hf_fetcher=lambda model, revision: RAW) == (131072, "hf-network-cached")
path = lib._hf_cache_file(cache_dir, "org/model")
entry = json.loads(path.read_text())
entry["payload_b64"] = base64.b64encode(b"{\"max_position_embeddings\": 999999}").decode("ascii")
lib.atomic_write_private_json(path, entry)
calls = []
def fetcher(model, revision):
    calls.append(model)
    return RAW
stderr = io.StringIO()
with contextlib.redirect_stderr(stderr):
    assert resolve_ctx_window(None, None, "org/model", hf_network=True, hf_pins=PINS,
        hf_cache_dir=str(cache_dir), hf_fetcher=fetcher) == (131072, "hf-network-cached")
assert calls == ["org/model"]
assert "cache entry checksum mismatch" in stderr.getvalue()
assert base64.b64decode(json.loads(path.read_text())["payload_b64"]) == RAW
'

run_python_case "altered cache payload with fixed digest still fails the sha256 pin" '
cache_dir = Path(os.environ["TMP_ROOT"]) / "altered-digest"
pins = {"org/model": {"revision": REV, "sha256": hashlib.sha256(RAW).hexdigest()}}
assert resolve_ctx_window(None, None, "org/model", hf_network=True, hf_pins=pins,
    hf_cache_dir=str(cache_dir), hf_fetcher=lambda model, revision: RAW) == (131072, "hf-network-cached")
path = lib._hf_cache_file(cache_dir, "org/model")
entry = json.loads(path.read_text())
altered = b"{\"max_position_embeddings\": 999999}"
entry["payload_b64"] = base64.b64encode(altered).decode("ascii")
entry["payload_sha256"] = hashlib.sha256(altered).hexdigest()
lib.atomic_write_private_json(path, entry)
calls = []
def fetcher(model, revision):
    calls.append(model)
    return RAW
stderr = io.StringIO()
with contextlib.redirect_stderr(stderr):
    assert resolve_ctx_window(None, None, "org/model", hf_network=True, hf_pins=pins,
        hf_cache_dir=str(cache_dir), hf_fetcher=fetcher) == (131072, "hf-network-cached")
assert calls == ["org/model"]
assert "cache entry checksum does not match OVF_HF_PINS" in stderr.getvalue()
assert base64.b64decode(json.loads(path.read_text())["payload_b64"]) == RAW
'

run_python_case "schema v1 cache is rejected and refetched as v2" '
cache_dir = lib.prepare_hf_cache_dir(str(Path(os.environ["TMP_ROOT"]) / "schema-v1"))
path = lib._hf_cache_file(cache_dir, "org/model")
lib.atomic_write_private_json(path, {"schema_version": 1, "model_id": "org/model", "max_position_embeddings": 7})
calls = []
def fetcher(model, revision):
    calls.append(model)
    return RAW
stderr = io.StringIO()
with contextlib.redirect_stderr(stderr):
    assert resolve_ctx_window(None, None, "org/model", hf_network=True, hf_pins=PINS,
        hf_cache_dir=str(cache_dir), hf_fetcher=fetcher) == (131072, "hf-network-cached")
assert calls == ["org/model"]
assert "cache entry schema mismatch" in stderr.getvalue()
assert json.loads(path.read_text())["schema_version"] == 2
'

run_python_case "environment pins are used when no explicit table is supplied" '
cache_dir = Path(os.environ["TMP_ROOT"]) / "env-pins"
os.environ["OVF_HF_PINS"] = json.dumps(PINS)
calls = []
def fetcher(model, revision):
    calls.append((model, revision))
    return RAW
try:
    assert resolve_ctx_window(None, None, "org/model", hf_network=True,
        hf_cache_dir=str(cache_dir), hf_fetcher=fetcher) == (131072, "hf-network-cached")
finally:
    os.environ.pop("OVF_HF_PINS", None)
assert calls == [("org/model", REV)]
'

run_python_case "unreadable cached base64 is rejected and refetched" '
cache_dir = lib.prepare_hf_cache_dir(str(Path(os.environ["TMP_ROOT"]) / "bad-base64"))
path = lib._hf_cache_file(cache_dir, "org/model")
for bad in ("!", None, 42):
    entry = cache_entry()
    entry["payload_b64"] = bad
    lib.atomic_write_private_json(path, entry)
    stderr = io.StringIO()
    with contextlib.redirect_stderr(stderr):
        assert resolve_ctx_window(None, None, "org/model", hf_network=True, hf_pins=PINS,
            hf_cache_dir=str(cache_dir), hf_fetcher=lambda model, revision: RAW) == (131072, "hf-network-cached")
    assert "cache entry payload unreadable" in stderr.getvalue()
'

run_python_case "maximum network payload fits the larger v2 cache cap" '
cache_dir = Path(os.environ["TMP_ROOT"]) / "max-payload"
raw = RAW + b" " * (HF_NETWORK_MAX_BYTES - len(RAW))
assert resolve_ctx_window(None, None, "org/model", hf_network=True, hf_pins=PINS,
    hf_cache_dir=str(cache_dir), hf_fetcher=lambda model, revision: raw) == (131072, "hf-network-cached")
assert HF_NETWORK_MAX_BYTES < lib._hf_cache_file(cache_dir, "org/model").stat().st_size <= HF_CACHE_MAX_BYTES
'

run_python_case "non UTF-8 network payload is rejected without caching" '
cache_dir = Path(os.environ["TMP_ROOT"]) / "invalid-utf8"
stderr = io.StringIO()
with contextlib.redirect_stderr(stderr):
    assert resolve_ctx_window(None, None, "org/model", hf_network=True, hf_pins=PINS,
        hf_cache_dir=str(cache_dir), hf_fetcher=lambda model, revision: b"\xff") == (200000, "default")
assert "utf-8" in stderr.getvalue()
assert list(cache_dir.iterdir()) == []
'

run_python_case "urllib fetch uses pinned revision headers timeout and bounded raw read" '
calls = []
class Response:
    def __enter__(self):
        return self
    def __exit__(self, *args):
        return False
    def read(self, size):
        assert size == HF_NETWORK_MAX_BYTES + 1
        return RAW

def urlopen(request, timeout):
    calls.append(request.full_url)
    assert request.get_header("Accept") == "application/json"
    assert request.get_header("User-agent") == "caty-overflow-sentinel/1"
    assert timeout == HF_NETWORK_TIMEOUT_S
    return Response()
lib.urllib.request.urlopen = urlopen
cache_dir = Path(os.environ["TMP_ROOT"]) / "urllib-pin"
assert resolve_ctx_window(None, None, "org/model", hf_network=True, hf_pins=PINS,
    hf_cache_dir=str(cache_dir)) == (131072, "hf-network-cached")
assert calls == [f"https://huggingface.co/org/model/resolve/{REV}/config.json"]
'

pins_output=$(python3 -B "$ROOT/scripts/lib_overflow_sentinel.py" validate-hf-pins '{"org/model":{"revision":"0123456789abcdef0123456789abcdef01234567"}}')
pins_sorted=$(python3 -B "$ROOT/scripts/lib_overflow_sentinel.py" validate-hf-pins '{"z/model":{"sha256":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","revision":"0123456789abcdef0123456789abcdef01234567"},"a/model":{"revision":"0123456789abcdef0123456789abcdef01234567"}}')
if [[ "$pins_output" == '{"org/model": {"revision": "0123456789abcdef0123456789abcdef01234567"}}' ]] &&
   [[ "$pins_sorted" == '{"a/model": {"revision": "0123456789abcdef0123456789abcdef01234567"}, "z/model": {"revision": "0123456789abcdef0123456789abcdef01234567", "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}' ]]; then
  pass "validate-hf-pins exits 0 and prints sorted JSON"
else
  fail_case "validate-hf-pins exits 0 and prints sorted JSON"
fi
set +e
python3 -B "$ROOT/scripts/lib_overflow_sentinel.py" validate-hf-pins '{"org/model":{}}' \
  >"$TMP_ROOT/pins-invalid.out" 2>"$TMP_ROOT/pins-invalid.err"
pins_invalid_rc=$?
set -e
if [[ "$pins_invalid_rc" -eq 2 ]] && [[ ! -s "$TMP_ROOT/pins-invalid.out" ]] && grep -Fq 'org/model: at least one revision or sha256 field is required' "$TMP_ROOT/pins-invalid.err"; then
  pass "validate-hf-pins exits 2 with a model-specific validation error"
else
  fail_case "validate-hf-pins exits 2 with a model-specific validation error"
fi

prep_real_parent="$TMP_ROOT/prepare-real-parent"
prep_link_parent="$TMP_ROOT/prepare-link-parent"
mkdir -p "$prep_real_parent"
ln -s "$prep_real_parent" "$prep_link_parent"
prep_cache="$prep_link_parent/prepared-cache"
prep_output=$(python3 -B "$ROOT/scripts/lib_overflow_sentinel.py" prepare-hf-cache "$prep_cache")
prep_mode=$(python3 -B - "$prep_cache" <<'PY'
import os
import stat
import sys
print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode)))
PY
)
if [[ "$prep_output" == "$prep_cache" ]] && [[ "$prep_mode" == "0o700" ]]; then
  pass "prepare-hf-cache accepts symlinked ancestors and normalizes a private cache directory"
else
  fail_case "prepare-hf-cache accepts symlinked ancestors and normalizes a private cache directory"
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
