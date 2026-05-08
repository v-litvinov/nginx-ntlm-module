# ntlm_mode selects strict vs lenient liveness checks for cached peers.
#
#   - strict:  before reusing a cached upstream, peek the socket; any
#              unexpected bytes mean it's dirty and must be closed. This
#              breaks long-poll endpoints that legitimately have data
#              queued mid-idle.
#   - lenient: skip the peek; trust the cached entry. Required for
#              Exchange ActiveSync Ping, MAPI notifications, and EWS
#              streaming SOAP actions.
#   - auto:    the default — apply lenient only for known long-poll URIs.
#
# We can't easily synthesize a "dirty" cached connection from the outside,
# so these tests verify the configuration paths execute and don't break
# normal request flow. Auto-detection of long-poll URIs is exercised by
# routing through endpoints whose URI matches the heuristics in
# ngx_http_ntlm_should_lenient_auto().

use Test::Nginx::Socket 'no_plan';

run_tests();

__DATA__

=== TEST 1: strict mode allows normal requests
--- http_config
upstream u {
    server 127.0.0.1:$TEST_NGINX_BACKEND_PORT;
    ntlm;
}
--- config
location /t {
    ntlm_mode strict;
    proxy_pass http://u;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
}
--- request
GET /t
--- more_headers
Authorization: NTLM alice
--- error_code: 200



=== TEST 2: lenient mode allows normal requests
--- http_config
upstream u {
    server 127.0.0.1:$TEST_NGINX_BACKEND_PORT;
    ntlm;
}
--- config
location /t {
    ntlm_mode lenient;
    proxy_pass http://u;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
}
--- request
GET /t
--- more_headers
Authorization: NTLM alice
--- error_code: 200



=== TEST 3: auto mode on /Microsoft-Server-ActiveSync?Cmd=Ping is OK
# Per ngx_http_ntlm_should_lenient_auto(): URIs starting with
# /Microsoft-Server-ActiveSync and args containing Cmd=Ping enable lenient.
# We can't observe the internal flag from outside; we just confirm the
# request path doesn't error.
--- http_config
upstream u {
    server 127.0.0.1:$TEST_NGINX_BACKEND_PORT;
    ntlm;
}
--- config
location /Microsoft-Server-ActiveSync {
    ntlm_mode auto;
    proxy_pass http://u;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
}
--- request
GET /Microsoft-Server-ActiveSync?Cmd=Ping
--- more_headers
Authorization: NTLM alice
--- error_code: 200



=== TEST 4: auto mode on /mapi/notifications enables lenient internally
--- http_config
upstream u {
    server 127.0.0.1:$TEST_NGINX_BACKEND_PORT;
    ntlm;
}
--- config
location /mapi {
    ntlm_mode auto;
    proxy_pass http://u;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
}
--- request
GET /mapi/notifications
--- more_headers
Authorization: NTLM alice
--- error_code: 200



=== TEST 5: auto mode on /EWS/ with SOAPAction streaming
--- http_config
upstream u {
    server 127.0.0.1:$TEST_NGINX_BACKEND_PORT;
    ntlm;
}
--- config
location /EWS/ {
    ntlm_mode auto;
    proxy_pass http://u;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
}
--- request
POST /EWS/Exchange.asmx
--- more_headers
Authorization: NTLM alice
SOAPAction: "GetStreamingEvents"
Content-Type: text/xml; charset=utf-8
--- error_code: 200
