import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_mobile/core/network/dns_tunnel_desktop.dart';

List<int> _field(int number, List<int> bytes) => <int>[
  number << 3 | 2,
  bytes.length,
  ...bytes,
];

List<int> _cidr(List<int> ip, int prefix) => <int>[
  ..._field(1, ip),
  2 << 3,
  prefix,
];

List<int> _country(String code, List<List<int>> cidrs) => <int>[
  ..._field(1, code.codeUnits),
  for (final List<int> cidr in cidrs) ..._field(2, cidr),
];

Uint8List _geoip() => Uint8List.fromList(<int>[
  ..._field(
    1,
    _country('US', <List<int>>[
      _cidr(<int>[1, 2, 3, 0], 24),
    ]),
  ),
  ..._field(
    1,
    _country('IR', <List<int>>[
      _cidr(<int>[5, 160, 0, 0], 14),
      // Not on its boundary: taken as the /12 it lies in.
      _cidr(<int>[2, 144, 0, 5], 12),
      _cidr(<int>[0x20, 0x01, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], 32),
    ]),
  ),
]);

void main() {
  test('decodes one country of a geoip.dat, IPv4 only', () {
    expect(geoipRanges(_geoip(), 'IR'), <(int, int)>[
      (0x05A00000, 0x05A3FFFF),
      (0x02900000, 0x029FFFFF),
    ]);
    expect(geoipRanges(_geoip(), 'DE'), isEmpty);
  });

  test('tells addresses in Iran from the bundled geoip.dat', () async {
    final Directory runtime = await Directory.systemTemp.createTemp('geo');
    addTearDown(() => runtime.delete(recursive: true));
    await File('${runtime.path}/geoip.dat').writeAsBytes(_geoip());
    final DesktopDnsTunnelPlatform platform = DesktopDnsTunnelPlatform(
      runtimeDirectory: runtime.path,
    );
    expect(
      await platform.inIran(<String>[
        '5.161.2.3',
        '1.2.3.4',
        '2.159.255.255',
        'not an address',
      ]),
      <bool>[true, false, true, false],
    );
    expect(await platform.networkKey(), 'desktop');
  });

  test('no geoip.dat: nothing is in Iran', () async {
    final DesktopDnsTunnelPlatform platform = DesktopDnsTunnelPlatform(
      runtimeDirectory: '${Directory.systemTemp.path}/nebula-missing',
    );
    expect(await platform.inIran(<String>['5.161.2.3']), <bool>[false]);
  });
}
