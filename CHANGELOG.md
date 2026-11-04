# Changelog

Releases of the apps are on the [releases page](https://github.com/Parsabrg/vpn/releases),
each with its full notes. A server updates to the same tags:
`sudo ./install.sh --update`. Server-side changes take effect when a server is
updated (`install.sh` rerun, or the deploy in `docs/runbooks/deployment.md`).

## Unreleased

### Apps
- WireGuard connects from the peer the phone already holds, as an Xray connect starts
  from its saved credential: no request to the server first. A saved peer that does
  not answer is dropped and a fresh one asked for, once. Disconnect no longer gives
  the peer back; sign-out, an admin, or the account running out removes it.

### Admin panel
- Admins page (owners only): add an admin with a one-time password, change a role
  (owner, operator, auditor), disable or re-enable, and see or end their sessions.
  Each change needs a fresh code and is audited. You cannot change or disable
  yourself there, so a deployment always keeps an owner.
- Passkeys: add one on the Security page (fingerprint, face or a security key), then
  sign in with it in place of the 6-digit code. Changes that need a fresh code still
  ask for the code. Needs a current browser.

### Servers
- DNS inside tunnels works again on servers with Xray 26.10: its default policy blocked
  the redirect to the server's own resolver, so pages did not load and the app kept
  reconnecting. The agent now allows exactly that target.
- A device's server list names the relays of the servers it holds a credential on, so the
  app no longer ends a relay tunnel with "Your access to this server has ended".
- Relays: a joined server can forward chosen ports to another server, and the app
  lists it as a server of its own ("Germany via Tehran") with the device's existing
  credential on the exit. Forwarded by the kernel, never logged; listed as under
  maintenance while the relay cannot reach the exit. Off until the owner sets it up
  (`docs/runbooks/relay.md`).
- New installs also answer on port 443: the panel, API and XHTTP on TCP 443 (nginx picks
  the site by name, so rate limits and the admin allowlist still see real addresses),
  Hysteria2 on UDP 443. The old ports stay open and listed after the 443 ones. Existing
  servers keep their ports until the owner turns it on (`docs/runbooks/port-443.md`).
- VLESS + REALITY (Vision on raw TCP, and XHTTP): no domain or certificate needed; a
  probe without the key sees another site's TLS. Off until the owner turns it on with
  `install.sh --configure` (`docs/runbooks/vless-reality.md`). The apps read it from the
  server as they already read REALITY links.
- Backup routes per account: with `NEBULA_API_ROUTES_PER_ACCOUNT=k` each account is told
  only k of the API's routes (a stable share that keeps the route it asked through), so
  one leaked account does not give away every route. Unset, everyone gets all, as before.
- Hysteria2 port hopping: new installs also answer Hysteria2 on UDP 20000-50000,
  and the apps move between those ports every 30 s, so one blocked port does not end
  the connection. Existing servers are unchanged until their owner turns it on
  (`docs/runbooks/hysteria-port-hopping.md`).

## 0.1.34 — 2026-11-03

### Apps
- Disconnect is instant: Off as soon as the tunnel is down, the server told after. The
  checks after a connect run together ("Protected" in about half the time), and the
  main button presses in, ticks and ignores an accidental second tap.
- Your links and subscriptions read `vmess://` links (WebSocket, XHTTP, gRPC or raw TCP,
  with or without TLS, and raw TCP dressed as HTTP), and VLESS Encryption links. A
  subscription that skipped 9 of its links now skips none of the kinds Xray can run.
- Account: change your password, or delete your account. Deletion removes everything
  that names you, and your VPN access on every server; see docs/privacy.md.
- Releases are built on GitHub from the release tag, with build attestations
  (`gh attestation verify <file> -R Parsabrg/vpn`); APKs and the manifest are still
  signed by the maintainer.
- Signing in tells the phone's password manager it worked, so it offers to save the
  password, or to update a saved one that changed; a refused password is never saved.
- A refused token refresh (rate limit, server busy) no longer disconnects the VPN (#20).

### Servers
- Admin panel: buttons and tiles press in under the pointer, and a menu link marks itself
  at once while its page loads, so no click looks lost.
- Admin panel: Server health and Security no longer wait for the servers' agents before
  showing; Server health fills each card in when its agent answers, and again every
  30 seconds.
- Faster control plane: calls to a server's agent reuse one kept-alive connection instead
  of a new TLS handshake each (about a second each to Tehran), and the panel and API
  are served over HTTP/2. Update the agents before the API (the agent keeps idle
  connections 120 s, the API 60 s).
- Admin panel: "All 20 protocols" instead of twenty chips, deleted accounts named as such in
  the audit log, and the user page's Grant all / Assign all show that they are working.
- Admin panel polish: one protocol picker on Permissions, protocols as chips, a user's
  actions in one row, and a tidier account summary.
- Admins change their own password (every other session of theirs is signed out) and
  move to a new authenticator (the old one works until the new one is confirmed) from
  Security. Needs migration 0020, applied by the deploy.
- Security no longer says reconciliation is clean while a server's agent cannot be
  reached; it names the server instead.
- Admin panel: Permissions shows one row per user, with the protocols they can use.
- Server health reloads its reconciliation history by itself after "Run reconciliation
  now" or "Check again".
- Admin panel: give every user a server (from its card on Server health) or a protocol
  (from Permissions) in one step.
- Admin panel: a pending request whose email or username an existing account already has
  is marked in the list, before Approve would refuse it.
- Admin panel: correct a user's email or username from their page. A refusal after the
  authenticator code is asked for now shows its reason instead of vanishing.
- Admin panel: after approving or rejecting, a note above the list says what was done
  (the row itself leaves the list).
- Admin panel: delete a user (the same strict deletion as the app's own) and send an
  account's activation email again, from the user's page.
- Audit log names who and what: the admin's or user's email, the server's or device's
  name, instead of an id.
- Admin authenticator setup shows a QR code to scan, beside the key.
- Admin panel: signing in again returns to the page you were opening; expiry has
  +1 month, +3 months and +1 year; the pairing link has a Copy button; refusing or
  removing confirms with a red button; the reject note is labelled as admin-only.
- Admin panel speaks plainly: states, audit events, email templates and every filter
  show words instead of codes; audit rows link to the user or server they are about.
- Admin panel redesign to match the app: its dark palette and Geist type, a menu that
  marks the page you are on, and tables that turn into cards on a phone.
- Admin panel fixes from a full sweep: times show in your own time zone (labelled) with
  no browser error; the user page's one-click fixes ask for the authenticator code;
  Security flags a missing backup and an old agent certificate and lists the
  control-plane CA; "All in sync" no longer shows beside an unreachable agent; a
  proper not-found page.
- The agent's Xray config sets the outbound's IPv4-only resolving in `sockopt`, where
  Xray 26.10 wants it (no deprecation warning; same behaviour).
- `infrastructure/check-protocols.py` proves every protocol a server offers carries
  traffic; the install test runs it after every fresh install.
- Enrolment sends the server's WireGuard range: before, no enrolled server had one,
  and WireGuard on it could give no device an address.
- Admin panel: an action refused because the session is no longer accepted signs out and
  opens the sign-in page, instead of leaving pages whose buttons all fail.
- Approving an account request whose email or username is taken says so (409) instead of
  failing, and a server error no longer leaves the admin panel refusing every later
  action as "session ended".
- Agents trust a CA of the control plane's own, which signs nothing else: no server's
  certificate, old ones included, can call another server's agent. New installs use it
  from the start; existing ones move over with `docs/runbooks/agent-certificates.md`.
- Prometheus metrics for the API and the agent on the server's loopback, and a Grafana
  dashboard (`docs/runbooks/metrics.md`).
- Audit log export as a hash chain (panel: Audit log → Export); `nebula-api audit-verify`
  checks an export, and that a later one still contains an earlier one unchanged.
- `NEBULA_ADMIN_ALLOW` limits the admin panel and admin API to listed addresses.
- `sudo ./install.sh --update` moves a server to the newest release tag, never
  backwards, and shows what changed.
- Login and password-reset limits fit many users behind one shared address (#21).
- Fresh installs: WireGuard clients reach the internet (#22); paths, gRPC name and
  Hysteria2 decoy differ per install (#24); fail2ban, automatic security updates
  and swap (#25); the backup key leaves the server and off-site backups are
  offered (#26).
- Agent certificates are for server use only, the control plane's for client use (#23).
- Admin panel: Content-Security-Policy and Permissions-Policy (#27).
- Xray 26.10.21 on servers (26.9.30 was a pre-release); a rerun of `install.sh` upgrades
  an older Xray and never replaces a newer one. WireGuard range set at install, /20 by
  default (#29).

## 0.1.33 — 2026-10-30

The first release from this repository.

- Stalled connections are caught in about 20 seconds by a small real download.
- Protocol test with download speed on Windows and Linux.
- Several servers on one account work side by side.

Releases up to 0.1.32 came from the private development repository.
