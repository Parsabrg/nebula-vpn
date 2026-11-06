# The DNS tunnel (server side)

A last resort for when every TCP and UDP route is blocked but DNS queries
still get out through resolvers inside Iran. Slow (tens of kbit/s up to
about 1 Mbit/s): for messages and the app's sign-in, not video. The design is
ADR 0004, "2026-11-05 revision"; this page is the server half. The app half
(resolver scanning, the engine, the last-resort offer) comes separately.

## How it fits together

```
phone -> ISP resolver -> ... -> NS for nt.<domain> = this server, port 53
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

The names are settings, never built into the app: the API lists them and the
app tries each in turn, so a name can be added or moved without an app update.
For now (2026-11-05) the one name is `nt.my-study-lab.org`; a backup on a
free EU.org domain is to be added once it is approved. The owner's WhiteDNS
tunnels (`ct.`, `st.`) share the domain and are left alone.

1. **DNS records** for `my-study-lab.org` in Cloudflare, both *DNS only* (the
   grey cloud, never proxied):

   | Type | Name | Content |
   |---|---|---|
   | A | `ns-nt` (`ns-nt.my-study-lab.org`) | `91.107.170.215` |
   | NS | `nt` (`nt.my-study-lab.org`) | `ns-nt.my-study-lab.org` |

   The nameserver sits beside the delegated name, not inside it: Cloudflare
   cannot hold glue for a name within a zone it delegates away.

2. **The router rule**, added to `routes` in `/etc/cottenrouter/config.json`,
   then restart CottenRouter. Nothing else in that file changes:

   ```json
   {
     "name": "nebula",
     "domains": ["nt.my-study-lab.org"],
     "backend": "127.0.0.1:5310",
     "tcp_backend": "127.0.0.1:5310"
   }
   ```

   A backup name later goes into the same `domains` list.

3. **The server**, with VLESS Encryption already on:

   ```sh
   sudo env NEBULA_COTTENDNS_DOMAINS=nt.my-study-lab.org ./install.sh
   systemctl is-active nebula-cottendns
   ```

   On a server whose nginx was set up by hand (Germany), do the same steps by
   hand instead of rerunning the installer: binary and hash as in
   `install.sh`, the user, the key, the unit, and
   `NEBULA_COTTENDNS_DOMAINS` in `agent.env`, then restart the agent. A
   second name is added to the comma-separated list.

4. **The API**, in `/etc/nebula/compose.env`, then recreate `api`:

   ```
   NEBULA_DNS_TUNNEL_DOMAINS=nt.my-study-lab.org
   NEBULA_DNS_TUNNEL_SERVER=study-lab-1
   ```

   Signed-in apps then read the names, the key and the server from
   `GET /v1/dns-tunnel/` and keep them for when the API is out of reach.

## The app (Android)

The app keeps the names, key and server from `GET /v1/dns-tunnel/` in secure
storage. It runs the CottenDNS client (`libcottendns_client.so`, from the same
release, pinned in `apps/mobile/third_party_src/vendor_plugin.py`) as a child
process in TCP mode on a random loopback port; Xray's VLESS Encryption
outbound to the named server dials that port, so the person's own credential
still applies. The first name is active, the others standby. Resolvers start
from CottenDNS's Iran list (`assets/dns_tunnel/resolvers_ir.txt`) and are
narrowed by the engine's `-scan-only` run.

People see it as "DNS tunnel (slow, last resort)" under the server it reaches,
last in the list. Automatic and the protocol test leave it out. While it is
connected, the "DNS resolvers" row shows how many resolvers the engine is using
and, on a tap, which.

### Resolvers (Settings > DNS tunnel resolvers)

- **Sets.** "Built-in (Iran)" is CottenDNS's list. People paste their own
  lists and save them as named sets; choosing another set keeps the others,
  and only "Delete this set" removes one.
- **One working list per network:** each mobile carrier (MCC/MNC, no
  permission needed) and Wi-Fi as one (telling Wi-Fi networks apart needs the
  location permission, which the app does not ask for).
- **Test and use** stops at 10 working resolvers, then tests the rest slowly
  in the background until 30 work with at least 10 inside Iran (Iran's ranges
  from Xray's own `geoip.dat`); short of Iranian ones, it also tests the
  built-in list. Progress and Stop are shown.
- **Test the whole list** only on Wi-Fi, never on mobile data.
- A network's list older than a week is retested on connect (at most 30 s),
  and on Wi-Fi when the app opens.

Phone, 2026-11-06: a 7,629-resolver list on MCI found 10 in 21 s and 30 in
3 min; on Wi-Fi the tunnel connected in 25 s (18 s on reconnect), 70 KB/s,
Google, Telegram, GitHub and YouTube loading.

## Checking

```sh
dig +short @127.0.0.1 -p 5310 x.nt.my-study-lab.org TXT   # CottenDNS answers
dig +short NS nt.my-study-lab.org @1.1.1.1                # the delegation is live
```

The real test is a phone on MCI, Irancell and home internet with public
resolvers blocked, compared with the WhiteDNS app on the same server.

Turning it off: remove the router rule, `systemctl disable --now
nebula-cottendns`, and empty the two compose settings.
