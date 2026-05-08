# Connection pinning: an NTLM-authenticated client TCP must always reach
# the same upstream TCP for the lifetime of the cache entry.
#
# A direct cross-response "same socket id" assertion is awkward in
# Test::Nginx::Socket (per-pipelined-response matching can't share regex
# captures), so the pinning effect is asserted indirectly here:
#
#   * TEST 1 — two pipelined NTLM requests on one client TCP both
#     succeed and echo the same authenticated user (would 401 if the
#     module had broken NTLM passthrough).
#   * TEST 2 — non-NTLM requests still flow through (module is
#     transparent for unauthenticated traffic).
#
# The broader "no upstream socket ever serves two distinct users"
# contract is asserted by t/06-isolation.t.

use Test::Nginx::Socket 'no_plan';

run_tests();

__DATA__

=== TEST 1: two pipelined NTLM requests on one client TCP succeed
--- http_config
upstream u {
    server 127.0.0.1:$TEST_NGINX_BACKEND_PORT;
    ntlm;
}
--- config
location /t {
    proxy_pass http://u;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
}
--- pipelined_requests eval
["GET /t", "GET /t"]
--- more_headers
Authorization: NTLM alice
--- error_code eval
[200, 200]
--- response_body_like eval
[qr/"user":"alice"/, qr/"user":"alice"/]



=== TEST 2: a non-NTLM request still works (module is transparent)
--- http_config
upstream u {
    server 127.0.0.1:$TEST_NGINX_BACKEND_PORT;
    ntlm;
}
--- config
location /t {
    proxy_pass http://u;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
}
--- request
GET /t
--- error_code: 200
--- response_body_like: "socket":\d+
