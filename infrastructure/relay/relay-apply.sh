#!/bin/bash
# Makes this server the relay a relay.env file describes, or no relay when it
# has no ports (docs/runbooks/relay.md). Run as root by install.sh with
# /etc/nebula/relay.env, and by nebula-relay-apply.service with the request
# the VPN agent wrote for the control plane (/var/lib/nebula/relay/relay.env).
# The agent is unprivileged: every value is checked again here, and only
# then copied to /etc/nebula/relay.env, so a rerun of install.sh keeps it.
#
# Forwarded connections are never logged.
set -euo pipefail

SRC=${1:-/etc/nebula/relay.env}
ETC=/etc/nebula
die() { printf 'relay: %s\n' "$*" >&2; exit 1; }
get() { [ -f "$SRC" ] && sed -n "s/^$1=//p" "$SRC" | tail -1; return 0; }

TARGET=$(get NEBULA_RELAY_TARGET)
PORTS=$(get NEBULA_RELAY_PORTS)
CONNTRACK=$(get NEBULA_RELAY_CONNTRACK_MAX)
REPORT_URL=$(get NEBULA_RELAY_REPORT_URL)
REPORT_TOKEN=$(get NEBULA_RELAY_REPORT_TOKEN)

SSH_PORT=$(sshd -T 2>/dev/null | awk '/^port /{p=$2} END{print p}' || true)
SSH_PORT=${SSH_PORT:-22}
WAN=$(ip -4 route show default | awk '{for (i = 1; i < NF; i++) if ($i == "dev") d = $(i + 1)} END {print d}')
[ -n "$WAN" ] || die "no default route to forward on"

CHECK=""
if [ -n "$PORTS" ]; then
  python3 -c 'import ipaddress,sys; ipaddress.IPv4Address(sys.argv[1])' "$TARGET" 2>/dev/null \
    || die "NEBULA_RELAY_TARGET must be the other server's IPv4 address"
  for p in $PORTS; do
    [[ $p =~ ^([0-9]{1,5})/(tcp|udp):([0-9]{1,5})$ ]] || die "relay port '$p' must look like 443/tcp:8447"
    here=${BASH_REMATCH[1]} proto=${BASH_REMATCH[2]} there=${BASH_REMATCH[3]}
    # Never the other server's SSH, agent, panel or certificate renewal.
    case $there in 22|80|8444|9443) die "relay port $there is not a VPN port; it is never forwarded" ;; esac
    [ "$here" != "$SSH_PORT" ] && [ "$here" != 80 ] || die "relay port $here is this server's own"
    flag=$([ "$proto" = tcp ] && echo -Hltn || echo -Hlun)
    [ -z "$(ss "$flag" "sport = :$here")" ] || die "relay port $here/$proto is already in use on this server"
    [ "$proto" = tcp ] && CHECK+="${CHECK:+,}$TARGET:$there"
  done
  if [ -n "$REPORT_URL$REPORT_TOKEN" ]; then
    [[ $REPORT_URL =~ ^https://[A-Za-z0-9.-]+(:[0-9]+)?/v1/relays/[a-z0-9_-]+/up$ ]] \
      || die "NEBULA_RELAY_REPORT_URL must look like https://<control plane>/v1/relays/<code>/up"
    [[ $REPORT_TOKEN =~ ^[A-Za-z0-9_-]{16,}$ ]] \
      || die "NEBULA_RELAY_REPORT_TOKEN must be the control plane's token"
  fi
  [ -z "$CONNTRACK" ] || [[ $CONNTRACK =~ ^[0-9]+$ ]] || die "NEBULA_RELAY_CONNTRACK_MAX must be a number"
fi

# Checked: this is the relay now, kept for install.sh's next run.
if [ "$SRC" != "$ETC/relay.env" ]; then
  if [ -n "$PORTS" ]; then
    install -m 600 "$SRC" "$ETC/relay.env"
  else
    rm -f "$ETC/relay.env"
  fi
fi

# --- forwarding (ufw's before.rules, so it survives a reload) -------------
FILE=/etc/ufw/before.rules
# ufw reload leaves nat rules it no longer has; take the live ones out.
if command -v iptables > /dev/null; then
  iptables -t nat -S | grep -- '--comment nebula-relay' | sed 's/^-A /-D /' \
    | while read -r rule; do iptables -t nat $rule; done || true
fi
awk '/^# nebula-relay start/ { skip = 1 } !skip && !/--comment nebula-relay/ { print }
  /^# nebula-relay end/ { skip = 0 }' "$FILE" > "$FILE.nebula"
if [ -n "$PORTS" ]; then
  nat="# nebula-relay start: forwarded to $TARGET\n*nat\n:PREROUTING ACCEPT [0:0]\n:POSTROUTING ACCEPT [0:0]\n"
  fwd=""
  for p in $PORTS; do
    here=${p%%/*}; proto=${p#*/}; proto=${proto%%:*}; there=${p##*:}
    nat+="-A PREROUTING -i $WAN -p $proto --dport $here -m comment --comment nebula-relay -j DNAT --to-destination $TARGET:$there\n"
    nat+="-A POSTROUTING -o $WAN -d $TARGET -p $proto --dport $there -m comment --comment nebula-relay -j MASQUERADE\n"
    # Only these ports, only to the target, may be forwarded.
    fwd+="-A ufw-before-forward -i $WAN -o $WAN -d $TARGET -p $proto --dport $there -m comment --comment nebula-relay -j ACCEPT\n"
  done
  nat+="COMMIT\n# nebula-relay end\n"
  awk -v nat="$nat" -v fwd="$fwd" '
    NR == 1 { printf "%s", nat }
    /^-A ufw-before-input -i lo -j ACCEPT/ && !done { printf "%s", fwd; done = 1 }
    { print }' "$FILE.nebula" > "$FILE.nebula2" && mv "$FILE.nebula2" "$FILE.nebula"
fi
cat "$FILE.nebula" > "$FILE" && rm -f "$FILE.nebula"

if [ -n "$PORTS" ]; then
  # Room to track every relayed connection; established ones idle out
  # after two hours instead of the kernel's five days.
  printf 'nf_conntrack\n' > /etc/modules-load.d/nebula-relay.conf; modprobe nf_conntrack
  printf 'net.netfilter.nf_conntrack_max=%s\nnet.netfilter.nf_conntrack_tcp_timeout_established=7200\n' \
    "${CONNTRACK:-131072}" > /etc/sysctl.d/99-nebula-relay.conf
  sysctl -q -p /etc/sysctl.d/99-nebula-relay.conf
  printf 'net.ipv4.ip_forward=1\n' > /etc/sysctl.d/99-nebula-forward.conf
  sysctl -q -p /etc/sysctl.d/99-nebula-forward.conf
else
  rm -f /etc/modules-load.d/nebula-relay.conf /etc/sysctl.d/99-nebula-relay.conf
fi
if command -v ufw > /dev/null && ufw status | grep -q '^Status: active'; then
  ufw reload > /dev/null
fi

# --- the agent checks the forwarded TCP ports answer from here -----------
if [ -f "$ETC/agent.env" ]; then
  before=$(grep '^NEBULA_RELAY_CHECK_TARGETS=' "$ETC/agent.env" || true)
  sed -i '/^NEBULA_RELAY_CHECK_TARGETS=/d' "$ETC/agent.env"
  [ -z "$CHECK" ] || printf 'NEBULA_RELAY_CHECK_TARGETS=%s\n' "$CHECK" >> "$ETC/agent.env"
  after=$(grep '^NEBULA_RELAY_CHECK_TARGETS=' "$ETC/agent.env" || true)
  # Not from inside a request the agent is answering: after it, with no wait.
  if [ "$before" != "$after" ] && systemctl is-active --quiet nebula-vpn-agent; then
    systemctl --no-block restart nebula-vpn-agent
  fi
fi

# --- and reports in itself, outward, every 30 seconds ---------------------
# TLS into Iran from abroad is filtered at times, and the control plane's own
# poll then fails while the relay works ("The relay reports in").
if [ -n "$PORTS" ] && [ -n "$REPORT_URL" ] && [ -n "$REPORT_TOKEN" ]; then
  install -m 600 /dev/null "$ETC/relay-report-token"
  printf '%s' "$REPORT_TOKEN" > "$ETC/relay-report-token"
  cat > /etc/systemd/system/nebula-relay-report.service <<UNIT
[Unit]
Description=Tell the exit's control plane this relay reaches it
[Service]
Type=oneshot
ExecStart=/bin/bash $(dirname "$(readlink -f "$0")")/relay-report.sh $REPORT_URL
UNIT
  cat > /etc/systemd/system/nebula-relay-report.timer <<'UNIT'
[Unit]
Description=Report the relay every 30 seconds
[Timer]
OnBootSec=30
OnUnitActiveSec=30
AccuracySec=5
[Install]
WantedBy=timers.target
UNIT
  systemctl daemon-reload; systemctl enable --now nebula-relay-report.timer > /dev/null 2>&1
else
  systemctl disable --now nebula-relay-report.timer > /dev/null 2>&1 || true
  rm -f /etc/systemd/system/nebula-relay-report.service /etc/systemd/system/nebula-relay-report.timer \
    "$ETC/relay-report-token"
fi
echo "relay: ${PORTS:-none}"
