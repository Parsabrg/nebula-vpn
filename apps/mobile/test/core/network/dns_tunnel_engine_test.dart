import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_mobile/core/network/dns_tunnel_engine.dart';
import 'package:nebula_mobile/core/network/dns_tunnel_sync.dart';
import 'package:nebula_mobile/core/servers/server_repository.dart';
import 'package:nebula_mobile/features/devices/devices_state.dart';
import 'package:nebula_mobile/features/devices/profile_order.dart';

const DnsTunnelDetails _details = DnsTunnelDetails(
  domains: <String>['nt.example.test', 'nt.backup.test'],
  key: '0123456789abcdef0123456789abcdef',
  encryptionMethod: 5,
  serverCode: 'study-lab-1',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('first name active, the rest standby; TCP on the given port', () {
    final String config = renderDnsTunnelConfig(_details, 41234);

    expect(config, contains('DOMAINS = ["nt.example.test"]'));
    expect(config, contains('STANDBY_DOMAINS = ["nt.backup.test"]'));
    expect(config, contains('DATA_ENCRYPTION_METHOD = 5'));
    expect(
      config,
      contains('ENCRYPTION_KEY = "0123456789abcdef0123456789abcdef"'),
    );
    expect(config, contains('PROTOCOL_TYPE = "TCP"'));
    expect(config, contains('LISTEN_IP = "127.0.0.1"'));
    expect(config, contains('LISTEN_PORT = 41234'));
    expect(config, contains('TUNNEL_MODE = "legacy"'));
  });

  test('quotes cannot break out of a TOML string', () {
    final String config = renderDnsTunnelConfig(
      const DnsTunnelDetails(
        domains: <String>['a"b'],
        key: r'k\"',
        encryptionMethod: 5,
        serverCode: 's',
      ),
      1,
    );
    expect(config, contains(r'DOMAINS = ["a\"b"]'));
    expect(config, contains(r'ENCRYPTION_KEY = "k\\\""'));
  });

  AvailableProfile profile(String code) => AvailableProfile(
    code: code,
    displayName: code,
    protocolId: 'p',
    protocolCode: 'vless',
    adBlock: false,
  );

  test('offered on its server only, after VLESS Encryption', () {
    final List<AvailableServer> servers = withDnsTunnelProfile(
      <AvailableServer>[
        AvailableServer(
          code: 'study-lab-1',
          displayName: 'germany',
          publicHost: 'h',
          profiles: <AvailableProfile>[profile('vless-enc'), profile('xhttp')],
        ),
        AvailableServer(
          code: 'other',
          displayName: 'other',
          publicHost: 'h',
          profiles: <AvailableProfile>[profile('vless-enc')],
        ),
      ],
      _details,
    );

    expect(servers[0].profiles.map((AvailableProfile p) => p.code), <String>[
      'vless-enc',
      'xhttp',
      kDnsTunnelProfileCode,
    ]);
    expect(servers[0].profiles.last.manualOnly, isTrue);
    expect(servers[1].profiles, hasLength(1));
    expect(credentialProfileCode(kDnsTunnelProfileCode), 'vless-enc');
    expect(credentialProfileCode('xhttp'), 'xhttp');
  });

  test('listed last even when it measured fastest', () {
    final List<AvailableProfile> ordered = orderedProfiles(
      <AvailableProfile>[profile(kDnsTunnelProfileCode), profile('xhttp')],
      <String, ProtocolDelay>{
        kDnsTunnelProfileCode: const ProtocolDelay.measured(10),
        'xhttp': const ProtocolDelay.measured(500),
      },
      pinging: false,
    );
    expect(ordered.last.code, kDnsTunnelProfileCode);
  });

  test('the config dials the tunnel port and carries the engine config', () {
    final String wrapped = withDnsTunnelConfig(
      jsonEncode(<String, Object>{
        'outbounds': <Object>[
          <String, Object>{
            'settings': <String, Object>{
              'vnext': <Object>[
                <String, Object>{'address': '91.107.170.215', 'port': 8453},
              ],
            },
          },
        ],
      }),
      _details,
      port: 40000,
      resolvers: '1.2.3.4\n',
    );
    final Map<String, dynamic> config =
        jsonDecode(wrapped) as Map<String, dynamic>;
    final Map<String, dynamic> next =
        // ignore: avoid_dynamic_calls
        config['outbounds'][0]['settings']['vnext'][0] as Map<String, dynamic>;
    expect(next['address'], '127.0.0.1');
    expect(next['port'], 40000);
    final Map<String, dynamic> tunnel =
        config['nebulaDnsTunnel'] as Map<String, dynamic>;
    expect(tunnel['port'], 40000);
    expect(tunnel['config'], contains('LISTEN_PORT = 40000'));
  });
}
