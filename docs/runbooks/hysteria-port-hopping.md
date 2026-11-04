# Hysteria2 port hopping

With hopping, the server answers Hysteria2 on a UDP range as well as on its
own port, and the app moves between the range's ports every 30 seconds. A
block on one port then does not end the connection.

- **New installs** hop on `20000-50000/udp`: `install.sh` writes
  `NEBULA_XRAY_HYSTERIA_HOP_PORTS=20000-50000` to `/etc/nebula/agent.env` and
  adds a redirect from the range to the Hysteria2 port in
  `/etc/ufw/before.rules` (marked `nebula-hysteria-hop`).
- **Existing servers** do not change by themselves. The redirect opens no
  other port: the firewall sees each packet on the Hysteria2 port, which is
  already open.

## Turning it on for an existing server

This changes what the server listens on, so the owner decides.

```sh
echo 'NEBULA_XRAY_HYSTERIA_HOP_PORTS=20000-50000' | sudo tee -a /etc/nebula/agent.env
sudo ./install.sh          # adds the redirect, restarts the agent
sudo iptables -t nat -S PREROUTING | grep 20000:50000
```

Apps learn the range with their next Hysteria2 credential (a reconnect).

## Turning it off

Remove the line from `agent.env`, delete the `nebula-hysteria-hop` block
from `/etc/ufw/before.rules`, then `sudo ufw reload` and
`sudo systemctl restart nebula-vpn-agent`.

## Limits

- IPv4 only.
- The redirect points at the Hysteria2 port it was made with. If the port is
  moved with `--configure`, edit the rule in `before.rules` to match.
- A Cloudflare route is TCP; hopping applies only to the direct UDP route.
