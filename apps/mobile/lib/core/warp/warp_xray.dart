import 'dart:io';

import '../wireguard/native_tunnel_channel.dart';
import 'desktop_aether.dart';
import 'warp_settings.dart';

/// Cloudflare WARP inside Xray-core (its MASQUE outbound) instead of the
/// Aether process: no process to start, no SOCKS hop, connected in about a
/// second and a half where Aether took 8-40 s on the same phone. Aether still
/// registers the device; Xray connects with that identity.
///
/// Only over HTTP/2: Cloudflare refuses Xray's HTTP/3 handshake (a TLS
/// handshake failure, also from outside Iran). The name in the TLS handshake
/// is the WARP settings' MASQUE SNI (www.cloudflare.com by default), as
/// Aether sends it; Xray's own default, cloudflareaccess.com, does not get
/// through from Iran.

/// The key Cloudflare's MASQUE endpoints present, the same for every device
/// (the `peers[0].public_key` of a MASQUE-enrolled registration). Xray
/// refuses an endpoint whose certificate carries another.
const String cloudflareMasquePublicKey =
    '-----BEGIN PUBLIC KEY-----\n'
    'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEIaU7MToJm9NKp8YfGxR6r+/h4mcG\n'
    '7SxI8tsW8OR1A5tv/zCzVbCRRh2t87/kxnP6lAy0lkr7qYwu+ox+k3dr6w==\n'
    '-----END PUBLIC KEY-----\n';

/// Where WARP is dialled when Aether has not recorded a gateway yet.
const String defaultWarpGateway = '162.159.198.1:443';

/// The parts of an Aether MASQUE identity Xray needs.
class WarpIdentity {
  const WarpIdentity({
    required this.privateKeyPem,
    required this.ipv4,
    this.ipv6,
    this.recentGateways = const <String>[],
  });

  /// The device's ECDSA P-256 key (PKCS#8 PEM) Cloudflare enrolled.
  final String privateKeyPem;
  final String ipv4;
  final String? ipv6;

  /// Gateways Aether last connected through, newest first.
  final List<String> recentGateways;

  /// The same identity with [gateway] tried first.
  WarpIdentity preferring(String gateway) => WarpIdentity(
    privateKeyPem: privateKeyPem,
    ipv4: ipv4,
    ipv6: ipv6,
    recentGateways: <String>[
      gateway,
      ...recentGateways.where((String g) => g != gateway),
    ],
  );
}

/// Whether this connect runs WARP inside Xray. Only plain WARP over MASQUE:
/// Psiphon ("Leave outside Iran") and WARP as the way in to a server still
/// need Aether. On Windows and Linux the gateway is routed around the tunnel
/// as a server's address is.
bool usesXrayWarp(WarpSettings settings) =>
    warpSupported &&
    settings.engine == WarpEngine.xray &&
    settings.protocol == WarpProtocol.masque &&
    !settings.leaveOutsideIran &&
    !settings.throughWarp;

/// Reads `warp-N-masque.toml` (and its `-lastconn` file) as Aether writes
/// them; null without a complete MASQUE identity.
WarpIdentity? parseWarpIdentity(String identity, {String? lastConnection}) {
  String? field(String name) => RegExp(
    '^$name\\s*=\\s*"([^"]*)"',
    multiLine: true,
  ).firstMatch(identity)?.group(1);
  final String? key = RegExp(
    r'^key_pem\s*=\s*"""\s*(-----BEGIN PRIVATE KEY-----[\s\S]*?-----END PRIVATE KEY-----)\s*"""',
    multiLine: true,
  ).firstMatch(identity)?.group(1);
  final String? ipv4 = field('ipv4');
  if (key == null ||
      ipv4 == null ||
      InternetAddress.tryParse(ipv4)?.type != InternetAddressType.IPv4) {
    return null;
  }
  final String? ipv6 = field('ipv6');
  final List<String> recent = <String>[
    if (lastConnection != null)
      for (final RegExpMatch m in RegExp(
        r'"([0-9.]+:[0-9]{1,5})"',
      ).allMatches(lastConnection))
        if (isValidWarpEndpoint(m.group(1)!)) m.group(1)!,
  ];
  return WarpIdentity(
    privateKeyPem: '${key.trim()}\n',
    ipv4: ipv4,
    ipv6: ipv6 != null && InternetAddress.tryParse(ipv6) != null ? ipv6 : null,
    recentGateways: recent,
  );
}

/// The identity of [settings]' slot, from Aether's folder, or null.
Future<WarpIdentity?> readWarpIdentity(WarpSettings settings) async {
  try {
    final Directory home = Platform.isAndroid
        ? Directory(await const NativeTunnelChannel().aetherDirectory())
        : aetherHome();
    final String base =
        '${home.path}${Platform.pathSeparator}warp-${settings.identity}-masque';
    final File identity = File('$base.toml');
    if (!await identity.exists()) {
      return null;
    }
    final File last = File('$base-lastconn.toml');
    return parseWarpIdentity(
      await identity.readAsString(),
      lastConnection: await last.exists() ? await last.readAsString() : null,
    );
  } on Object {
    // No channel (tests), no folder, unreadable: Aether carries WARP.
    return null;
  }
}

/// The gateway to dial, on port 443: MASQUE over HTTP/2 is TCP on 443,
/// while the port Aether records is often a QUIC one (8095, 4500, 8443...),
/// where a TCP connect gets nothing -- seen on Windows. The address is the
/// one pinned in WARP settings, else the newest Aether connected through,
/// else Cloudflare's first.
String warpGatewayFor(WarpSettings settings, WarpIdentity identity) {
  final String chosen =
      settings.endpoint ??
      (identity.recentGateways.isEmpty
          ? defaultWarpGateway
          : identity.recentGateways.first);
  return '${chosen.substring(0, chosen.lastIndexOf(':'))}:443';
}

/// The gateways worth knocking on before a connect, newest first, each
/// once, on port 443: Aether's recent ones, then Cloudflare's first.
List<String> warpGatewayCandidates(WarpIdentity identity, {int limit = 4}) {
  final List<String> hosts = <String>[];
  for (final String gateway in <String>[
    ...identity.recentGateways,
    defaultWarpGateway,
  ]) {
    final String host = gateway.substring(0, gateway.lastIndexOf(':'));
    if (!hosts.contains(host)) {
      hosts.add(host);
    }
  }
  return <String>[for (final String h in hosts.take(limit)) '$h:443'];
}

/// Opens a TCP connection to [gateway] ("ip:port"); true if it answered.
typedef GatewayKnock = Future<bool> Function(String gateway, Duration timeout);

Future<bool> knockTcp(String gateway, Duration timeout) async {
  final int colon = gateway.lastIndexOf(':');
  try {
    final Socket socket = await Socket.connect(
      gateway.substring(0, colon).replaceAll(RegExp(r'[\[\]]'), ''),
      int.parse(gateway.substring(colon + 1)),
      timeout: timeout,
    );
    socket.destroy();
    return true;
  } on Object {
    return false;
  }
}

/// The newest of [candidates] that answers a TCP connect within [timeout],
/// all knocked on at once; null if none does. A gateway that has gone away
/// costs [timeout] here, instead of a connect that carries nothing and a
/// retry through Aether's scan.
Future<String?> firstAnsweringGateway(
  List<String> candidates, {
  Duration timeout = const Duration(milliseconds: 1500),
  GatewayKnock knock = knockTcp,
}) async {
  final List<bool> answered = await Future.wait(<Future<bool>>[
    for (final String gateway in candidates) knock(gateway, timeout),
  ]);
  for (int i = 0; i < candidates.length; i++) {
    if (answered[i]) {
      return candidates[i];
    }
  }
  return null;
}

/// The Xray outbound that carries WARP.
Map<String, dynamic> xrayWarpOutbound(
  String tag,
  WarpSettings settings,
  WarpIdentity identity,
) {
  final String gateway = warpGatewayFor(settings, identity);
  final int colon = gateway.lastIndexOf(':');
  final String host = gateway
      .substring(0, colon)
      .replaceAll(RegExp(r'[\[\]]'), '');
  return <String, dynamic>{
    'tag': tag,
    'protocol': 'masque',
    'settings': <String, dynamic>{
      'address': host,
      'port': int.parse(gateway.substring(colon + 1)),
      'remoteDNS': <String>['1.1.1.1', '1.0.0.1'],
    },
    'streamSettings': <String, dynamic>{
      'network': 'masque',
      'security': 'tls',
      'tlsSettings': <String, dynamic>{
        'serverName': settings.masqueSni,
        'alpn': <String>['h2'],
        'fingerprint': settings.fingerprint == WarpFingerprint.firefox
            ? 'firefox'
            : 'chrome',
      },
      'masqueSettings': <String, dynamic>{
        'warp': <String, dynamic>{
          'privateKey': identity.privateKeyPem,
          'publicKey': cloudflareMasquePublicKey,
          // Both of the device's WARP addresses, whatever the gateway is
          // dialled over: with only IPv4 inside, every site the phone
          // reached over IPv6 failed ("no address to reach").
          'address': <String>[
            '${identity.ipv4}/32',
            if (identity.ipv6 != null) '${identity.ipv6}/128',
          ],
        },
      },
    },
  };
}
