/// The root helper for the macOS tunnel, run through macOS's own
/// administrator prompt (`osascript ... with administrator privileges`), as
/// the Linux helper runs through pkexec and the Windows one through UAC.
///
/// No Network Extension: that needs a paid Apple Developer membership. Xray
/// makes the `utun` interface and its routes itself (`autoSystemRoutingTable`,
/// its own connections bound to the real interface); this starts it as
/// root, points every network service's DNS at the tunnel, and puts it all
/// back when the app asks (a `stop` file in the session folder), when Xray
/// exits, or when the app is gone.
///
/// Arguments: mode (`start`), xray, config, state directory, owner pid,
/// comma-separated DNS servers. `start` copies the helper into a folder only
/// root can change, starts that copy in the background (mode `run`), and
/// returns once the routes are up or the start failed. Files it leaves for
/// the app in [macosSessionOutputs]: xray.pid, routes-ready, startup.error,
/// runtime.error, stopped.
library;

/// Where the helper leaves its files for the session in [state].
String macosSessionOutputs(String state) =>
    '/var/run/nebula-vpn-out/${state.split('/').last}';

/// The interface Xray creates: macOS names a utun by its number.
const String macosTunnelInterface = 'utun188';

const String macosVpnHelperScript = r'''#!/bin/bash
set -u
MODE="$1"; XRAY="$2"; CONFIG="$3"; STATE="$4"; OWNER="$5"; DNS="$6"
DEV=utun188
session="$(basename "$STATE")"
[[ "$session" =~ ^[A-Za-z0-9._-]{1,80}$ ]] || exit 1
[[ "$OWNER" =~ ^[0-9]+$ ]] || exit 1
[[ "$DNS" =~ ^[0-9a-fA-F.:,]+$ ]] || exit 1
OUT_ROOT=/var/run/nebula-vpn-out
OUT="$OUT_ROOT/$session"

if [ "$MODE" = start ]; then
  [ -d "$STATE" ] && [ ! -L "$STATE" ] && [ -f "$CONFIG" ] || exit 1
  case "$CONFIG" in "$STATE"/*) ;; *) exit 1 ;; esac
  [ -L "$OUT_ROOT" ] && exit 1
  install -d -m 755 -o root -g wheel "$OUT_ROOT" || exit 1
  rm -rf "$OUT"
  install -d -m 755 -o root -g wheel "$OUT" || exit 1
  install -m 700 -o root -g wheel "$0" "$OUT/helper.sh" || exit 1
  nohup /bin/bash "$OUT/helper.sh" run "$XRAY" "$CONFIG" "$STATE" "$OWNER" "$DNS" \
    </dev/null >/dev/null 2>&1 &
  for _ in $(seq 1 150); do
    [ -f "$OUT/routes-ready" ] && exit 0
    [ -f "$OUT/startup.error" ] && exit 1
    sleep 0.2
  done
  printf 'The tunnel did not come up in time.' > "$OUT/startup.error"
  exit 1
fi
[ "$MODE" = run ] || exit 1

child=""
dns_set=""
cleanup() {
  if [ -n "$child" ]; then
    kill "$child" 2>/dev/null
    for _ in $(seq 1 25); do kill -0 "$child" 2>/dev/null || break; sleep 0.2; done
    kill -9 "$child" 2>/dev/null
  fi
  if [ -n "$dns_set" ] && [ -f "$OUT/dns.saved" ]; then
    while IFS='|' read -r service servers; do
      # shellcheck disable=SC2086
      networksetup -setdnsservers "$service" $servers
    done < "$OUT/dns.saved"
    dscacheutil -flushcache; killall -HUP mDNSResponder 2>/dev/null
  fi
  touch "$OUT/stopped"
}
trap cleanup EXIT
trap 'exit 0' TERM INT HUP

"$XRAY" run -c "$CONFIG" > "$OUT/xray.log" 2>&1 &
child=$!
echo "$child" > "$OUT/xray.pid"
up=""
for _ in $(seq 1 75); do
  kill -0 "$child" 2>/dev/null || break
  if ifconfig "$DEV" >/dev/null 2>&1 && route -n get 1.1.1.1 2>/dev/null | grep -q "interface: $DEV"; then
    up=1; break
  fi
  sleep 0.2
done
if [ -z "$up" ]; then
  tail -c 600 "$OUT/xray.log" > "$OUT/startup.error"
  [ -s "$OUT/startup.error" ] || printf 'Xray did not bring up the tunnel.' > "$OUT/startup.error"
  exit 1
fi

# Every network service's DNS to the tunnel's resolvers, which its routes
# carry; what each had is put back on the way out.
: > "$OUT/dns.saved"
dns_set=1
networksetup -listallnetworkservices | tail -n +2 | grep -v '^\*' | while IFS= read -r service; do
  current="$(networksetup -getdnsservers "$service" | tr '\n' ' ')"
  case "$current" in *"aren't any"*) current=Empty ;; esac
  printf '%s|%s\n' "$service" "$current" >> "$OUT/dns.saved"
  # shellcheck disable=SC2086
  networksetup -setdnsservers "$service" ${DNS//,/ }
done
dscacheutil -flushcache; killall -HUP mDNSResponder 2>/dev/null
touch "$OUT/routes-ready"

while kill -0 "$OWNER" 2>/dev/null && kill -0 "$child" 2>/dev/null && [ ! -e "$STATE/stop" ]; do
  sleep 0.5
done
if ! kill -0 "$child" 2>/dev/null; then
  tail -c 600 "$OUT/xray.log" > "$OUT/runtime.error"
fi
exit 0
''';
