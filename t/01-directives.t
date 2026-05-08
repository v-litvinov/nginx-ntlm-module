# Directive parsing: ntlm, ntlm_timeout, ntlm_mode.
#
# These tests probe the config parser: valid forms must load, invalid forms
# must fail with the expected log line. We do not exercise NTLM behavior
# here — just the configuration surface.

use Test::Nginx::Socket 'no_plan';

run_tests();

__DATA__

=== TEST 1: ntlm with no args is accepted
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



=== TEST 2: ntlm with a positive integer is accepted
--- http_config
upstream u {
    server 127.0.0.1:$TEST_NGINX_BACKEND_PORT;
    ntlm 50;
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



=== TEST 3: ntlm with zero is rejected at config time
--- http_config
upstream u {
    server 127.0.0.1:$TEST_NGINX_BACKEND_PORT;
    ntlm 0;
}
--- config
location /t { proxy_pass http://u; }
--- must_die
--- error_log
ntlm invalid value



=== TEST 4: ntlm with a non-numeric arg is rejected
--- http_config
upstream u {
    server 127.0.0.1:$TEST_NGINX_BACKEND_PORT;
    ntlm abc;
}
--- config
location /t { proxy_pass http://u; }
--- must_die
--- error_log
ntlm invalid value



=== TEST 5: ntlm_timeout with an msec value is accepted
--- http_config
upstream u {
    server 127.0.0.1:$TEST_NGINX_BACKEND_PORT;
    ntlm;
    ntlm_timeout 5s;
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



=== TEST 6: ntlm_mode strict is accepted at location scope
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
--- error_code: 200



=== TEST 7: ntlm_mode lenient is accepted
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
--- error_code: 200



=== TEST 8: ntlm_mode auto is accepted
--- http_config
upstream u {
    server 127.0.0.1:$TEST_NGINX_BACKEND_PORT;
    ntlm;
}
--- config
location /t {
    ntlm_mode auto;
    proxy_pass http://u;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
}
--- request
GET /t
--- error_code: 200



=== TEST 9: ntlm_mode with an unknown value is rejected
--- http_config
upstream u {
    server 127.0.0.1:$TEST_NGINX_BACKEND_PORT;
    ntlm;
}
--- config
location /t {
    ntlm_mode bogus;
    proxy_pass http://u;
}
--- must_die
--- error_log
invalid value "bogus" in "ntlm_mode"
