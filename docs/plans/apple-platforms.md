# iOS and macOS

Roadmap: *plan 9*. Status: planned, not started.

The goal is one repository and one Flutter app on Android, Windows, Linux,
iOS and macOS: the existing Dart code (UI, accounts, API, state) shared, a
native tunnel per Apple platform, builds on GitHub's macOS runners, and files
on GitHub Releases. App Store publication is not a goal.

## Constraints known up front

- **Tunnels on Apple platforms are Network Extensions** (`NEPacketTunnelProvider`).
  The Android engine (AndroidLibXrayLite with hev-socks5-tunnel in a
  `VpnService`) and the desktop helpers (Xray as a process, Wintun, nftables)
  do not carry over; each engine needs an Apple build linked into the
  extension.
- **A Network Extension needs a paid Apple Developer Program membership**
  ($99 a year). The free personal team cannot sign the Network Extension
  entitlement, so without the membership neither an iOS IPA nor a macOS app
  with a tunnel can be installed. Paying from Iran is a known obstacle, as for
  Google's developer verification (see `docs/sanctioned-services.md`).
- **No Mac is needed to build**: GitHub-hosted macOS runners build and sign.
  Testing needs a real iPhone and a real Mac; the simulator has no
  Network Extension tunnel.
- **iOS distribution outside the App Store** is limited to Ad Hoc builds for
  registered devices (up to 100 per year per device type) or TestFlight.
  macOS can be distributed as a Developer ID signed, notarised DMG.
- **The extension's memory limit on iOS** (about 50 MB) constrains which
  engines fit; Xray-core with large geo files is the known risk.

## Engines

| Engine | Apple build | Notes |
| --- | --- | --- |
| Xray-core (VLESS, REALITY, VMess, SS2022, XHTTP, MASQUE) | Go; LibXray builds an xcframework for iOS and macOS | Also carries WARP over MASQUE, which needs no Aether on these platforms |
| WireGuard | WireGuardKit (official, Swift + wireguard-go) | |
| Hysteria2 | Go; buildable with gomobile | To confirm in the extension's memory limit |
| Aether (WARP registration, Psiphon) | Rust | Only registration may be needed if WARP runs inside Xray |
| DNS tunnel (CottenDNS) | Go | Last-resort route; lowest priority |

## Checklist

### Phase 1 – Repository audit and compatibility
- [ ] Inspect `apps/mobile/pubspec.yaml`: which plugins support iOS and macOS; isolate Android-only ones.
- [ ] Identify Windows/Linux-specific native integrations.
- [ ] Audit `flutter_v2ray_client`, WireGuard, LibXray, Hysteria2 and the DNS tunnel for Apple builds.
- [ ] List architecture-specific native binaries and libraries.
- [ ] Document the native changes required; existing platforms unaffected.

Deliverable: Apple platform compatibility report.

### Phase 2 – Flutter platform preparation
- [ ] Enable the iOS and macOS targets; bundle identifiers; minimum OS versions.
- [ ] Verify routing, Riverpod state, authentication, API calls and secure storage.
- [ ] Adapt file handling, permissions and lifecycle; handle unsupported features gracefully.
- [ ] `flutter analyze` and the existing tests.

Deliverable: the app compiles for iOS and macOS.

### Phase 3 – Common VPN platform interface
- [ ] A shared Dart tunnel interface; UI separated from platform tunnels.
- [ ] Apple MethodChannel: connect, disconnect, status and traffic events, configuration transfer, errors.
- [ ] Android, Windows and Linux adapters unchanged.

Deliverable: one tunnel abstraction across all platforms.

### Phase 4 – iOS tunnel
- [ ] Runner project; Packet Tunnel extension target; `NEPacketTunnelProvider` in Swift.
- [ ] Entitlements and provisioning profiles.
- [ ] Configuration management and secure storage; app ↔ extension communication.
- [ ] Lifecycle, status reporting, DNS, IPv4 and IPv6 routing.
- [ ] Background execution, reconnection, VPN authorisation.

Deliverable: a working iOS tunnel extension.

### Phase 5 – macOS tunnel
- [ ] Runner project; Packet Tunnel extension target; `NEPacketTunnelProvider` in Swift.
- [ ] Entitlements, signing and provisioning.
- [ ] Configuration and credential storage; app ↔ extension communication.
- [ ] Lifecycle, DNS, routing, status; restart and reconnection; permissions.

Deliverable: a working macOS tunnel extension.

### Phase 6 – Engines
- [ ] WireGuard: WireGuardKit in both extensions; configuration conversion; routing, DNS, reconnect.
- [ ] Xray: LibXray for iOS and macOS architectures; configuration conversion; lifecycle; VLESS and REALITY; DNS and routing.
- [ ] Hysteria2: Apple build if feasible; connectivity and traffic.
- [ ] DNS tunnel: port if feasible; resolution and routing.

Deliverable: protocol support with documented compatibility.

### Phase 7 – CI
- [ ] `.github/workflows/apple.yml` on GitHub-hosted macOS runners: Flutter, dependencies, Xcode.
- [ ] Analysis and tests; iOS and macOS builds including the extensions.
- [ ] Optional signing from GitHub secrets.
- [ ] iOS artifact; macOS DMG or ZIP; attached to the release on version tags.
- [ ] Existing workflows unaffected.

Deliverable: automated Apple builds.

### Phase 8 – Signing and distribution
- [ ] Apple Developer Program membership.
- [ ] Certificates and profiles; iOS Ad Hoc for registered devices.
- [ ] macOS Developer ID signing and notarisation; Network Extension entitlements verified.
- [ ] Signed DMG and IPA on GitHub Releases.
- [ ] Installation instructions and their limits for both platforms.

Deliverable: distribution through GitHub without the App Store.

### Phase 9 – Testing
- [ ] iOS, on a real iPhone: authorisation, WireGuard, Xray/VLESS/REALITY, DNS, IPv4 and IPv6, recovery, backgrounding, restart, reconnect, no DNS or traffic leaks.
- [ ] macOS, on a real Mac: the same, plus restart, permissions, signed installation, notarisation and Gatekeeper.
- [ ] Regression: Android, Windows, Linux, automated tests, API compatibility.

A protocol is listed as supported on a platform only after it has been tested on a real device.

### Phase 10 – Documentation
- [ ] README and supported platforms; iOS and macOS installation; build requirements.
- [ ] Workflows, signing and provisioning; protocols per platform; known limitations.

## Rules for the work

1. The Flutter app is extended, not rewritten.
2. Android, Windows and Linux keep working; the existing tests stay green.
3. No Android engine is assumed to work on Apple platforms.
4. Tunnels use Apple's Network Extension framework.
5. Each engine's Apple build is verified before it is integrated.
6. Configurations and credentials stay in secure storage.
7. Apple builds run on GitHub Actions.
8. Changes land in small, separate pull requests.
9. Production server behaviour does not change for the port unless required.
