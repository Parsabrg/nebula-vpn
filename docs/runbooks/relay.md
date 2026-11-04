# Relays

A relay is a joined server that forwards some of its ports to another server
(the exit), for networks that reach the relay and not the exit. The app lists
it as a server of its own, for example "Germany via Tehran". Traffic stays
encrypted from the phone to the exit; the relay only forwards packets (the
kernel does it, with no VPN software in the path) and never logs them.

- **One credential.** A device asking for the relay gets its credential on
  the exit, the same one the exit's own entry hands out, with the relay's
  address and port. Device limits, usage and revocation are the exit's.
- **What is offered.** Only the exit's profiles listed in `NEBULA_RELAYS`
  (and their ad-block siblings). WireGuard is never offered through a relay.
- **Health.** The relay's agent checks, with every usage poll, that the
  exit's forwarded TCP ports answer from the relay. While none does, or the
  relay's agent does not answer, the relay is listed as under maintenance and
  refuses connections (HTTP 423), instead of failing without a reason.
- **TLS** still names the exit (its certificate), so protocols with TLS show
  the exit's domain to filtering on the phone-to-relay leg too. Shadowsocks-2022
  and VLESS Encryption carry no domain.
- **Address.** Every relay user reaches the exit as the relay's one address.
  Nothing on the exit may limit or ban by address on the forwarded ports:
  fail2ban stays SSH-only, and the Xray site (8445) has no `limit_req`.

Turning a server into a relay changes what it runs and opens ports on it, so
it needs the owner's OK; the owner chooses the ports.

## On the relay

Write `/etc/nebula/relay.env`, then rerun the installer:

```sh
sudo tee /etc/nebula/relay.env <<'EOF'
NEBULA_RELAY_TARGET=<exit's IPv4 address>
# port here/proto:port on the exit
NEBULA_RELAY_PORTS=443/tcp:8453 443/udp:8450 8443/tcp:8451 8443/udp:8451 2053/tcp:8449 2083/tcp:8448 2087/tcp:8447 2096/tcp:8445
# connections the kernel can track at once (default 131072, about 40 MB)
NEBULA_RELAY_CONNTRACK_MAX=131072
EOF
sudo ./install.sh
```

`install.sh` then:

- forwards each listed port to the exit (DNAT) and rewrites the source to the
  relay (MASQUERADE), in a marked block of `/etc/ufw/before.rules`;
- lets the firewall forward only those ports, only to the exit;
- sizes connection tracking, and lets idle established connections go after
  two hours instead of five days (`/etc/sysctl.d/99-nebula-relay.conf`);
- sets `NEBULA_RELAY_CHECK_TARGETS` in `agent.env` for the health check.

It refuses the exit's SSH, port 80, panel (8444) and agent (9443), the relay's
own SSH and port 80, and any port already in use on the relay. Forwarding
stays IPv4 only.

A phone uses about one tracked connection per tunnel (XHTTP a few), so the
default fits thousands of users.

Turning it off: delete `/etc/nebula/relay.env` and rerun `sudo ./install.sh`.

## On the control plane

Add the relay to `/etc/nebula/compose.env` (one line of JSON), then restart
`api` and `usage`:

```sh
NEBULA_RELAYS=[{"code":"study-lab-1-via-tehran","display_name":"Germany via Tehran","exit":"study-lab-1","via":"tehran","host":"<relay's address>","ports":{"hysteria2":443,"vless-tcp-tls":2053,"vless-enc":443,"vless-grpc-tls":2087,"vless-xhttp-tls":2096}}]
```

`exit` and `via` are server codes; `ports` gives the relay's port for each of
the exit's profiles, matching `NEBULA_RELAY_PORTS` above. The app lists them in
this order, so put the fastest through the relay first; leave out any that
are too slow there (on the first relay, WebSocket and Shadowsocks-2022 ran
at 2-5 KB/s) and they are not offered, even if still forwarded. The relay is offered
to every account that may use the exit.

## First use and the API

An app that never used the relay has no credential for it and must reach the
API first. Test that with the exit's address blocked and the Cloudflare route
stalled. If it fails: the exit's Xray site (8445) also serves the API's
`/v1/`, so with 8445 forwarded the API is reachable through the relay under a
name the exit's certificate covers. Add a name such as `relay.<domain>`
pointing at the relay to the exit's certificate and to its Xray site's
`server_name`, and put `https://relay.<domain>:<relay port>` in
`NEBULA_API_ROUTES`. Never forward the relay's own port 80: its certificate
renews there.

## Traffic

Relayed traffic crosses the relay twice: in from the phone and out to the
exit, then back. A relay carrying X GB of users' traffic moves about 2X GB,
X of it international. Check the relay's plan for limits on international
traffic before turning it on; one server inside Iran sending a lot to one
foreign address is also easy for its provider to notice.

## Checking

```sh
sudo iptables -t nat -S PREROUTING | grep nebula-relay
sudo iptables -S ufw-before-forward | grep nebula-relay
docker exec nebula-production-usage-1 nebula-api collect-usage   # on the control plane
```

The relay's source `relay` must not be among the failed sources. On a phone,
pick the relay and test each protocol.
