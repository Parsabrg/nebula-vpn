# The standard protocol set

Every server offers the same set, so a user who moves between servers or
relays finds the same choices, and a block on one protocol leaves the others.
`install.sh` turns it on for a new install or join; `--configure` changes it.

| Name in `NEBULA_PROTOCOLS` | Protocol | What it is for |
|---|---|---|
| `reality` | VLESS REALITY, Vision and XHTTP | Looks like TLS to a borrowed site; needs no domain. See vless-reality.md |
| (always on) | VLESS XHTTP + TLS | The one that goes through a CDN, the Vercel front and ECH when the server's address is blocked |
| `ws` | VLESS WebSocket + TLS | Also passes Cloudflare; a fallback for XHTTP |
| `grpc` | VLESS gRPC + TLS | Also passes Cloudflare |
| `tcp` | VLESS raw TCP + TLS | Simple and fast; carries well through relays |
| `hysteria` | Hysteria2, Salamander and port hopping | Fastest where UDP gets through |
| `ss2022` | Shadowsocks-2022 | Fast on home lines; no TLS |
| `vlessenc` | VLESS Encryption | Post-quantum, no TLS; what the DNS tunnel forwards into |
| (always on) | WireGuard | App only; share links cannot carry it |

Also offered, not per server: the DNS tunnel (dns-tunnel.md, on servers with
a delegated name) and WARP inside Xray (from the app).

Left out: VMess (`vmess`) -- older and weaker than VLESS, which every client
has. It can still be turned on with `--configure`.

## Changing it

On the server:

```bash
sudo ./install.sh --configure                       # asks, protocol by protocol
sudo NEBULA_PROTOCOLS="grpc ws tcp hysteria ss2022 vlessenc reality" ./install.sh --configure
```

With `NEBULA_PROTOCOLS`, exactly those are on and every port and borrowed site
is kept. The control plane reads what each server serves at its usage poll and
offers a protocol that is new there within a minute. A protocol turned off on
a server is not withdrawn on the server's word yet: `--configure` prints the
command for the control plane.
