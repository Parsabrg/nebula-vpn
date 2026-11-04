# Port 443

Many networks in Iran treat unusual ports worse than 443. On a new install the
server also answers on 443:

- **TCP 443** (nginx): the panel, the API and the XHTTP/WebSocket/gRPC site.
  nginx chooses the site by the name the client asks for (`panel.`, `api.` or
  the bare domain), so each keeps its own rate limits, real client addresses
  and admin allowlist.
- **UDP 443**: Hysteria2 (`NEBULA_XRAY_HYSTERIA_PORT=443`). With port hopping
  the range redirects to it.

The old ports (8444, 8445, 8450/udp) stay open, and `/v1/routes` lists the
443 addresses first and the old ones after, so apps that know the old ports
keep working. The panel's address is `https://panel.<domain>` (no port).

REALITY keeps its own port: it borrows another site's name, which nginx
cannot route without hiding client addresses.

## How `install.sh` decides

A server whose `/etc/nebula/agent.env` already exists keeps its ports. It gets
443 only when that file has `NEBULA_XRAY_PUBLIC_PORT=443`. A restore keeps the
ports of the server it came from.

## Turning it on for an existing server

This changes the ports and the panel's address, so the owner decides, one
server at a time. Check that nothing else listens on 443 first:

```sh
sudo ss -ltnup | grep ':443 '         # must print nothing
sudo sed -i '/^NEBULA_XRAY_PUBLIC_PORT=/d; /^NEBULA_XRAY_HYSTERIA_PORT=/d' /etc/nebula/agent.env
printf 'NEBULA_XRAY_PUBLIC_PORT=443\nNEBULA_XRAY_HYSTERIA_PORT=443\n' | sudo tee -a /etc/nebula/agent.env
sudo ./install.sh
```

If the server hops Hysteria2 ports, change the target port in the
`nebula-hysteria-hop` block of `/etc/ufw/before.rules` from 8450 to 443, then
`sudo ufw reload`.

A server whose nginx site was made by hand (not by `install.sh`) needs the
same by hand: add `listen 443 ssl http2;` and `listen [::]:443 ssl http2;`
beside each `listen 8444`/`8445 ssl` line, set the two agent settings above,
open `443/tcp` and `443/udp` in ufw, and add the 443 addresses to the front of
`NEBULA_API_ROUTES` in `compose.env`.

Apps learn the new ports with their next credential (a reconnect) and the new
routes at their next sign-in check.

## Checking

```sh
curl -s -o /dev/null -w '%{http_code}\n' https://api.<domain>/v1/servers/   # 401
sudo python3 infrastructure/check-protocols.py                              # Hysteria2 and XHTTP on 443
```
