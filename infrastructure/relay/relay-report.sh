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

post() {
  curl -fsS -m 8 -o "$ANSWER" -X POST -H "Authorization: Bearer $(cat "$TOKEN_FILE")" "$@" "$URL"
}
# The system resolver (Google's, from Iran) fails some evenings for a while:
# from 2026-11-21 14:00 UTC about half of these reports, and the relay showed
# "under maintenance" in the app though it worked. Then the name is looked
# up elsewhere -- the node's own resolver, then two public ones -- and
# pinned for this one request.
if ! post; then
  host=${URL#https://}
  host=${host%%/*}
  sent=0
  for server in "-p 5354 @127.0.0.1" "@1.1.1.1" "@9.9.9.9"; do
    # shellcheck disable=SC2086 # the port and server are two words
    address=$(dig +short +time=2 +tries=1 $server "$host" A 2> /dev/null | grep -Em1 '^[0-9.]+$') || continue
    if post --resolve "$host:443:$address"; then
      sent=1
      break
    fi
  done
  [ "$sent" = 1 ] || exit 1
fi
# Nothing back: a relay set by hand (NEBULA_RELAYS), kept as it is.
[ -s "$ANSWER" ] || exit 0
grep -q '^NEBULA_RELAY_TARGET=' "$ANSWER" || exit 0
if ! cmp -s "$ANSWER" "$WANT" 2> /dev/null; then
  install -m 600 -o nebula-agent -g nebula-agent "$ANSWER" "$WANT"
fi
