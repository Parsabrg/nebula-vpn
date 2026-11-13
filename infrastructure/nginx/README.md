# nginx: Xray XHTTP+TLS listener (`:8445`)

One tracked file, `xray-8445.conf`: the nginx server block that terminates
TLS on `:8445` and reverse-proxies VLESS-over-XHTTP traffic to Xray's own
loopback-only inbound. TLS termination stays in nginx rather than Xray
(REALITY was rejected for exactly that reason), and `:8445` was confirmed
free against the real host.

This file also proxies the control-plane API (`/v1/`) to the same backend
the existing `:8444` block reaches -- not for Xray's sake, just an ordinary
reverse proxy. This exists because the whole motivation for this milestone
is a client whose ISP blocks `:8444` outright: if the control-plane API
isn't *also* reachable over a port/transport that looks like ordinary
HTTPS, the app can never log in or request an Xray client far enough to
bring the tunnel up in the first place. A mobile build for such a user
should point its `API_BASE_URL` at `https://<host>:8445` instead of
`:8444`.

## What is, and isn't, tracked here

This repository owns the nginx files `install.sh` installs: `nebula-8444.conf`
(the panel and API on `:8444`), `xray-8445.conf` (the client-facing `:8445`),
`nebula-ratelimit.conf` and `cloudflare-real-ip.conf`; it writes
`snippets/nebula-admin-allow.conf` itself, from `NEBULA_ADMIN_ALLOW` (who may
open the panel and `/v1/admin/`; empty is everyone). The first VPS predates
the installer and has a hand-made `:8444` block instead; on that host
`xray-8445.conf` is added beside it as a second server block on a different
port.

## Install: drop-in, not an edited vhost

Install `xray-8445.conf` as its own file under nginx's `conf.d/`
drop-in directory, rather than folding its contents into the existing
`:8444` vhost file or `sites-enabled/`:

```shell
cp infrastructure/nginx/xray-8445.conf /etc/nginx/conf.d/xray-8445.conf
nginx -t && systemctl reload nginx
```

`conf.d/*.conf` is picked over `sites-available/` +
`sites-enabled/` symlinks because this file is a complete, independent
`server {}` block with no shared dependency on the `:8444` vhost's
directives -- there's nothing to "enable/disable" as a unit the way
Debian's sites-enabled convention is meant for, and a plain drop-in avoids
ever needing to touch a host's existing `:8444` file to
wire this one in. (Ubuntu/Debian's stock `nginx.conf` already globs
`/etc/nginx/conf.d/*.conf` by default alongside `sites-enabled/*`, so no
`include` line needs adding by hand -- confirm this is still true on the
real host before relying on it; if the stock `include` line was ever
removed or narrowed, add `include /etc/nginx/conf.d/*.conf;` inside the
`http {}` block of `/etc/nginx/nginx.conf`.)

## Before installing: two host-specific substitutions

1. **TLS certificate.** `xray-8445.conf` ships with placeholder paths
   (`/etc/letsencrypt/live/vpn.example.com/{fullchain,privkey}.pem`) and a
   placeholder `server_name` (`vpn.example.com`) -- the same placeholder
   convention used by `Settings.xray_public_host`/`xray_sni` in
   `services/vpn-agent/src/nebula_agent/settings.py`, since this repo does
   not know, and a pre-installer host's own `:8444` config can't be read from here
   either, what the real certificate path or hostname is on the operator's
   box. Point both `ssl_certificate`/`ssl_certificate_key` and
   `server_name` at whatever the existing `:8444` block already uses --
   the same certificate is fine to reuse here as long as it covers the
   hostname this port is served under (a wildcard/SAN cert already issued
   for the domain). Do not provision a separate certificate for this port
   unless the existing one doesn't already cover the name.
2. **Loopback port match.** The `proxy_pass` target
   (`http://127.0.0.1:8446`) and the `location /xhttp` path must match
   `Settings.xray_local_listen_port` and `Settings.xray_xhttp_path` in the
   deployed agent's environment exactly (defaults `8446` and `/xhttp`). `install.sh` gives a new
   install its own XHTTP and WebSocket paths and gRPC service name, written to both `agent.env`
   (`NEBULA_XRAY_XHTTP_PATH`, `NEBULA_XRAY_WS_PATH`, `NEBULA_XRAY_GRPC_SERVICE_NAME`) and this file,
   so installs do not share a fingerprint; installs from before 2026-10-30 keep the defaults.
   Nothing enforces this automatically -- if an operator overrides either
   setting, this file needs a matching edit.

## Port collision constraint

`:8445` must stay clear of every other service already running on this
box: the Nebula panel/API (`:8444`), the VPN agent's own mTLS listener
(`:9443`), and whatever else the host runs (here `443`, `2096`, `8443`,
`2053`). `:8445` was confirmed free against
the real deployment via `ss -tulnp`/`ufw status` before this decision was
made -- re-verify with the same commands if
deploying to a different host, since that confirmation was host-specific
and isn't something this repo can re-check on its own.

## Rate limiting the control-plane path

Both vhosts limit the API with the `nebula_api` zone (20 requests/second per
address, burst 20), declared in `nebula-ratelimit.conf`, which `install.sh`
copies into `/etc/nginx/conf.d/` (http context). It is keyed on the address
nginx sees -- behind Cloudflare, the one `cloudflare-real-ip.conf` restores --
never on a client-supplied `X-Forwarded-For`. It blunts a connection flood
before it reaches the API; the API's own per-account and per-network limits
stay the real ones.

`/v1/admin/` answers 404 on `:8445`: the panel calls the API inside the
server, and on `:8444` the admin routes are behind `NEBULA_ADMIN_ALLOW`.

## The `:8444` vhost

`nebula-8444.conf` is tracked and installed by `install.sh`. Its panel and
API blocks carry the same headers as `:8445` (HSTS, `X-Frame-Options`,
`X-Content-Type-Options`, `Referrer-Policy`, `server_tokens off`), the
`nebula_api` rate limit on the API, and `access_log off` on both: an access
log would keep client addresses next to paths that carry device ids and
subscription secrets, which `docs/privacy.md` says are never collected.
nginx's error log stays on.

## The Cloudflare backup route

Iran blocked this server's IP outright on 2026-09-22: no packet from a phone
on home broadband or on mobile data reached it, on any port, while a
Cloudflare-proxied hostname pointing at the *same* IP still answered. Every
Nebula hostname was `DNS only`, so sign-in and all six transports died at
once and the app was useless.

The backup route is a Cloudflare-proxied hostname in front of this same
`:8445` block. A client that cannot reach the server directly reaches the API
through it, and -- because arriving that way is itself proof the direct route
is blocked for that client -- is handed tunnel endpoints through it too. See
`services/api/src/nebula_api/cdn.py` and the app's `route_fallback.dart`.

WebSocket, XHTTP and gRPC cross it. Hysteria2 is QUIC over UDP and raw
TCP+TLS is not HTTP, so neither can, and the API hides both from a client on
this route rather than handing it something that reports "Protected" and
carries nothing.

gRPC must **not** go through nginx. Routed Cloudflare -> nginx -> xray it
carried 5.3 KB up and 0 B back while the app showed "Protected". The same
shape reached by Cloudflare directly works end to end, from a network where this server's address
is blocked. So a second Origin Rule sends `/grpc/` straight to the gRPC
inbound's own port; the `/grpc/` location in this file is no longer on the
CDN path.

### What the server needs

Already in `xray-8445.conf`: the CDN hostname on `server_name`, `/ws` and
`/grpc/` routed to the same inbounds the direct route uses (so credentials,
paths and service names are unchanged), an ACME location, and
`cloudflare-real-ip.conf`. That last one matters: behind Cloudflare the
socket peer is a Cloudflare edge, so without it every user counts as one
network for the API's per-network rate limits and they throttle each other.

The TLS certificate must cover the CDN name. It is the same certbot
invocation with one more `-d`:

```bash
certbot certonly --webroot -w /var/www/nebula-acme   --cert-name panel.example.org   -d panel.example.org -d api.example.org -d cdn.example.org --expand
```

Set `NEBULA_CDN_HOST` to the hostname in the API's environment. Empty (the
default) disables the route.

### What Cloudflare needs

Four things, all scoped to the one hostname:

1. **DNS**: an `A` record for the CDN name at the server's IP, **Proxied**.
2. **Origin Rule** -- Cloudflare does not proxy `:8445`, so the edge takes
   the request on 443 and this sends it to the right port:
   `(http.host eq "cdn.example.org" and ssl)` -> rewrite destination port to
   `8445`. The `and ssl` matters: it leaves plain HTTP on `:80`, which is
   where the certificate's HTTP-01 check arrives.
3. **Configuration Rule**: `(http.host eq "cdn.example.org")` -> SSL
   **Strict**. The zone-wide mode may be Flexible for other hostnames, which
   would send plain HTTP at a TLS-only port; this overrides it for this name
   alone, and Strict is available because the certificate now covers it.
4. **A second Origin Rule, placed after the first**:
   `(http.host eq "cdn.example.org" and ssl and starts_with(http.request.uri.path, "/<service>/"))` -- `<service>` is the install's `NEBULA_XRAY_GRPC_SERVICE_NAME` (`grpc` on installs from before 2026-10-30)
   -> rewrite destination port to `8447`, the gRPC inbound's own port. Last
   matching rule wins, so this overrides the first for gRPC paths only. The
   inbound's certificate must cover the CDN name, which the certbot line
   above arranges.
5. **Network -> gRPC: On** and **WebSockets: On**.

### A second CDN, for a network that throttles Cloudflare's names

Measured from Iran on 2026-10-06: the Cloudflare hostname answered the first
request on a connection and stalled the rest, while a `*.cloudfront.net` name
answered all of them. List both in `NEBULA_CDN_HOST` (comma-separated) and in
`NEBULA_API_ROUTES`, and a client that arrives by either is handed a tunnel
that goes back through the same one.

A CloudFront distribution for it (not yet built or tried -- needs an AWS
account): origin = this server's hostname, HTTPS only, port `8445`; allowed
methods all; caching disabled; origin request policy *AllViewer* so `Host`
and the WebSocket headers reach nginx; paths `/ws*` and `/xhttp*`. nginx must
answer a request whose `Host` is the distribution's name like the CDN name
above. Hysteria2 and gRPC do not cross it.

### What this costs

Cloudflare terminates TLS, so on this route it can see API traffic --
sign-ins included -- and the tunnel's payload, most of which is itself
end-to-end encrypted. The direct route is unchanged and is still tried
first; this is a fallback for a blocked address, not the normal path.

## Not covered here

Firewall/`ufw` rules to actually open `:8445` to the internet, and
installing/starting Xray itself (`../systemd/nebula-xray.service`), are
separate steps -- this README only covers the nginx side.
