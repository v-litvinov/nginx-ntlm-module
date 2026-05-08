# Tests

Functional and security tests for `nginx-ntlm-module`. Uses
[`Test::Nginx::Socket`](https://metacpan.org/pod/Test::Nginx::Socket) and a
small Node.js mock backend that tracks per-TCP identity so assertions can
prove pinning works and isolation holds.

## Layout

| File | What it covers |
| --- | --- |
| `backend/server.js` | Mock NTLM upstream + audit/leak-check endpoints |
| `01-directives.t`   | Parsing of `ntlm`, `ntlm_timeout`, `ntlm_mode` |
| `02-pinning.t`      | Same client TCP → same upstream TCP |
| `03-cache.t`        | `ntlm N` cap, eviction, `ntlm_timeout` |
| `04-mode.t`         | `strict` / `lenient` / `auto` paths and Exchange long-poll auto-detection |
| `05-cleanup.t`      | Client disconnect closes the pinned upstream |
| `06-isolation.t`    | Cross-tenant isolation contract: under client churn (8 users, 4-slot cache, eviction exercised), no upstream socket ever serves two users |

## Prerequisites

- nginx built with this module (statically or as a dynamic module) and on `PATH`
- Perl with `Test::Nginx::Socket` — `cpan Test::Nginx`
- Node.js >= 14

## Running

```bash
# from repo root
t/run.sh                  # all tests
t/run.sh t/02-pinning.t   # one file
t/run.sh -v t/06-*.t      # verbose, glob
```

`run.sh` starts the mock backend on `${TEST_BACKEND_PORT:-8080}`, exports
`TEST_NGINX_BACKEND_PORT` for the test bodies, runs `prove`, and kills the
backend on exit.

If you prefer to manage the backend yourself:

```bash
node t/backend/server.js &
export TEST_NGINX_BACKEND_PORT=8080
prove -r t
kill %1
```

## What the mock backend tracks

Every inbound TCP connection gets a stable per-process numeric `socket` id.
On every request the backend records the `Authorization` value (parsed as
`<scheme> <token>` — for tests we use plain readable tokens like
`NTLM alice`). The set of distinct users seen on each socket is exposed:

- `GET /_audit` → JSON array of every request seen since last reset
- `GET /_reset` → clears audit + per-socket user sets
- `GET /_leak_check` → `200 ok` if every socket has only ever seen one
  distinct user; `409` with `{"socketId":..., "users":[...]}` otherwise
- `GET /ntlm/...` without `Authorization` → returns `401 WWW-Authenticate: NTLM`
- `GET /slow/<ms>` → sleeps before responding (timeout-test helper)

A normal `GET /<anything-else>` returns:

```json
{"socket":3,"user":"alice","firstUser":"alice","requestNum":2,"url":"/t"}
```

## Scope

This is a black-box functional suite: it drives nginx + the module
through ordinary HTTP and inspects responses plus the mock backend's
audit log. It covers directive parsing, NTLM passthrough, cache size
and timeout, mode selection, client-side cleanup, and the isolation
contract (no upstream socket ever serves two users under churn).

It does not cover race conditions whose triggering depends on precise
timing inside one nginx worker — those need either deterministic
debug hooks in the module or a sustained ASAN/TSAN stress harness run
separately from `prove`.
