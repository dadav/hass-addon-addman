#!/usr/bin/env python3
"""Minimal mock of the Home Assistant Supervisor REST API.

Used by tests/smoke_test.sh to exercise addman.sh end-to-end without a real
Supervisor. Every request is appended as a single JSON line to MOCK_LOG so the
smoke test can assert on the exact reconciliation calls AddMan made.

Responses use the Supervisor envelope `{"result": "ok", "data": ...}` that
bashio expects (see /usr/lib/bashio/api.sh). A catch-all returns an empty-ok
envelope so the mock tolerates any endpoint bashio happens to call; the
path-specific responses below drive the reconcile path:

  - bashio::config reads GET /addons/self/options/config -> add-on's own options
  - GET /store/repositories -> [] so the configured repo looks new (-> add)
  - GET /addons/<slug>/info with version=null -> add-on not installed (-> install)
    and state="stopped" (-> start), options={} (-> options differ, get set)
  - POST .../options/validate -> valid so AddMan applies options

Stdlib only. Configured via env: MOCK_HOST, MOCK_PORT, MOCK_LOG.
"""

import json
import os
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MOCK_HOST = os.environ.get("MOCK_HOST", "127.0.0.1")
MOCK_PORT = int(os.environ.get("MOCK_PORT", "8099"))
MOCK_LOG = os.environ.get("MOCK_LOG", "/tmp/mock_supervisor.log")

# AddMan's own options, returned for GET /addons/self/options/config. Short
# check_interval keeps the reconcile loop quick.
SELF_CONFIG = {
    "check_interval": 5,
    "check_updates_x_iterations": 0,
    "config_file": "/config/addman.yaml",
    "log_level": "info",
    "watch_config_changes": False,
}

# Per-add-on info. version=null => not installed; state=stopped => needs start;
# empty options => every configured option differs and gets applied.
ADDON_INFO = {
    "state": "stopped",
    "options": {},
    "version": None,
    "version_latest": "1",
    "boot": "manual",
    "watchdog": False,
    "auto_update": False,
    "ingress_panel": False,
}


def _ok(data):
    return {"result": "ok", "data": data}


def response_for(method, path):
    """Return the response body for a request. Most specific patterns first."""
    if method == "GET" and path == "/addons/self/options/config":
        return _ok(SELF_CONFIG)

    if method == "POST" and re.search(r"/addons/[^/]+/options/validate$", path):
        return _ok({"valid": True, "message": ""})

    if method == "GET" and path == "/store/repositories":
        return _ok([])

    if method == "GET" and re.search(r"/addons/[^/]+/info$", path):
        return _ok(ADDON_INFO)

    # Everything else (install, options, boot/watchdog/auto_update via options,
    # start, restart, /addons/reload, ...) just succeeds.
    return _ok({})


class Handler(BaseHTTPRequestHandler):
    def _record(self, method):
        length = int(self.headers.get("Content-Length", 0) or 0)
        body = self.rfile.read(length).decode("utf-8") if length else ""
        with open(MOCK_LOG, "a", encoding="utf-8") as fh:
            fh.write(
                json.dumps({"method": method, "path": self.path, "body": body}) + "\n"
            )

    def _reply(self, method):
        self._record(method)
        payload = json.dumps(response_for(method, self.path)).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        self._reply("GET")

    def do_POST(self):
        self._reply("POST")

    def do_DELETE(self):
        self._reply("DELETE")

    # Silence default stderr request logging; MOCK_LOG is the record we use.
    def log_message(self, *args):
        pass


def main():
    open(MOCK_LOG, "w", encoding="utf-8").close()  # truncate: clean run
    server = ThreadingHTTPServer((MOCK_HOST, MOCK_PORT), Handler)
    print(f"mock_supervisor listening on {MOCK_HOST}:{MOCK_PORT}, log={MOCK_LOG}")
    server.serve_forever()


if __name__ == "__main__":
    main()
