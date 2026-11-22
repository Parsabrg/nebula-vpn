# macOS (and why not iOS)

Roadmap: *plan 9*. Status: macOS in progress; iOS dropped.

## iOS: dropped

A VPN on iOS can only be a Network Extension (`NEPacketTunnelProvider`).
Its entitlement is signed only for a paid Apple Developer Program
membership; a free Apple ID cannot sideload it, and TrollStore, which can,
does not run on current iOS. Even with the membership the app could not
reach people:

- **App Store:** Apple accepts VPN apps only from an *organization*
  account (a registered company with a D-U-N-S number), not an individual
  one, and Iran has no App Store.
- **TestFlight:** reviewed against the same rules; builds expire after 90
  days.
- **Ad Hoc:** only devices whose UDID is registered, 100 a year, a new build
  each time; and the builds stop opening when the membership ends.

iPhone and iPad users use an existing App Store client with their Nebula
subscription link instead (see "Use on iPhone or iPad" in the app). The
Flutter code itself would build for iOS (`flutter create --platforms=ios`)
if an organization account ever becomes possible.

## macOS: without a Network Extension

The Mac app is not for the Mac App Store, so it needs no Network Extension
and no paid membership. The tunnel works as on Linux:

- The bundled Xray (`tool/vendor_macos_runtime.sh`: the release's Apple
  silicon and Intel builds, pinned by SHA-256, joined with `lipo`) makes its
  own `utun188` and the system routes (`autoSystemRoutingTable`), and binds
  its own connections to the real interface (`autoOutboundsInterface`).
- A root helper (`lib/core/xray/macos_tunnel_config.dart`), started through
  macOS's administrator prompt (`osascript ... with administrator
  privileges`), runs it, points every network service's DNS at the tunnel
  and puts it all back on disconnect, when Xray exits, or when the app is
  gone.
- Proxy mode runs Xray as the user; the delay and download probes are the
  Linux ones.
- The app is not sandboxed and unsigned: the first launch needs right-click
  → Open (Gatekeeper).

CI (`.github/workflows/macos.yml`, GitHub's free macOS runner) analyzes,
tests, runs the tunnel end to end (`tool/macos_tunnel_smoke.sh`: a local
Xray server as the VPN server, traffic and DNS through the utun, routes and
DNS restored after) and builds the unsigned app.

### Left to do

- [ ] Hysteria2 (its release has macOS builds), WARP (Aether has macOS
      builds), WireGuard (wireguard-go under the same helper), the DNS
      tunnel (if CottenDNS has a macOS build).
- [ ] Kill switch (pf).
- [ ] Tray, window and app icon.
- [ ] ZIP or DMG on GitHub Releases from the Release workflow.
- [ ] One run on a real Mac: the windows, the administrator prompt, a
      connect to a real server.
