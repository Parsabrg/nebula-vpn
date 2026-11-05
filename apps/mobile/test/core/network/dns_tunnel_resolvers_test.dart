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

Future<(DnsTunnelResolvers, List<String>)> _resolvers({
  bool wifi = true,
  List<String> found = const <String>['1.1.1.1:53'],
  DateTime? now,
  Map<String, Object> stored = const <String, Object>{},
}) async {
  SharedPreferences.setMockInitialValues(stored);
  final SharedPreferences preferences = await SharedPreferences.getInstance();
  final List<String> scanned = <String>[];
  return (
    DnsTunnelResolvers(
      preferences,
      bundled: () async => '9.9.9.9\n8.8.8.8\n',
      onWifi: () async => wifi,
      scan: (DnsTunnelDetails details, String list) async {
        scanned.add(list);
        return found;
      },
      now: () => now ?? DateTime(2026, 11, 6),
    ),
    scanned,
  );
}

void main() {
  test('starts from the bundled list', () async {
    final (DnsTunnelResolvers resolvers, _) = await _resolvers();
    expect(await resolvers.current(), '9.9.9.9\n8.8.8.8\n');
  });

  test('a scan on Wi-Fi keeps its survivors', () async {
    final (DnsTunnelResolvers resolvers, List<String> scanned) =
        await _resolvers();

    await resolvers.refreshIfDue(_details);

    expect(scanned, <String>['9.9.9.9\n8.8.8.8\n']);
    expect(await resolvers.current(), '1.1.1.1:53\n');
  });

  test('no scan off Wi-Fi or within a week', () async {
    final (DnsTunnelResolvers offWifi, List<String> a) = await _resolvers(
      wifi: false,
    );
    await offWifi.refreshIfDue(_details);
    expect(a, isEmpty);

    final (DnsTunnelResolvers recent, List<String> b) = await _resolvers(
      stored: <String, Object>{
        DnsTunnelResolvers.scannedAtKey: DateTime(
          2026,
          11,
          3,
        ).millisecondsSinceEpoch,
      },
    );
    await recent.refreshIfDue(_details);
    expect(b, isEmpty);
  });

  test('a scan that finds nothing keeps the previous list', () async {
    final (DnsTunnelResolvers resolvers, _) = await _resolvers(
      found: const <String>[],
      stored: <String, Object>{DnsTunnelResolvers.listKey: '2.2.2.2:53\n'},
    );

    await resolvers.refreshIfDue(_details);

    expect(await resolvers.current(), '2.2.2.2:53\n');
  });
}
