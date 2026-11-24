import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_mobile/core/servers/server_repository.dart';
import 'package:nebula_mobile/core/storage/advanced_settings_store.dart';
import 'package:nebula_mobile/core/wireguard/wireguard_config.dart';
import 'package:nebula_mobile/core/xray/local_proxy.dart';
import 'package:nebula_mobile/core/xray/xray_config.dart';

const LocalProxy _localProxy = LocalProxy(
  port: 20443,
  username: 'n0011223344556677',
  password: '00112233445566778899aabbccddeeff',
);

const XrayClientResult _plain = XrayClientResult(
  clientId: 'client-1',
  uuid: 'a1b2c3d4-0000-0000-0000-000000000000',
  serverAddress: 'ams-1.example.test',
  port: 8443,
  sni: 'ams-1.example.test',
  adBlock: false,
  transport: 'xhttp',
  transportSecurity: 'tls',
);

const WireGuardPeerResult _peer = WireGuardPeerResult(
  peerId: 'peer-1',
  assignedAddress: '10.77.0.2',
  serverPublicKey: 'server-key',
  listenPort: 51820,
  publicEndpoint: 'vpn.example.org:51820',
  clientDns: '10.77.0.1',
  clientAllowedIps: '0.0.0.0/0',
  persistentKeepaliveSeconds: 25,
);

Map<String, dynamic> _xray(AdvancedSettings settings) => jsonDecode(
  renderXrayClientConfigJson(
    _plain,
    localProxy: _localProxy,
    settings: settings,
  ),
) as Map<String, dynamic>;

void main() {
  test('Block ads turns a plain Xray profile into a blocking one', () {
    final Map<String, dynamic> off = _xray(AdvancedSettings.defaults);
    final Map<String, dynamic> on = _xray(
      AdvancedSettings.defaults.copyWith(blockAds: true),
    );

    expect(jsonEncode(off['outbounds']), isNot(contains('ad-block')));
    expect(jsonEncode(on['outbounds']), contains('ad-block'));
    expect((on['dns'] as Map<String, dynamic>)['servers'], <String>[
      adBlockResolver,
    ]);
  });

  test('Block ads gives WireGuard the filtering resolver', () {
    String dns(bool blockAds) => renderWireGuardConfig(
      privateKeyBase64: 'private-key',
      peer: _peer,
      blockAds: blockAds,
    ).split('\n').firstWhere((String l) => l.startsWith('DNS = '));

    expect(dns(false), 'DNS = 10.77.0.1');
    expect(dns(true), 'DNS = $adBlockResolver');
  });

  test('flipping Block ads reconnects, like the routing switches', () {
    expect(
      routingChanged(
        AdvancedSettings.defaults,
        AdvancedSettings.defaults.copyWith(blockAds: true),
      ),
      isTrue,
    );
  });
}
