import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_mobile/core/xray/macos_vpn_helper.dart';
import 'package:nebula_mobile/core/xray/macos_xray_tunnel.dart';

void main() {
  final Map<String, dynamic> profile = <String, dynamic>{
    'dns': <String, dynamic>{
      'servers': <String>['1.1.1.1'],
    },
    'outbounds': <Map<String, dynamic>>[
      <String, dynamic>{
        'tag': 'proxy',
        'protocol': 'vless',
        'settings': <String, dynamic>{
          'vnext': <Map<String, dynamic>>[
            <String, dynamic>{'address': 'vpn.example.org', 'port': 443},
          ],
        },
      },
    ],
  };

  test('the TUN is a numbered utun that routes everything', () {
    final Map<String, dynamic> config = macosXrayTunConfig(profile);
    final Map<String, dynamic> settings =
        (config['inbounds'] as List<Map<String, dynamic>>).single['settings']
            as Map<String, dynamic>;
    expect(settings['name'], macosTunnelInterface);
    expect(RegExp(r'^utun\d+$').hasMatch(settings['name'] as String), isTrue);
    expect(settings.containsKey('desc'), isFalse);
    expect(settings['autoSystemRoutingTable'], <String>['0.0.0.0/0', '::/0']);
    expect(settings['autoOutboundsInterface'], 'auto');
  });

  test('the upstream is found under vnext, servers or the settings', () {
    expect(macosUpstreamAddress(profile), 'vpn.example.org');
    expect(
      macosUpstreamAddress(<String, dynamic>{
        'outbounds': <Map<String, dynamic>>[
          <String, dynamic>{
            'settings': <String, dynamic>{'address': '162.159.198.1'},
          },
        ],
      }),
      '162.159.198.1',
    );
  });

  test('traffic comes from the link row of netstat -ibI', () {
    const String netstat =
        'Name       Mtu   Network       Address            Ipkts Ierrs     Ibytes    Opkts Oerrs     Obytes  Coll\n'
        'utun188    1500  <Link#24>                          120     0      98304       80     0      40960     0\n'
        'utun188    1500  172.19.0/30   172.19.0.2           120     -      98304       80     -      40960     -\n';
    final reading = macosTunnelTraffic(netstat, 'utun188')!;
    expect(reading.rxBytes, 98304);
    expect(reading.txBytes, 40960);
    expect(macosTunnelTraffic(netstat, 'utun3'), isNull);
  });
}
