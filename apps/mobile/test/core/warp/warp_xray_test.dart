import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_mobile/core/free/free_mode.dart';
import 'package:nebula_mobile/core/storage/advanced_settings_store.dart';
import 'package:nebula_mobile/core/warp/warp_settings.dart';
import 'package:nebula_mobile/core/warp/warp_xray.dart';
import 'package:nebula_mobile/core/xray/local_proxy.dart';
import 'package:nebula_mobile/core/xray/xray_config.dart';

// A made-up identity in the layout Aether writes; the key is not a real one.
// The PEM markers are assembled so secret scanners do not take it for one.
const String _begin =
    '-----BEGIN '
    'PRIVATE KEY-----';
const String _end =
    '-----END '
    'PRIVATE KEY-----';
const String _identityToml =
    '''
device_id = "d"
access_token = "t"
cert_pem = """
-----BEGIN CERTIFICATE-----
AAAA
-----END CERTIFICATE-----
"""
key_pem = """
$_begin
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgAAAA
$_end
"""
ipv4 = "172.16.0.2"
ipv6 = "2606:4700:110:8a36::2"
''';

const String _lastConnection = '''
recent = [
    "162.159.198.35:443",
    "162.159.199.81:443",
]
''';

const LocalProxy _localProxy = LocalProxy(
  port: 20443,
  username: 'n0011223344556677',
  password: '00112233445566778899aabbccddeeff',
);

void main() {
  test('an Aether identity gives the key, addresses and recent gateways', () {
    final WarpIdentity identity = parseWarpIdentity(
      _identityToml,
      lastConnection: _lastConnection,
    )!;
    expect(identity.privateKeyPem, startsWith(_begin));
    expect(identity.privateKeyPem, endsWith('$_end\n'));
    expect(identity.ipv4, '172.16.0.2');
    expect(identity.ipv6, '2606:4700:110:8a36::2');
    expect(identity.recentGateways, <String>[
      '162.159.198.35:443',
      '162.159.199.81:443',
    ]);
  });

  test('an identity without a key or address is none', () {
    expect(parseWarpIdentity('ipv4 = "172.16.0.2"'), isNull);
    expect(
      parseWarpIdentity(_identityToml.replaceAll('172.16.0.2', 'x')),
      isNull,
    );
  });

  test('the gateway: pinned, else the newest, else the default', () {
    final WarpIdentity seen = parseWarpIdentity(
      _identityToml,
      lastConnection: _lastConnection,
    )!;
    final WarpIdentity fresh = parseWarpIdentity(_identityToml)!;
    expect(warpGatewayFor(WarpSettings.defaults, seen), '162.159.198.35:443');
    expect(warpGatewayFor(WarpSettings.defaults, fresh), defaultWarpGateway);
    expect(
      warpGatewayFor(const WarpSettings(endpoint: '162.159.192.1:2408'), seen),
      '162.159.192.1:443',
    );
    // A QUIC port Aether recorded is not where HTTP/2 is served.
    expect(
      warpGatewayFor(
        WarpSettings.defaults,
        parseWarpIdentity(
          _identityToml,
          lastConnection: 'recent = ["162.159.198.176:8095"]',
        )!,
      ),
      '162.159.198.176:443',
    );
  });

  test('WARP mode with an identity runs in Xray and starts no Aether', () {
    final WarpIdentity identity = parseWarpIdentity(
      _identityToml,
      lastConnection: _lastConnection,
    )!;
    final Map<String, dynamic> config = jsonDecode(
      renderXrayClientConfigJson(
        warpClient,
        localProxy: _localProxy,
        settings: AdvancedSettings.defaults.copyWith(
          warp: const WarpSettings(engine: WarpEngine.xray),
        ),
        warpIdentity: identity,
      ),
    ) as Map<String, dynamic>;
    expect(config.containsKey('nebulaAether'), isFalse);
    final Map<String, dynamic> proxy =
        (config['outbounds'] as List<dynamic>).first as Map<String, dynamic>;
    expect(proxy['tag'], 'proxy');
    expect(proxy['protocol'], 'masque');
    expect(
      (proxy['settings'] as Map<String, dynamic>)['address'],
      '162.159.198.35',
    );
    final Map<String, dynamic> stream =
        proxy['streamSettings'] as Map<String, dynamic>;
    final Map<String, dynamic> tls =
        stream['tlsSettings'] as Map<String, dynamic>;
    // What gets through from Iran: HTTP/2, Aether's server name, Chrome.
    expect(tls['alpn'], <String>['h2']);
    expect(tls['serverName'], defaultMasqueSni);
    expect(tls['fingerprint'], 'chrome');
    final Map<String, dynamic> warp =
        (stream['masqueSettings'] as Map<String, dynamic>)['warp']
            as Map<String, dynamic>;
    expect(warp['publicKey'], cloudflareMasquePublicKey);
    expect(warp['address'], <String>[
      '172.16.0.2/32',
      '2606:4700:110:8a36::2/128',
    ]);
  });

  test('without an identity, WARP mode is still Aether', () {
    final Map<String, dynamic> config = jsonDecode(
      renderXrayClientConfigJson(
        warpClient,
        localProxy: _localProxy,
        settings: AdvancedSettings.defaults.copyWith(
          warp: const WarpSettings(engine: WarpEngine.xray),
        ),
      ),
    ) as Map<String, dynamic>;
    expect(config.containsKey('nebulaAether'), isTrue);
  });

  test('the engine choice is saved and read back', () {
    const WarpSettings xray = WarpSettings(engine: WarpEngine.xray);
    expect(
      WarpSettings.fromJsonString(jsonEncode(xray.toJson())).engine,
      WarpEngine.xray,
    );
    expect(WarpSettings.fromJsonString('{}').engine, WarpEngine.aether);
  });
}
