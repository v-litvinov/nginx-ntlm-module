# Cross-tenant isolation contract.
#
# The whole point of this module is to pin a client TCP to one upstream
# TCP so that NTLM auth state isn't shared between clients. Under churn
# (more distinct users than the cache can hold), pinning still has to
# honor that contract: each upstream socket should only ever serve one
# authenticated user.
#
# Asserted via the mock backend's /_leak_check endpoint, which tracks
# the set of distinct users seen on each upstream socket and returns
# 200 if every socket has only ever seen one user, 409 otherwise.

use Test::Nginx::Socket 'no_plan';

# Use a small cache + short timeout so entries cycle quickly under churn.
our $UpstreamConfig = <<'_EOC_';
    server 127.0.0.1:$TEST_NGINX_BACKEND_PORT;
    ntlm 4;
    ntlm_timeout 1s;
_EOC_

run_tests();

__DATA__

=== TEST 1: reset audit
--- http_config eval
"upstream u {\n${main::UpstreamConfig}}\n"
--- config
location = /reset {
    proxy_pass http://u/_reset;
    proxy_http_version 1.0;
    proxy_set_header Connection "close";
}
--- request
GET /reset
--- error_code: 204



=== TEST 2: drive client as alice
--- http_config eval
"upstream u {\n${main::UpstreamConfig}}\n"
--- config
location /t {
    proxy_pass http://u;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
}
--- request
GET /t
--- more_headers
Authorization: NTLM alice
--- error_code: 200
--- response_body_like: "user":"alice"



=== TEST 3: drive client as bob
--- http_config eval
"upstream u {\n${main::UpstreamConfig}}\n"
--- config
location /t {
    proxy_pass http://u;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
}
--- request
GET /t
--- more_headers
Authorization: NTLM bob
--- error_code: 200
--- response_body_like: "user":"bob"



=== TEST 4: drive client as carol
--- http_config eval
"upstream u {\n${main::UpstreamConfig}}\n"
--- config
location /t {
    proxy_pass http://u;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
}
--- request
GET /t
--- more_headers
Authorization: NTLM carol
--- error_code: 200
--- response_body_like: "user":"carol"



=== TEST 5: drive client as dave
--- http_config eval
"upstream u {\n${main::UpstreamConfig}}\n"
--- config
location /t {
    proxy_pass http://u;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
}
--- request
GET /t
--- more_headers
Authorization: NTLM dave
--- error_code: 200
--- response_body_like: "user":"dave"



=== TEST 6: stress — extra users to force eviction (ntlm 4 cap)
--- http_config eval
"upstream u {\n${main::UpstreamConfig}}\n"
--- config
location /t {
    proxy_pass http://u;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
}
--- request
GET /t
--- more_headers
Authorization: NTLM eve
--- error_code: 200
--- response_body_like: "user":"eve"



=== TEST 7: more eviction churn
--- http_config eval
"upstream u {\n${main::UpstreamConfig}}\n"
--- config
location /t {
    proxy_pass http://u;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
}
--- request
GET /t
--- more_headers
Authorization: NTLM frank
--- error_code: 200
--- response_body_like: "user":"frank"



=== TEST 8: more eviction churn
--- http_config eval
"upstream u {\n${main::UpstreamConfig}}\n"
--- config
location /t {
    proxy_pass http://u;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
}
--- request
GET /t
--- more_headers
Authorization: NTLM grace
--- error_code: 200
--- response_body_like: "user":"grace"



=== TEST 9: more eviction churn
--- http_config eval
"upstream u {\n${main::UpstreamConfig}}\n"
--- config
location /t {
    proxy_pass http://u;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
}
--- request
GET /t
--- more_headers
Authorization: NTLM heidi
--- error_code: 200
--- response_body_like: "user":"heidi"



=== TEST 10: leak_check — every upstream saw exactly one user
# After 8 distinct-user clients churned through a 4-slot cache, every
# upstream socket must have served only one user.
--- http_config eval
"upstream u {\n${main::UpstreamConfig}}\n"
--- config
location = /leak {
    proxy_pass http://u/_leak_check;
    proxy_http_version 1.0;
    proxy_set_header Connection "close";
}
--- request
GET /leak
--- error_code: 200
--- response_body
ok
