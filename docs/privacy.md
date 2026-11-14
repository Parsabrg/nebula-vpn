# Privacy policy

What a Nebula VPN server stores about the people who use it, for how long,
and what the apps (Android, Windows, Linux) send where. Written from the
code and checked against the live deployment on 2026-10-17; WARP, free mode
and the connection checks added from the code on 2026-11-14. If something
here stops being true, it is a bug in the software or in this page.

Nebula is self-hosted: whoever runs a Nebula server is the one holding this
data, and the one to ask about it. The terms of use are in
[terms.md](terms.md).

## Never collected

- The sites and addresses you visit, and the contents of your traffic. The
  servers' Xray and Hysteria2 keep no connection log; checked on the live
  server: no connection lines at all.
- Your DNS lookups.
- Your IP address. No database table has a column for it, and the web server keeps no access log.
- Your password (only a slow, salted Argon2id hash of it is stored), and
  one-time sign-in, activation and reset codes (only keyed digests).
- Private keys: your WireGuard key never leaves your device.

## Stored while you have an account

| What | Why |
|---|---|
| Email address, optional username | To sign in, and to send the emails you ask for |
| Password hash (Argon2id) | To check your password |
| Account state, device limit, data allowance, expiry | The limits your account has |
| Each device: the name you see in Devices, its platform (Android, Windows, Linux), the app version, and whether it is revoked | So you can see and revoke your devices |
| Sessions: which device, when it expires, when it was last used | To keep you signed in, and to sign a device out when it is revoked |
| Each device's VPN keys and credentials (WireGuard public key, Xray/Hysteria2 credentials, encrypted) | So the server lets that device connect |
| Traffic counters per device and protocol: bytes received and sent, and when they were last read | Data allowances and the usage you see; amounts only, never where they went |

## Kept for a limited time

| What | How long |
|---|---|
| Sign-in and email events (that a sign-in or email happened, its outcome; no IP address) | 90 days |
| Administrator actions (audit log) | 365 days |
| Server health and housekeeping records | 90 days |
| Encrypted nightly backups of the database (age-encrypted before they leave the server) | 30 days, then deleted by the nightly backup job |

A weekly job deletes what is older than this.

## What the apps send, and where

- **To your Nebula server:** sign-in, your device's registration and keys,
  the server list, and requests for a connection. When signed in, the app
  also asks the server which app version is current.
- **Through the VPN:** everything else your device sends while connected,
  except what you chose to let skip it (split tunnelling, Iranian sites,
  websites you listed). The app never sees its contents.
- **Through a relay** (a server listed as "<exit> via <relay>"): the relay
  sees your IP address and how much you send, as any network on the way
  does, but not your traffic, which stays encrypted from your device to the
  exit server. It does not log forwarded connections, and the exit server
  sees the relay's address instead of yours.
- **Through Cloudflare WARP** (the "Cloudflare WARP" server, or "Reach
  servers through WARP" in WARP's settings): the app's WARP client registers
  this device with Cloudflare's WARP service once, with a random key pair it
  makes on the device and no email, account or name. The keys stay on the
  device ("Get new WARP keys" replaces them). Cloudflare then carries your
  traffic: it sees your IP address and the addresses you connect to, and
  the contents of anything not already encrypted (most sites use HTTPS).
  Its own privacy policy for WARP applies to what it does with that.
  Through WARP to one of our servers, Cloudflare sees only that you reach
  that server, and the server sees a Cloudflare address instead of yours.
- **Through Psiphon** ("Leave outside Iran", Cloudflare WARP server only):
  WARP carries you to Psiphon's network and your traffic leaves from a
  Psiphon server outside Iran. Cloudflare sees only that you reach Psiphon;
  Psiphon sees where your traffic goes, but not your IP address, which it
  receives as a Cloudflare one. Psiphon's own privacy policy applies.
- **Through the DNS tunnel** (only when every other route has failed, once
  the app supports it): your traffic is split into DNS queries sent through
  public resolvers, often ones inside Iran, which pass them to the server.
  Their contents are encrypted (AES-256-GCM, then the VLESS Encryption tunnel
  inside); the resolvers see their volume and timing, and that they go to
  the tunnel's domain.
- **To GitHub:** if "Check for updates" is on, the app asks GitHub's public
  releases page for the newest version. GitHub sees your IP address, as for
  any download. When you install an update from the app, it
  downloads the release file and its signed checksum list from GitHub too.
- **To public DNS resolvers (Cloudflare 1.1.1.1, Google 8.8.8.8, Quad9
  9.9.9.9):** before a connection through Cloudflare, one lookup of
  `cloudflare-ech.com`, which every Cloudflare encrypted connection makes.
  It names no site you visit.
- **Subscriptions and links you add:** fetched from the address you gave;
  they stay on your device and are never sent to your Nebula server.
- **Free mode** (no account): the app fetches the free subscription, a
  public list of servers, from GitHub Pages (`parsabrg.github.io`), which
  sees your IP address as for any page. The servers in it are run by other
  people, not by Nebula: like any VPN server, whoever runs one can see your
  IP address and where your traffic goes. Use them for getting around a
  block, not for anything you would not want a stranger to see.
- **Connection checks:** while connecting and while connected, the app
  checks that the tunnel really carries data, with requests through it to
  `www.gstatic.com`, `speed.cloudflare.com` and `www.youtube.com`. Before a
  connection, it checks the device is online at all with one request each
  to `connectivitycheck.gstatic.com` and `checkip.amazonaws.com`, outside
  the VPN. None of them carries anything about you or your account.
- **Tools you start:** the speed test downloads from and uploads to
  `speed.cloudflare.com`; the leak test asks Cloudflare (`1.1.1.1`) which
  address your traffic leaves from; the clean-address scan connects to
  Cloudflare's addresses to time them. Each runs only when you start it.
- **Nothing else.** No analytics, no crash reporting, no advertising, no
  third-party SDKs. The app contains no Google Play Services or Firebase
  code (the QR scanner is open-source ZXing).

On the device, the app keeps your session, settings and the links you added,
in the platform's secure storage where they are secrets.

## Your choices

- See and revoke your devices under Devices.
- Turn off "Check for updates" in Settings.
- Get new WARP keys in Settings, Cloudflare WARP; or never use WARP, and
  nothing is sent to Cloudflare's WARP service.
- Change your password under Account. You stay signed in on this device;
  every other device is signed out.
- Delete your account under Account, with your password. This happens at
  once and cannot be undone:
  - **Deleted:** your email address, username and password; your devices'
    names and hardware IDs; every session, sign-in token, activation and
    password-reset link; your original account request; every email queued
    for or sent to your address; your permissions and server assignments.
  - **Removed from every server:** your WireGuard, Xray and Hysteria2
    credentials (within about a minute; an unreachable server removes them
    when it is back).
  - **Kept, under a random number that is not linked to you:** audit log
    entries and traffic totals. The deletion's own audit entry does not
    contain your address.
  - **Backups** still hold the old data until they expire, within 30 days.
  - An email already on its way when you delete may still arrive; its copy
    on the server expires within 24 hours and is never sent once deleted.
- An administrator can delete an account from the admin panel, for example
  when you ask them to. It is the same deletion as above; the audit entry
  names the administrator who did it.

## A server's operator

Running a VPN means your traffic leaves the internet from that server, so
the person running it is in a position of trust. Nebula is built so that
the software records as little as possible, but it cannot stop an operator
from changing what their own server does. Use a server run by someone you
trust, or run your own.
