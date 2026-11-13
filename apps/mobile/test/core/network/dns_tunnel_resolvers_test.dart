import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_mobile/core/network/dns_tunnel_resolvers.dart';
import 'package:nebula_mobile/core/network/dns_tunnel_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

const DnsTunnelDetails _details = DnsTunnelDetails(
  domains: <String>['nt.example.test'],
  key: '0123456789abcdef0123456789abcdef',
  encryptionMethod: 5,
  serverCode: 'study-lab-1',
);

/// An engine where resolvers ending in a digit < [goodBelow] work, and
/// ones starting with `5.` are inside Iran.
class _FakePlatform implements DnsTunnelPlatform {
  String network = 'mobile-43211';
  final List<(int, List<String>)> scans = <(int, List<String>)>[];
  DnsTunnelScanProgress _last = const DnsTunnelScanProgress(
    tested: 0,
    total: 0,
    valid: <String>[],
    seen: <String>[],
    done: true,
  );

  @override
  Future<String> networkKey() async => network;

  @override
  Future<List<bool>> inIran(List<String> addresses) async =>
      addresses.map((String a) => a.startsWith('5.')).toList();

  @override
  Future<void> startScan(String config, String resolvers, int stopAfter) async {
    final List<String> list = resolvers
        .split('\n')
        .where((String l) => l.isNotEmpty)
        .toList();
    scans.add((stopAfter, list));
    final List<String> valid = <String>[];
    final List<String> seen = <String>[];
    for (final String r in list) {
      if (valid.length >= stopAfter) {
        break;
      }
      final String reported = DnsTunnelResolvers.normalise(r);
      seen.add(reported);
      if (r.startsWith('5.') || r.startsWith('9.')) {
        valid.add(reported);
      }
    }
    _last = DnsTunnelScanProgress(
      tested: seen.length,
      total: list.length,
      valid: valid,
      seen: seen,
      done: true,
    );
  }

  @override
  Future<DnsTunnelScanProgress> scanProgress() async => _last;

  @override
  Future<void> stopScan() async {}
}

/// An engine still testing until it is stopped.
class _NeverDone implements DnsTunnelPlatform {
  int started = 0;
  bool stopped = false;

  @override
  Future<String> networkKey() async => 'wifi';

  @override
  Future<List<bool>> inIran(List<String> addresses) async =>
      addresses.map((_) => false).toList();

  @override
  Future<void> startScan(String config, String resolvers, int stopAfter) async {
    started++;
  }

  @override
  Future<DnsTunnelScanProgress> scanProgress() async => DnsTunnelScanProgress(
    tested: 0,
    total: 1,
    valid: const <String>[],
    seen: const <String>[],
    done: stopped,
  );

  @override
  Future<void> stopScan() async {
    stopped = true;
  }
}

Future<(DnsTunnelResolvers, _FakePlatform)> _resolvers({
  Map<String, Object> stored = const <String, Object>{},
  String bundled = '5.0.0.1\n5.0.0.2\n1.0.0.1\n',
  DateTime? now,
}) async {
  SharedPreferences.setMockInitialValues(stored);
  final SharedPreferences preferences = await SharedPreferences.getInstance();
  final _FakePlatform platform = _FakePlatform();
  return (
    DnsTunnelResolvers(
      preferences,
      platform: platform,
      bundled: () async => bundled,
      now: () => now ?? DateTime(2026, 11, 6),
      pollEvery: Duration.zero,
    ),
    platform,
  );
}

/// Lets background growth finish.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 50));

List<String> _many(String prefix, int count) => <String>[
  for (int i = 1; i <= count; i++) '$prefix.0.0.$i',
];

void main() {
  test('parses lines, spaces and commas; drops anything not an address', () {
    expect(
      DnsTunnelResolvers.parse(
        '1.2.3.4\n5.6.7.8:53, [2001:db8::1]:53 example.com\n1.2.3.4 ; 9.9.9.9',
      ),
      <String>['1.2.3.4', '5.6.7.8:53', '[2001:db8::1]:53', '9.9.9.9'],
    );
  });

  test(
    'untested: the tunnel gets every candidate of the built-in list',
    () async {
      final (DnsTunnelResolvers r, _) = await _resolvers();
      expect(r.custom, isFalse);
      expect(await r.current('wifi'), '5.0.0.1\n5.0.0.2\n1.0.0.1\n');
    },
  );

  test(
    'a quick test stops at 10, then grows to 30 with 10 inside Iran',
    () async {
      final (DnsTunnelResolvers r, _FakePlatform platform) = await _resolvers();
      // 40 working abroad (9.x), 15 inside Iran (5.x), 20 dead (1.x).
      await r.saveSource(<String>[
        ..._many('9', 40),
        ..._many('5', 15),
        ..._many('1', 20),
      ]);

      expect(await r.quickTest(_details), 10);
      expect(platform.scans.first.$1, DnsTunnelResolvers.quickTarget);
      await _settle();

      final List<String> kept = r.workingOn('mobile-43211');
      expect(kept.length, greaterThanOrEqualTo(DnsTunnelResolvers.growTarget));
      expect(
        r.iranCountOn('mobile-43211'),
        greaterThanOrEqualTo(DnsTunnelResolvers.iranTarget),
      );
    },
  );

  test('short inside Iran, growth also tests the built-in Iran list', () async {
    final (DnsTunnelResolvers r, _FakePlatform platform) = await _resolvers(
      bundled: '${_many('5', 12).join('\n')}\n',
    );
    await r.saveSource(_many('9', 40));

    await r.quickTest(_details);
    await _settle();

    expect(platform.scans.last.$2.first, startsWith('5.'));
    expect(
      r.iranCountOn('mobile-43211'),
      greaterThanOrEqualTo(DnsTunnelResolvers.iranTarget),
    );
  });

  test('each network keeps its own list', () async {
    final (DnsTunnelResolvers r, _FakePlatform platform) = await _resolvers();
    await r.saveSource(<String>['9.0.0.1']);
    await r.quickTest(_details);
    await _settle();
    platform.network = 'wifi';

    expect(r.workingOn('mobile-43211'), contains('9.0.0.1:53'));
    expect(r.workingOn('wifi'), isEmpty);
  });

  test('a connect retests a list only once it is a week old', () async {
    final (DnsTunnelResolvers r, _FakePlatform platform) = await _resolvers();
    await r.saveSource(<String>['9.0.0.1', '9.0.0.2', '9.0.0.3']);

    await r.ensureFresh(_details);
    await _settle();
    final int afterFirst = platform.scans.length;
    expect(afterFirst, greaterThan(0));

    await r.ensureFresh(_details);
    expect(platform.scans.length, afterFirst);
  });

  test('a connect retests a list with too few working resolvers', () async {
    // One resolver, found while another VPN carried the test, kept the
    // tunnel from working for a week (Linux, 2026-11-13).
    final (DnsTunnelResolvers r, _FakePlatform platform) = await _resolvers(
      stored: <String, Object>{
        'nebula.dns_tunnel.resolvers.#built-in/mobile-43211': '9.0.0.1:53\n',
        'nebula.dns_tunnel.scanned_at.#built-in/mobile-43211': DateTime(
          2026,
          11,
          6,
        ).millisecondsSinceEpoch,
      },
    );
    expect(r.workingOn('mobile-43211'), hasLength(1));

    await r.ensureFresh(_details);

    expect(platform.scans, isNotEmpty);
  });

  test('the whole list is tested only on Wi-Fi', () async {
    final (DnsTunnelResolvers r, _FakePlatform platform) = await _resolvers();
    expect(await r.fullScan(_details), isNull);
    expect(platform.scans, isEmpty);

    platform.network = 'wifi';
    expect(await r.fullScan(_details), 2);
  });

  test('opening the app retests only on Wi-Fi', () async {
    final (DnsTunnelResolvers r, _FakePlatform platform) = await _resolvers();
    await r.refreshIfDue(_details);
    expect(platform.scans, isEmpty);

    platform.network = 'wifi';
    await r.refreshIfDue(_details);
    expect(platform.scans, isNotEmpty);
  });

  test('Stop leaves the screen idle at once and starts no growth', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final _NeverDone platform = _NeverDone();
    final DnsTunnelResolvers r = DnsTunnelResolvers(
      await SharedPreferences.getInstance(),
      platform: platform,
      bundled: () async => '9.0.0.1\n',
      pollEvery: const Duration(milliseconds: 5),
    );

    final Future<int> test = r.quickTest(_details);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(r.scanning, DnsTunnelScanKind.quick);

    await r.stop();
    expect(r.scanning, isNull);
    expect(platform.stopped, isTrue);
    await test;
    await _settle();
    expect(r.scanning, isNull);
    expect(platform.started, 1);
  });

  test('sets: pasting on the built-in list makes one; choosing another '
      'keeps it; only delete removes it', () async {
    final (DnsTunnelResolvers r, _) = await _resolvers();

    await r.saveSource(<String>['9.0.0.1'], newName: 'My list');
    expect(r.active, 'My list');
    await r.quickTest(_details);
    await _settle();

    await r.select(null);
    expect(r.custom, isFalse);
    expect(r.setNames, <String>['My list']);

    await r.select('My list');
    expect(r.source, '9.0.0.1\n');
    expect(r.workingOn('mobile-43211'), contains('9.0.0.1:53'));

    await r.saveSource(<String>['9.0.0.2'], newName: 'My list');
    expect(r.setNames, <String>['My list']);

    await r.select(null);
    await r.saveSource(<String>['9.0.0.3'], newName: 'My list');
    expect(r.setNames, <String>['My list', 'My list 2']);

    await r.deleteSet('My list 2');
    expect(r.setNames, <String>['My list']);
    expect(r.active, isNull);
  });
}
