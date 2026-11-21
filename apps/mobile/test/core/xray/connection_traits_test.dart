import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_mobile/core/servers/server_repository.dart';
import 'package:nebula_mobile/core/storage/advanced_settings_store.dart';
import 'package:nebula_mobile/core/warp/warp_settings.dart';
import 'package:nebula_mobile/core/xray/xray_config.dart';

XrayClientResult _client({
  String transport = 'xhttp',
  String? flow,
  bool adBlock = false,
  bool relayed = false,
}) => XrayClientResult(
  clientId: 'c1',
  uuid: 'a1b2c3d4-0000-0000-0000-000000000000',
  serverAddress: '203.0.113.7',
  port: 443,
  sni: 'vpn.example.org',
  transport: transport,
  transportSecurity: 'tls',
  adBlock: adBlock,
  flow: flow,
  relayed: relayed,
);

void main() {
  final AdvancedSettings everything = AdvancedSettings.defaults.copyWith(
    muxEnabled: true,
    iranDirect: true,
    bypassDomains: <String>['bank.example'],
    fragment: FragmentSettings.defaults.copyWith(enabled: true),
    warp: const WarpSettings(throughWarp: true),
  );

  test('nothing on, nothing listed', () {
    expect(connectionTraits(_client(), AdvancedSettings.defaults), isEmpty);
  });

  test('each listed only where it takes effect', () {
    // VLESS over XHTTP: WARP carries the hello, so no split handshake.
    expect(connectionTraits(_client(), everything), <ConnectionTrait>{
      ConnectionTrait.warp,
      ConnectionTrait.iranDirect,
      ConnectionTrait.mux,
    });
    // Hysteria2 runs its own client: none of these reach it.
    expect(
      connectionTraits(_client(transport: 'hysteria'), everything),
      isEmpty,
    );
    expect(
      routesBypassSites(_client(transport: 'hysteria'), everything),
      false,
    );
    // Vision cannot be multiplexed; a relay in Iran is not reached through
    // WARP, so the hello is split instead.
    expect(
      connectionTraits(
        _client(transport: 'raw', flow: 'xtls-rprx-vision', relayed: true),
        everything,
      ),
      <ConnectionTrait>{ConnectionTrait.iranDirect, ConnectionTrait.fragment},
    );
    expect(
      connectionTraits(_client(adBlock: true), AdvancedSettings.defaults),
      <ConnectionTrait>{ConnectionTrait.adBlock},
    );
  });
}
