# The DNS tunnel (server side)

A last resort for when every TCP and UDP route is blocked but DNS queries
still get out through resolvers inside Iran. Slow (tens of kbit/s up to
about 1 Mbit/s): for messages and the app's sign-in, not video. The design is
ADR 0004, "2026-11-05 revision"; this page is the server half. The app half
(resolver scanning, the engine, the last-resort offer) comes separately.

## How it fits together

```
phone -> ISP resolver -> ... -> NS for t1.<domain> = this server, port 53
      -> CottenDNS (nebula-cottendns.service) on port 53 of the server's
         address, or on 127.0.0.1:5310 behind whatever else owns port 53
      -> 127.0.0.1:8453, this server's VLESS Encryption inbound, only
```

- **Per server.** Any server can have its own tunnel, with up to four names
  (the first is used, the rest are backups, e.g. on another domain). The
  control plane keeps each server's names and key (`dns_tunnels` table) and
  tells the server's agent (`POST /v1/dns-tunnel` on the agent); the reconcile
  sweep tells every agent again (`nebula-api push-dns-tunnels`), so a rebuilt
  server or a missed push catches up within 15 minutes.
- **Fixed target.** CottenDNS forwards every connection to the VLESS
  Encryption inbound and nowhere else. The tunnel key alone reaches nothing:
  the app still needs its Nebula credential there, so revocation and
  allowances work as on any other route, and the traffic is encrypted twice.
- **Encryption.** AES-256-GCM only (`DATA_ENCRYPTION_METHOD = 5`,
  `ENCRYPTION_AUTO_DETECT = false`); a 32-hex-character key per server, made
  by the control plane, written by the agent beside the config
  (`/etc/nebula/cottendns/key`, group `nebula-cottendns`, 0640). CottenMax
  (beta, 8-byte tag) has no server switch: Nebula's client never selects it.
- **Install.** `install.sh` installs CottenDNS on every server: a pinned
  release checked by sha256 (`COTTENDNS_VERSION`, also in the offline bundle),
  its own unprivileged user, and a hardened unit whose only capability is
  binding port 53. It runs once the server has names. Where it listens is
  decided by the installer: port 53 on the server's address when nothing else
  has it (the firewall opens 53/udp and 53/tcp), else loopback port 5310
  behind whatever owns 53, which is left alone. It needs VLESS Encryption on
  that server (`--configure`).

## Turning it on

**Admin panel:** Servers → Manage → **DNS tunnel**: type the name (for
example `t1.example.org`) and Save. The dialog then lists the two records to
add at the DNS provider, with a copy button, and checks them: the name is
delegated to this server, and something answers on port 53.

**Admin command** (in the API container), the same:

```sh
nebula-api set-dns-tunnel --server-code <code> --domains t1.example.org
nebula-api set-dns-tunnel --server-code <code> --domains ""   # off
```

**Installer:** `NEBULA_COTTENDNS_DOMAINS=t1.example.org` on the first server
saves the name for that server (once; the panel owns it from then on). A
tunnel set up before this (names in `agent.env`, key in
`/etc/nebula/secrets/cottendns_key`) moves to the control plane with its key
on the next installer run, so apps that hold the key keep working. On a
joined server the installer points to the panel.

**DNS records**, at the DNS provider, both *DNS only* (never proxied):
(the panel's Server health → DNS records lists them with every other record the deployment needs, and checks each one)

| Type | Name | Value |
|---|---|---|
| NS | `t1.example.org` | `ns-t1.example.org` |
| A | `ns-t1.example.org` | the server's address |

The nameserver sits beside the delegated name, not inside it: a zone cannot
hold glue for a name it delegates away.

**Port 53 owned by another program** (another DNS tunnel or router): the
tunnel listens on 127.0.0.1:5310 and that program forwards the tunnel's
names there. For CottenRouter, a rule in `routes` of
`/etc/cottenrouter/config.json`:

```json
{
  "name": "nebula",
  "domains": ["t1.example.org"],
  "backend": "127.0.0.1:5310",
  "tcp_backend": "127.0.0.1:5310"
}
```

Signed-in apps read every server's names, key and server from
`GET /v1/dns-tunnel/` (`tunnels`; the first one also at the top level, for
apps from before there could be several) and keep them for when the API is
out of reach.

## The app (Android)

The app keeps every server's names, key and server from `GET /v1/dns-tunnel/`
in secure storage. It runs the CottenDNS client (`libcottendns_client.so`, from the same
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

## Checking

The panel's check does both of these from the control plane:

```sh
dig +short NS t1.example.org @1.1.1.1            # the delegation is live
dig @<server address> x.t1.example.org TXT       # something answers on port 53
```

The real test is a phone on each mobile carrier and on home internet with
public resolvers blocked.

Turning it off: empty the name in the panel (or `set-dns-tunnel --domains
""`); the agent stops the server and removes its config and key.
