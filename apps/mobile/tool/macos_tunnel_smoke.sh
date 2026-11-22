#!/usr/bin/env bash
# The macOS tunnel end to end, on a Mac with passwordless sudo (GitHub's
# macOS runner): the app's root helper and tunnel config, a local Xray
# server as the VPN server, then traffic and DNS through the utun, and
# everything put back after. Needs tool/vendor_macos_runtime.sh first.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
xray="$root/assets/macos_runtime/xray"
work="$(mktemp -d)"
state="$work/nebula-tun-smoke"
mkdir -m 700 "$state"
dart run "$root/tool/macos_tunnel_smoke.dart" "$state"

physical="$(route -n get default | awk '/interface:/ {print $2}')"
cat > "$work/server.json" <<EOF
{
  "log": {"access": "$work/server-access.log", "loglevel": "info"},
  "inbounds": [{"listen": "127.0.0.1", "port": 18443, "protocol": "vless",
    "settings": {"clients": [{"id": "9d1b7c58-2f3e-4f5a-9c33-5f2d7f0e1a11"}], "decryption": "none"}}],
  "outbounds": [{"protocol": "freedom", "streamSettings": {"sockopt": {"interface": "$physical"}}}]
}
EOF
"$xray" run -c "$work/server.json" > "$work/server.log" 2>&1 &
server=$!
sleep 600 &
owner=$!
dns_state() {
  networksetup -listallnetworkservices | tail -n +2 | grep -v '^\*' | while IFS= read -r s; do
    echo "$s: $(networksetup -getdnsservers "$s" | tr '\n' ' ')"
  done
}
dns_before="$(dns_state)"

out="/var/run/nebula-vpn-out/$(basename "$state")"
finish() {
  touch "$state/stop"
  for _ in $(seq 1 50); do [ -f "$out/stopped" ] && break; sleep 0.2; done
  kill "$server" "$owner" 2>/dev/null || true
}
trap finish EXIT

if ! sudo /bin/bash "$state/helper.sh" start "$xray" "$state/client.json" "$state" "$owner" 1.1.1.1; then
  echo "helper failed: $(sudo cat "$out/startup.error" 2>/dev/null)"; exit 1
fi
echo "route to 1.1.1.1: $(route -n get 1.1.1.1 | awk '/interface:/ {print $2}')"
route -n get 1.1.1.1 | grep -q "interface: utun188"
networksetup -listallnetworkservices
scutil --dns | grep -m3 nameserver || true

curl -fsS -m 20 -o /dev/null -w 'through the tunnel: HTTP %{http_code}\n' https://www.example.com/
grep -q "example.com" "$work/server-access.log" || { echo "server saw no request"; cat "$work/server-access.log"; exit 1; }
echo "DNS lookup: $(dscacheutil -q host -a name github.com | awk '/ip_address/ {print $2; exit}')"
grep -c accepted "$work/server-access.log" | xargs echo "connections the server carried:"

finish
trap - EXIT
[ -f "$out/stopped" ] || { echo "helper did not stop"; exit 1; }
if route -n get 1.1.1.1 | grep -q "interface: utun188"; then echo "routes left behind"; exit 1; fi
dns_after="$(dns_state)"
[ "$dns_before" = "$dns_after" ] || { echo "DNS not restored: '$dns_before' -> '$dns_after'"; exit 1; }
curl -fsS -m 20 -o /dev/null https://www.example.com/ && echo "after stop: direct traffic works"
echo "macOS tunnel smoke test passed"
