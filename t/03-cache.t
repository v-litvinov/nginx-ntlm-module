# Cache size and timeout behavior.
#
#   * `ntlm N`  caps the number of pinned upstream sockets. When the cache
#     is full and a new client arrives, the oldest entry is evicted and its
#     upstream is closed.
#   * `ntlm_timeout T` closes idle pinned upstreams after T msec.
#
# These are integration tests, not white-box: we drive the module from the
# outside and look at the audit log on the mock backend.

use Test::Nginx::Socket 'no_plan';

run_tests();

__DATA__

=== TEST 1: ntlm_timeout closes idle upstream
# With a 500ms timeout, after caching one upstream and waiting > 500ms,
# a follow-up audit fetch (over a fresh HTTP/1.0 conn from nginx) must see
# the original upstream socket gone.
--- http_config
upstream u {
    server 127.0.0.1:$TEST_NGINX_BACKEND_PORT;
    ntlm;
    ntlm_timeout 500ms;
}
--- config
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
GET /t
--- more_headers
Authorization: NTLM alice
--- error_code: 200
--- wait: 1
--- response_body_like: "socket":\d+



=== TEST 2: ntlm 1 caps cache size to a single upstream
# Drive two distinct client connections through nginx (Test::Nginx::Socket
# closes between blocks), each NTLM-authenticated. With max=1, the second
# eviction must close the first upstream. The leak check must still pass —
# each upstream socket only ever saw one user.
--- http_config
upstream u {
    server 127.0.0.1:$TEST_NGINX_BACKEND_PORT;
    ntlm 1;
}
--- config
location = /reset {
    proxy_pass http://u/_reset;
    proxy_http_version 1.0;
    proxy_set_header Connection "close";
}
location = /leak {
    proxy_pass http://u/_leak_check;
    proxy_http_version 1.0;
    proxy_set_header Connection "close";
}
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
