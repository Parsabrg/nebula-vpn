import 'dart:convert';
import 'dart:io';

import '../servers/server_repository.dart';
import 'dns_tunnel_sync.dart';

/// The DNS tunnel as one more protocol on its server. Its credential is the
/// server's VLESS Encryption one: the tunnel only carries that connection.
/// Starts with `vless-enc`, so Automatic leaves it out
/// ([AvailableProfile.manualOnly]); listed last ([orderedProfiles]).
const String kDnsTunnelProfileCode = 'vless-enc-dns';
const String _kVlessEncProfileCode = 'vless-enc';

/// The profile the server knows for [code].
String credentialProfileCode(String code) =>
    code == kDnsTunnelProfileCode ? _kVlessEncProfileCode : code;

/// [servers] with the DNS tunnel offered on the server it reaches, when
/// that server lists VLESS Encryption.
List<AvailableServer> withDnsTunnelProfile(
  List<AvailableServer> servers,
  DnsTunnelDetails? tunnel,
) {
  if (tunnel == null) {
    return servers;
  }
  return <AvailableServer>[
    for (final AvailableServer server in servers)
      if (server.code != tunnel.serverCode)
        server
      else
        AvailableServer(
          code: server.code,
          displayName: server.displayName,
          publicHost: server.publicHost,
          maintenance: server.maintenance,
          profiles: <AvailableProfile>[
            ...server.profiles,
            for (final AvailableProfile profile in server.profiles)
              if (profile.code == _kVlessEncProfileCode)
                AvailableProfile(
                  code: kDnsTunnelProfileCode,
                  displayName: 'DNS tunnel (slow, last resort)',
                  protocolId: profile.protocolId,
                  protocolCode: profile.protocolCode,
                  adBlock: false,
                ),
          ],
        ),
  ];
}

/// The rendered Xray config, pointed at the DNS tunnel's loopback port and
/// carrying what the plugin needs to start the tunnel first.
String withDnsTunnelConfig(
  String xrayConfigJson,
  DnsTunnelDetails details, {
  required int port,
  required String resolvers,
}) {
  final Map<String, dynamic> config =
      jsonDecode(xrayConfigJson) as Map<String, dynamic>;
  final Map<String, dynamic> proxy =
      (config['outbounds'] as List<dynamic>).first as Map<String, dynamic>;
  final Map<String, dynamic> next =
      ((proxy['settings'] as Map<String, dynamic>)['vnext'] as List<dynamic>)
              .first
          as Map<String, dynamic>;
  next['address'] = '127.0.0.1';
  next['port'] = port;
  config['nebulaDnsTunnel'] = <String, Object>{
    'config': renderDnsTunnelConfig(details, port),
    'resolvers': resolvers,
    'port': port,
  };
  return jsonEncode(config);
}

/// The DNS tunnel's client config (CottenDNS TOML) for the details the
/// server gave. Only what differs from the engine's defaults, plus what its
/// Android notes ask to be explicit.
///
/// TCP mode: every connection to [port] on loopback reaches the server's
/// VLESS Encryption inbound, which Xray's outbound then dials.
String renderDnsTunnelConfig(
  DnsTunnelDetails details,
  int port, {
  int? scanParallelism,
}) {
  String quote(String value) =>
      '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  String list(Iterable<String> values) => '[${values.map(quote).join(', ')}]';
  return <String>[
    'TUNNEL_MODE = "legacy"',
    // The first name; the rest are tried in turn when it stops answering.
    'DOMAINS = ${list(details.domains.take(1))}',
    'STANDBY_DOMAINS = ${list(details.domains.skip(1))}',
    'DATA_ENCRYPTION_METHOD = ${details.encryptionMethod}',
    'ENCRYPTION_KEY = ${quote(details.key)}',
    'PROTOCOL_TYPE = "TCP"',
    'LISTEN_IP = "127.0.0.1"',
    'LISTEN_PORT = $port',
    'RESOLVER_IP_MODE = "auto"',
    'STARTUP_MODE = "resolvers"',
    'TERMINAL_UI = "plain"',
    'FAST_CONNECT = true',
    'LOG_TO_FILE = false',
    'LOG_LEVEL = "INFO"',
    // A resolver test: one try per size and a short timeout (defaults 3
    // tries, 2 s; 4 resolvers took 80 s, MCI 2026-11-06).
    if (scanParallelism != null) ...<String>[
      'MTU_TEST_RETRIES_RESOLVERS = 1',
      'MTU_TEST_TIMEOUT_RESOLVERS = 1.5',
      'MTU_TEST_PARALLELISM_RESOLVERS = $scanParallelism',
    ],
    '',
  ].join('\n');
}

/// The IPv4 addresses among [resolvers] (one per line, `ip`, `ip:port` or
/// `[ipv6]:port`), each once, at most 64: on Windows and Linux the engine
/// runs outside the VPN and these leave by the physical gateway.
List<String> dnsTunnelResolverIpv4s(String resolvers) {
  final Set<String> found = <String>{};
  for (final String raw in resolvers.split(RegExp(r'[\s,]+'))) {
    final String entry = raw.trim();
    if (entry.isEmpty || entry.startsWith('[') || entry.startsWith('#')) {
      continue;
    }
    final String host = entry.split(':').first;
    final InternetAddress? address = InternetAddress.tryParse(host);
    if (address != null && address.type == InternetAddressType.IPv4) {
      found.add(address.address);
    }
    if (found.length == 64) {
      break;
    }
  }
  return found.toList();
}
