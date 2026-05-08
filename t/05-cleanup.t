# Client-side cleanup: when the client TCP closes, the pinned upstream
# TCP must be closed too — otherwise the upstream lingers in the cache.
#
# We can't directly observe nginx's cache from the outside, but we CAN
# observe the backend: after a cleanly-closed authed client, the leak
# check should remain green.

use Test::Nginx::Socket 'no_plan';

run_tests();

__DATA__

=== TEST 1: a single auth request completes and returns body
--- http_config
upstream u {
    server 127.0.0.1:$TEST_NGINX_BACKEND_PORT;
    ntlm;
    ntlm_timeout 30s;
}
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



=== TEST 2: leak check is green after a cleanly-closed authed client
# Test::Nginx::Socket closes the client conn at the end of the block.
# The pool cleanup we registered in free_peer must run and post a close
# for the upstream. After that, querying /_leak_check on the backend
# should return 200 ok.
--- http_config
upstream u {
    server 127.0.0.1:$TEST_NGINX_BACKEND_PORT;
    ntlm;
    ntlm_timeout 30s;
}
--- config
location = /leak {
    proxy_pass http://u/_leak_check;
    proxy_http_version 1.0;
    proxy_set_header Connection "close";
}
location = /reset {
    proxy_pass http://u/_reset;
    proxy_http_version 1.0;
    proxy_set_header Connection "close";
}
location /t {
    proxy_pass http://u;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
}
--- request
GET /leak
--- error_code: 200
--- response_body
ok
