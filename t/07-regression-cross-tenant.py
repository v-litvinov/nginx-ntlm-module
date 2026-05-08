#!/usr/bin/env python3
"""
Regression test: cross-tenant cache leak from ngx_connection_t pointer reuse.

Reproduces the bug fixed in commit b3bf03e.  MUST FAIL on pre-fix code,
PASS on post-fix code.

Bug chain (3 clients, 1-second ntlm_timeout):

  1. Alice  — NTLM request, upstream cached, cleanup registered on
     Alice's pool pointing to cache item1.
  2. Wait for ntlm_timeout — upstream closed, item1 returned to free
     queue.  Pre-fix: client_connection pointer NOT cleared.
  3. Carol  — NTLM request, free_peer reuses item1 for Carol.  Alice's
     pool cleanup still points to item1 (now Carol's).
  4. Alice  — second request on same TCP (keepalive).  Cache miss → new
     upstream cached as item2.  Pre-fix: cleanup-dedup finds the stale
     one and skips registration → item2 has no protector.
  5. Alice disconnects — pool cleanup fires on item1 (Carol's!) →
     closes Carol's upstream peerZ.  item2 untouched.
  6. Carol  — second request on same TCP.
     Pre-fix:  cache miss (peerZ killed) → *new* upstream socket.
     Post-fix: cache hit  (peerZ alive) → *same* upstream socket.

Assertion: Carol's upstream socket ID must not change.

Prerequisites:
  - nginx with this module on PATH or TEST_NGINX_BINARY env var
  - node >= 14
  - Python 3.7+

Usage:
    python3 t/07-regression-cross-tenant.py
"""

import http.client
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time

BACKEND_PORT = 18080
NGINX_PORT = 18081
NTLM_TIMEOUT_S = 1


def log(msg):
    print(msg, flush=True)


def fail(msg):
    log(f"FAIL: {msg}")
    sys.exit(1)


def wait_for_port(port, timeout=5):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.5):
                return
        except (ConnectionRefusedError, OSError):
            time.sleep(0.1)
    raise RuntimeError(f"port {port} not listening after {timeout}s")


def proxy_request(port, path, auth=None):
    """Open a keepalive connection, send one GET, return (conn, json_body)."""
    c = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    headers = {"Authorization": auth} if auth else {}
    c.request("GET", path, headers=headers)
    body = json.loads(c.getresponse().read())
    return c, body


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    tmpdir = tempfile.mkdtemp(prefix="ntlm-regress-")
    nginx_bin = os.environ.get("TEST_NGINX_BINARY", "nginx")

    if not shutil.which(nginx_bin) and not os.path.isfile(nginx_bin):
        sys.exit(f"ERROR: nginx not found ({nginx_bin})")
    if not shutil.which("node"):
        sys.exit("ERROR: node not found on PATH")

    # ── Start mock backend ──────────────────────────────────────────
    backend = subprocess.Popen(
        ["node", os.path.join(here, "backend", "server.js")],
        env={**os.environ, "PORT": str(BACKEND_PORT)},
        stderr=subprocess.DEVNULL,
    )
    try:
        wait_for_port(BACKEND_PORT)

        # Reset audit state
        c = http.client.HTTPConnection("127.0.0.1", BACKEND_PORT, timeout=3)
        c.request("GET", "/_reset")
        assert c.getresponse().status == 204
        c.close()

        # ── Write nginx config ──────────────────────────────────────
        conf = (
            f"worker_processes 1;\n"
            f"error_log {tmpdir}/error.log info;\n"
            f"pid {tmpdir}/nginx.pid;\n"
            f"events {{ worker_connections 64; }}\n"
            f"http {{\n"
            f"  access_log off;\n"
            f"  client_body_temp_path {tmpdir};\n"
            f"  proxy_temp_path {tmpdir};\n"
            f"  fastcgi_temp_path {tmpdir};\n"
            f"  uwsgi_temp_path {tmpdir};\n"
            f"  scgi_temp_path {tmpdir};\n"
            f"  upstream ntlm_backend {{\n"
            f"    server 127.0.0.1:{BACKEND_PORT};\n"
            f"    ntlm 4;\n"
            f"    ntlm_timeout {NTLM_TIMEOUT_S}s;\n"
            f"  }}\n"
            f"  server {{\n"
            f"    listen 127.0.0.1:{NGINX_PORT};\n"
            f"    location / {{\n"
            f"      proxy_pass http://ntlm_backend;\n"
            f"      proxy_http_version 1.1;\n"
            f"      proxy_set_header Connection \"\";\n"
            f"    }}\n"
            f"  }}\n"
            f"}}\n"
        )
        conf_path = os.path.join(tmpdir, "nginx.conf")
        with open(conf_path, "w") as f:
            f.write(conf)

        # ── Start nginx ─────────────────────────────────────────────
        nginx_log = os.path.join(tmpdir, "stderr.log")
        nginx = subprocess.Popen(
            [nginx_bin, "-c", conf_path],
            stderr=open(nginx_log, "w"),
        )
        try:
            try:
                wait_for_port(NGINX_PORT)
            except RuntimeError:
                # nginx likely failed to start; show why
                if os.path.exists(nginx_log):
                    log(f"--- nginx stderr ---")
                    with open(nginx_log) as f:
                        log(f.read())
                err_log = os.path.join(tmpdir, "error.log")
                if os.path.exists(err_log):
                    log(f"--- {err_log} ---")
                    with open(err_log) as f:
                        log(f.read())
                raise

            # ── Step 1: Alice connects, NTLM auth ───────────────────
            alice, d1 = proxy_request(NGINX_PORT, "/", auth="NTLM alice")
            log(f"[1] Alice  -> socket {d1['socket']}")

            # ── Step 2: wait for ntlm_timeout ────────────────────────
            time.sleep(NTLM_TIMEOUT_S + 0.5)
            log(f"[2] waited {NTLM_TIMEOUT_S + 0.5}s (ntlm_timeout)")

            # ── Step 3: Carol connects, NTLM auth ────────────────────
            carol, d3 = proxy_request(NGINX_PORT, "/", auth="NTLM carol")
            carol_sock = d3["socket"]
            log(f"[3] Carol  -> socket {carol_sock}")

            # ── Step 4: Alice reuses her keepalive connection ────────
            alice.request("GET", "/", headers={"Authorization": "NTLM alice"})
            d4 = json.loads(alice.getresponse().read())
            log(f"[4] Alice  -> socket {d4['socket']}")

            # ── Step 5: Alice disconnects ─────────────────────────────
            alice.close()
            time.sleep(0.3)
            log("[5] Alice disconnected")

            # ── Step 6: Carol reuses her keepalive connection ────────
            carol.request("GET", "/", headers={"Authorization": "NTLM carol"})
            d6 = json.loads(carol.getresponse().read())
            carol_sock2 = d6["socket"]
            log(f"[6] Carol  -> socket {carol_sock2}")

            # ── Assertion ─────────────────────────────────────────────
            if carol_sock2 != carol_sock:
                fail(
                    f"Carol's upstream changed {carol_sock} -> {carol_sock2} "
                    f"(Alice's stale cleanup closed Carol's upstream)"
                )

            carol.close()

            # ── Leak check ────────────────────────────────────────────
            c = http.client.HTTPConnection(
                "127.0.0.1", BACKEND_PORT, timeout=3
            )
            c.request("GET", "/_leak_check")
            resp = c.getresponse()
            status, body = resp.status, resp.read().decode()
            c.close()
            if status != 200:
                fail(f"leak_check returned {status}: {body}")

            log("PASS: Carol kept her upstream -- no cross-tenant leak")

        finally:
            nginx.terminate()
            nginx.wait(timeout=5)
    finally:
        backend.terminate()
        backend.wait(timeout=5)

    shutil.rmtree(tmpdir, ignore_errors=True)


if __name__ == "__main__":
    main()
