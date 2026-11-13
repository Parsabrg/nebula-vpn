import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_mobile/core/free/free_mode.dart';
import 'package:nebula_mobile/core/servers/server_repository.dart';
import 'package:nebula_mobile/core/storage/advanced_settings_store.dart';
import 'package:nebula_mobile/core/warp/warp_settings.dart';
import 'package:nebula_mobile/core/xray/local_proxy.dart';
import 'package:nebula_mobile/core/xray/xray_config.dart';

const LocalProxy _localProxy = LocalProxy(
  port: 20443,
  username: 'n0011223344556677',
  password: '00112233445566778899aabbccddeeff',
);

const XrayClientResult _reality = XrayClientResult(
  clientId: 'c1',
  uuid: 'a1b2c3d4-0000-0000-0000-000000000000',
  serverAddress: '203.0.113.7',
  port: 443,
  sni: 'www.speedtest.net',
  transport: 'raw',
  transportSecurity: 'reality',
  adBlock: false,
  flow: 'xtls-rprx-vision',
  realityPublicKey: 'key',
  realityShortId: '0d14',
);

Map<String, dynamic> _render(XrayClientResult result, WarpSettings warp) =>
    jsonDecode(
          renderXrayClientConfigJson(
            result,
            localProxy: _localProxy,
            settings: AdvancedSettings.defaults.copyWith(warp: warp),
          ),
        )
        as Map<String, dynamic>;

void main() {
  group('Aether arguments', () {
    test('default to MASQUE over HTTP/2 with Chrome, the shape that works', () {
      final List<String> args = aetherArguments(WarpSettings.defaults, 20444);
      expect(args.sublist(0, 4), <String>[
        '--bind',
        '127.0.0.1:20444',
        '--protocol',
        'masque',
      ]);
      expect(
        args,
        containsAllInOrder(<String>[
          '--masque-sni',
          'www.cloudflare.com',
          '--h2',
        ]),
      );
      expect(args, contains('--enable-ech-grease'));
      expect(args, isNot(contains('--noize')));
      expect(
        args,
        containsAllInOrder(<String>['--masque-config', 'warp-0-masque.toml']),
      );
    });

    test('carry each choice, and new keys move the identity files', () {
      final List<String> args = aetherArguments(
        const WarpSettings(
          protocol: WarpProtocol.warpInWarp,
          scan: WarpScan.ironclad,
          obfuscation: WarpObfuscation.gfw,
          fingerprint: WarpFingerprint.firefox,
          ipVersion: WarpIpVersion.both,
          endpoint: '162.159.192.1:2408',
          quickReconnect: false,
          identity: 3,
        ),
        20444,
      );
      expect(
        args,
        containsAllInOrder(<String>['--protocol', 'gool', '--gool-classic']),
      );
      expect(args, containsAllInOrder(<String>['--noize', 'gfw']));
      expect(
        args,
        containsAllInOrder(<String>['--peer', '162.159.192.1:2408']),
      );
      expect(args, containsAllInOrder(<String>['--ip', 'both']));
      // WireGuard in WireGuard: no MASQUE options.
      expect(args, isNot(contains('--masque-sni')));
      expect(args, contains('--disable-extension-permutation'));
      expect(args, contains('--no-quick-reconnect'));
      expect(args, containsAllInOrder(<String>['--config', 'warp-3.toml']));
    });
  });

  group('WARP settings', () {
    test('round-trip, and fall back field by field on bad values', () {
      const WarpSettings custom = WarpSettings(
        transport: WarpTransport.http3,
        fingerprint: WarpFingerprint.go,
        masqueSni: 'consumer-masque.cloudflareclient.com',
        throughWarp: true,
      );
      expect(WarpSettings.fromJsonString(jsonEncode(custom.toJson())), custom);
      final WarpSettings bad = WarpSettings.fromJsonString(
        jsonEncode(<String, Object?>{
          'protocol': 'nonsense',
          'masqueSni': '1.2.3.4',
          'endpoint': '1.2.3.4',
          'throughWarp': true,
        }),
      );
      expect(bad.protocol, WarpProtocol.masque);
      expect(bad.masqueSni, defaultMasqueSni);
      expect(bad.endpoint, isNull);
      expect(bad.throughWarp, isTrue);
      expect(WarpSettings.fromJsonString('{not json'), WarpSettings.defaults);
    });

    test('validate an endpoint and a server name', () {
      expect(isValidWarpEndpoint('162.159.192.1:443'), isTrue);
      expect(isValidWarpEndpoint('[2606:4700:d0::a29f:c001]:2408'), isTrue);
      expect(isValidWarpEndpoint('162.159.192.1'), isFalse);
      expect(isValidWarpEndpoint('example.com:443'), isFalse);
      expect(isValidMasqueSni('www.cloudflare.com'), isTrue);
      expect(isValidMasqueSni('1.1.1.1'), isFalse);
      expect(isValidMasqueSni('localhost'), isFalse);
    });
  });

  group('the tunnel config', () {
    test('WARP mode dials Aether and carries its run', () {
      final Map<String, dynamic> config = _render(
        warpClient,
        WarpSettings.defaults,
      );
      final Map<String, dynamic> proxy =
          (config['outbounds'] as List<dynamic>).first as Map<String, dynamic>;
      expect(proxy['tag'], 'proxy');
      expect(proxy['protocol'], 'socks');
      expect(
        (((proxy['settings'] as Map<String, dynamic>)['servers']
                    as List<dynamic>)
                .first
            as Map<String, dynamic>)['port'],
        20444,
      );
      final Map<String, dynamic> aether =
          config['nebulaAether'] as Map<String, dynamic>;
      expect(aether['port'], 20444);
      expect(aether['args'], contains('--h2'));
    });

    test('through WARP, the server is dialled via Aether', () {
      final Map<String, dynamic> config = _render(
        _reality,
        const WarpSettings(throughWarp: true),
      );
      final List<dynamic> outbounds = config['outbounds'] as List<dynamic>;
      final Map<String, dynamic> proxy =
          outbounds.first as Map<String, dynamic>;
      expect(proxy['protocol'], 'vless');
      expect(
        ((proxy['streamSettings'] as Map<String, dynamic>)['sockopt']
            as Map<String, dynamic>)['dialerProxy'],
        'warp-entry',
      );
      expect(
        outbounds.any(
          (dynamic o) =>
              (o as Map<String, dynamic>)['tag'] == 'warp-entry' &&
              o['protocol'] == 'socks',
        ),
        isTrue,
      );
      expect(config.containsKey('nebulaAether'), isTrue);
    });

    test('off, the server config is as before, without Aether', () {
      final Map<String, dynamic> config = _render(
        _reality,
        WarpSettings.defaults,
      );
      expect(config.containsKey('nebulaAether'), isFalse);
      expect(jsonEncode(config), isNot(contains('warp-entry')));
    });
  });

  test('WARP is listed first and needs no link', () async {
    final LocalServerRepository repository = LocalServerRepository(
      store: InMemoryFreeLinkStore(),
      importedName: () => 'Imported',
      offersWarp: () => 'Cloudflare WARP (free)',
    );
    final List<AvailableServer> servers = await repository
        .listAvailableServers();
    expect(servers.first.code, kWarpServerCode);
    expect(isOwnLinkCode(kWarpServerCode), isTrue);
    final XrayClientResult client = await repository.requestXrayClient(
      deviceId: freeDeviceId,
      serverCode: kWarpServerCode,
      protocolProfileCode: kWarpTransport,
    );
    expect(client.transport, kWarpTransport);
  });
}
