# The DNS tunnel (server side)

A last resort for when every TCP and UDP route is blocked but DNS queries
still get out through resolvers inside Iran. Slow (tens of kbit/s up to
about 1 Mbit/s): for messages and the app's sign-in, not video. The design is
ADR 0004, "2026-11-05 revision"; this page is the server half. The app half
(resolver scanning, the engine, the last-resort offer) comes separately.

## How it fits together

```
phone -> ISP resolver -> ... -> NS for t.<domain> = this server, port 53
      -> CottenRouter (the owner's, owns port 53; one rule per name)
      -> CottenDNS for Nebula on 127.0.0.1:5310 (nebula-cottendns.service)
      -> 127.0.0.1:8453, this server's VLESS Encryption inbound, only
```

- **Fixed target.** CottenDNS forwards every connection to the VLESS
  Encryption inbound and nowhere else. The tunnel key alone reaches nothing:
  the app still needs its Nebula credential there, so revocation and
  allowances work as on any other route, and the traffic is encrypted twice.
- **Encryption.** AES-256-GCM only (`DATA_ENCRYPTION_METHOD = 5`,
  `ENCRYPTION_AUTO_DETECT = false`); the key is
  `/etc/nebula/secrets/cottendns_key` (32 hex characters, root:nebula-secrets
  0640). CottenMax (beta, 8-byte tag) has no server switch: Nebula's client
  never selects it.
- **Install.** `install.sh` installs it only when given a name: a pinned
  CottenDNS release checked by sha256 (`COTTENDNS_VERSION`), its own
  unprivileged user, a hardened unit, and the agent renders
  `/etc/nebula/cottendns/server_config.toml` and restarts it. It needs VLESS
  Encryption turned on (`--configure`). The offline bundle carries it too.

## Turning it on (owner)

Pick a name under a domain other than the panel's, for example
`t.<other domain>`, and a name for its nameserver, for example
`ns-t.<other domain>`.

1. **DNS records** at that domain's DNS host (Cloudflare: *DNS only*, the grey
   cloud, never proxied):

   | Type | Name | Value |
   |---|---|---|
   | A | `ns-t.<other domain>` | the server's IPv4 address (the glue) |
   | NS | `t.<other domain>` | `ns-t.<other domain>` |

2. **The router rule**, added to `routes` in `/etc/cottenrouter/config.json`,
   then restart CottenRouter. Nothing else in that file changes:

   ```json
   {
     "name": "nebula",
     "domains": ["t.<other domain>"],
     "backend": "127.0.0.1:5310",
     "tcp_backend": "127.0.0.1:5310"
   }
   ```

3. **The server**, with VLESS Encryption already on:

   ```sh
   sudo env NEBULA_COTTENDNS_DOMAIN=t.<other domain> ./install.sh
   systemctl is-active nebula-cottendns
   ```

   On a server whose nginx was set up by hand (Germany), do the same steps by
   hand instead of rerunning the installer: binary and hash as in
   `install.sh`, the user, the key, the unit, and `NEBULA_COTTENDNS_DOMAIN` in
   `agent.env`, then restart the agent.

4. **The API**, in `/etc/nebula/compose.env`, then recreate `api`:

   ```
   NEBULA_DNS_TUNNEL_DOMAIN=t.<other domain>
   NEBULA_DNS_TUNNEL_SERVER=<this server's code, e.g. study-lab-1>
   ```

   Signed-in apps then read the name, the key and the server from
   `GET /v1/dns-tunnel/` and keep them for when the API is out of reach.

## Checking

```sh
dig +short @127.0.0.1 -p 5310 x.t.<other domain> TXT   # CottenDNS answers
dig +short NS t.<other domain> @1.1.1.1                # the delegation is live
```

The real test is a phone on MCI, Irancell and home internet with public
resolvers blocked, compared with the WhiteDNS app on the same server.

Turning it off: remove the router rule, `systemctl disable --now
nebula-cottendns`, and empty the two compose settings.
