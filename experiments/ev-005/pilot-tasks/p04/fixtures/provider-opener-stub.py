#!/usr/bin/env python3
import json
import os
import runpy
import sys
import urllib.error
import urllib.request


class StubResponse:
    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def read(self):
        return json.dumps(
            {
                "content": [
                    {
                        "type": "text",
                        "text": "VERDICT: pass\nstub accepted the request URL",
                    }
                ]
            }
        ).encode("utf-8")


def write_marker(name: str, value: str) -> None:
    path = os.environ.get(name, "")
    if not path:
        return
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(value)


def record_request(request, count: int) -> None:
    write_marker("REQUEST_COUNT_MARKER", str(count))
    write_marker("REQUEST_URL_MARKER", request.full_url)
    write_marker("REQUEST_KEY_MARKER", request.get_header("X-api-key", ""))


class StubOpener:
    def __init__(self, redirect_handler):
        self.redirect_handler = redirect_handler

    def open(self, request, timeout):
        del timeout
        record_request(request, 1)
        if os.environ.get("STUB_RESPONSE_MODE") == "redirect":
            redirected = self.redirect_handler.redirect_request(
                request,
                None,
                302,
                "Found",
                {},
                "http://redirect.example.test/collect",
            )
            if redirected is not None:
                record_request(request, 2)
                return StubResponse()
            raise urllib.error.HTTPError(request.full_url, 302, "Found", {}, None)
        return StubResponse()


def stub_build_opener(*handlers):
    redirect_handlers = [
        handler
        for handler in handlers
        if isinstance(handler, urllib.request.HTTPRedirectHandler)
    ]
    if len(redirect_handlers) != 1:
        raise AssertionError("provider must install exactly one redirect handler")
    return StubOpener(redirect_handlers[0])


def stub_urlopen(request, timeout=0):
    del timeout
    if os.environ.get("STUB_RESPONSE_MODE") == "redirect":
        record_request(request, 2)
    else:
        record_request(request, 1)
    return StubResponse()


if len(sys.argv) != 3:
    raise SystemExit("usage: provider-opener-stub.py <provider-path> <bundle>")

provider_path, bundle = sys.argv[1:]
urllib.request.build_opener = stub_build_opener
urllib.request.urlopen = stub_urlopen
sys.argv = [provider_path, bundle]
runpy.run_path(provider_path, run_name="__main__")
