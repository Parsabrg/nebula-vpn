# VLESS + REALITY

REALITY needs no domain or certificate of its own. To anyone without the
server's key it answers with the TLS handshake of another site (the
"borrowed" site), so a block on the deployment's own domain does not reach
it and a probe sees that site. Two profiles:

- `vless-reality-vision`: raw TCP with the Vision flow (port 8456 by default);
- `vless-reality-xhttp`: XHTTP over REALITY (the next port, 8457).

Both are dialled at the server itself, never through the CDN route.

## Turning it on

It opens two new ports, so the owner decides, server by server.

```sh
sudo ./install.sh --configure
```

Answer **y** at "VLESS REALITY", keep or change the port, and name the site to
borrow. The installer makes the key pair (`xray x25519`) and a short id, writes
them to `/etc/nebula/agent.env`, opens the ports, adds both profiles (and their
ad-block siblings) and enables them on this server.

## Choosing the site

It should load from Iran without a VPN, speak TLS 1.3 and HTTP/2, and be big
enough that traffic to it is ordinary. Check it from a phone in Iran before
using it. Changing it later: rerun `--configure` and give another name; the
key pair stays.

## Checking

```sh
sudo grep -c reality /etc/nebula/xray/config.json        # 2 inbounds
openssl s_client -connect <server-ip>:8456 -servername <site> </dev/null 2>/dev/null | grep subject
```

The second command should show the borrowed site's certificate. The app
then lists "VLESS REALITY (Vision)" and "(XHTTP)" for this server.
