import 'package:flutter/services.dart';

import 'dns_tunnel_sync.dart';

/// The DNS tunnel's client config (CottenDNS TOML) for the details the
/// server gave. Only what differs from the engine's defaults, plus what its
/// Android notes ask to be explicit.
///
/// TCP mode: every connection to [port] on loopback reaches the server's
/// VLESS Encryption inbound, which Xray's outbound then dials.
String renderDnsTunnelConfig(DnsTunnelDetails details, int port) {
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
    '',
  ].join('\n');
}

/// Asks the engine which of [resolvers] (one address per line) carry a
/// test through the tunnel. Android only; the scan uses the real network
/// even while connected, since the app is outside its own VPN.
Future<List<String>> scanDnsTunnelResolvers(
  DnsTunnelDetails details,
  String resolvers, {
  MethodChannel channel = const MethodChannel('org.nebulavpn/wireguard_tunnel'),
}) async {
  final List<Object?>? valid = await channel.invokeMethod<List<Object?>>(
    'dnsTunnelScan',
    <String, String>{
      // The scan opens no listener; any valid port will do.
      'config': renderDnsTunnelConfig(details, 1),
      'resolvers': resolvers,
    },
  );
  return (valid ?? const <Object?>[]).whereType<String>().toList();
}
