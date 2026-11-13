#!/bin/bash
# A relay's check-in, every 30 seconds (nebula-relay-report.timer): tells the
# exit's control plane this relay reaches it, the way relayed traffic goes
# (outward from Iran, where TLS from abroad is filtered at times). The answer
# carries what the relay should be, as the panel says; it is saved where the
# agent writes the control plane's requests, and only when it changed, so
# nebula-relay-apply.path checks it again and applies it.
set -euo pipefail

URL=$1
TOKEN_FILE=/etc/nebula/relay-report-token
WANT=/var/lib/nebula/relay/relay.env
ANSWER=$(mktemp)
trap 'rm -f "$ANSWER"' EXIT

curl -fsS -m 15 -o "$ANSWER" -X POST -H "Authorization: Bearer $(cat "$TOKEN_FILE")" "$URL"
# Nothing back: a relay set by hand (NEBULA_RELAYS), kept as it is.
[ -s "$ANSWER" ] || exit 0
grep -q '^NEBULA_RELAY_TARGET=' "$ANSWER" || exit 0
if ! cmp -s "$ANSWER" "$WANT" 2> /dev/null; then
  install -m 600 -o nebula-agent -g nebula-agent "$ANSWER" "$WANT"
fi
