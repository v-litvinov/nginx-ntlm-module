'use strict';

/*
 * Mock NTLM upstream for nginx-ntlm-module tests.
 *
 * - Tracks each inbound TCP connection: a stable per-process socket id, the
 *   set of distinct NTLM/Negotiate "users" seen on it, and a request count.
 * - Echoes that identity back in JSON so Test::Nginx assertions can prove
 *   that two requests landed on the same upstream TCP (pinning works) or
 *   different upstream TCPs (isolation works).
 * - Records every request in an in-memory audit log queryable via /_audit.
 * - Reports cross-tenant leaks via /_leak_check: returns 200 if every
 *   socket has only ever seen one distinct user, 409 with details otherwise.
 *
 * The "user" extracted from an Authorization header is whatever follows
 * the scheme. Real NTLM tokens are base64 NTLMSSP blobs; for tests we use
 * plain readable tokens like "NTLM alice" so assertions stay simple.
 */

const http = require('http');

const port = parseInt(process.env.PORT || '8080', 10);

let nextSocketId = 0;
const sockets = new Map();    /* socket -> state (live only) */
const allSockets = new Map(); /* socketId -> state (incl. closed) — leak detection must remember */
const audit = [];             /* { socketId, auth, user, url, t } */

function stateFor(sock) {
    let s = sockets.get(sock);
    if (s) return s;
    s = { id: ++nextSocketId, users: new Set(), requests: 0, firstUser: null };
    sockets.set(sock, s);
    allSockets.set(s.id, s);
    sock.on('close', () => sockets.delete(sock));
    return s;
}

function parseAuth(h) {
    if (!h) return null;
    const m = /^(NTLM|Negotiate)\s+(.+)$/i.exec(h);
    return m ? m[2].trim() : null;
}

const server = http.createServer((req, res) => {
    const sock = req.socket;
    const s = stateFor(sock);
    s.requests++;

    const auth = req.headers.authorization || '';
    const user = parseAuth(auth);
    if (user) {
        s.users.add(user);
        if (!s.firstUser) s.firstUser = user;
    }

    audit.push({
        socketId: s.id,
        auth: auth || null,
        user,
        url: req.url,
        t: Date.now(),
    });

    /* ---- internal endpoints ---- */
    if (req.url === '/_audit') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(audit));
        return;
    }
    if (req.url === '/_reset') {
        audit.length = 0;
        allSockets.clear();
        for (const v of sockets.values()) {
            v.users.clear();
            v.requests = 0;
            v.firstUser = null;
            allSockets.set(v.id, v);
        }
        res.writeHead(204);
        res.end();
        return;
    }
    if (req.url === '/_leak_check') {
        let leak = null;
        for (const v of allSockets.values()) {
            if (v.users.size > 1) {
                leak = { socketId: v.id, users: [...v.users] };
                break;
            }
        }
        if (leak) {
            res.writeHead(409, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify(leak) + '\n');
        } else {
            res.writeHead(200, { 'Content-Type': 'text/plain' });
            res.end('ok\n');
        }
        return;
    }

    /* ---- /ntlm/* requires Authorization (simulates challenge) ---- */
    if (req.url.startsWith('/ntlm') && !user) {
        res.writeHead(401, { 'WWW-Authenticate': 'NTLM' });
        res.end();
        return;
    }

    /* ---- /slow/<ms> sleeps before responding (for timeout tests) ---- */
    const slow = /^\/slow\/(\d+)/.exec(req.url);
    if (slow) {
        setTimeout(() => respond(res, s, user, req.url), parseInt(slow[1], 10));
        return;
    }

    respond(res, s, user, req.url);
});

function respond(res, s, user, url) {
    if (res.writableEnded) return;
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
        socket: s.id,
        user,
        firstUser: s.firstUser,
        requestNum: s.requests,
        url,
    }));
}

server.on('connection', (sock) => stateFor(sock));

server.listen(port, () => {
    process.stderr.write('mock-ntlm-backend listening on ' + port + '\n');
});

process.on('SIGTERM', () => server.close(() => process.exit(0)));
process.on('SIGINT',  () => server.close(() => process.exit(0)));
