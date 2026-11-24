import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_mobile/core/network/dns_tunnel_sync.dart';

class _Answering implements HttpClientAdapter {
  _Answering(this.status, [this.body]);

  final int? status; // null: the network fails.
  final Object? body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (status == null) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    return ResponseBody.fromString(
      jsonEncode(body ?? <String, Object>{}),
      status!,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const Map<String, Object> _served = <String, Object>{
  'domains': <String>['nt.example.test', 'nt.backup.test'],
  'key': '0123456789abcdef0123456789abcdef',
  'encryption_method': 5,
  'server_code': 'study-lab-1',
};

DnsTunnelSync _sync(_Answering network, InMemoryDnsTunnelStore store) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://direct.test'))
    ..httpClientAdapter = network;
  return DnsTunnelSync(dio, store);
}

void main() {
  test('keeps what the server serves, names in order', () async {
    final InMemoryDnsTunnelStore store = InMemoryDnsTunnelStore();

    expect(await _sync(_Answering(200, _served), store).refresh(), isTrue);
    // The same details again: nothing to rebuild the server list for.
    expect(await _sync(_Answering(200, _served), store).refresh(), isFalse);

    expect(store.tunnels.single.domains, <String>[
      'nt.example.test',
      'nt.backup.test',
    ]);
    expect(store.tunnels.single.serverCode, 'study-lab-1');
    expect(store.tunnels.single.encryptionMethod, 5);
  });

  test("keeps every server's tunnel from a newer server", () async {
    final InMemoryDnsTunnelStore store = InMemoryDnsTunnelStore();
    final Map<String, Object> second = <String, Object>{
      ..._served,
      'domains': <String>['t2.example.test'],
      'server_code': 'nl',
    };

    expect(
      await _sync(
        _Answering(200, <String, Object>{
          ..._served,
          'tunnels': <Object>[_served, second],
        }),
        store,
      ).refresh(),
      isTrue,
    );

    expect(store.tunnels.map((DnsTunnelDetails t) => t.serverCode), <String>[
      'study-lab-1',
      'nl',
    ]);
    expect(dnsTunnelFor(store.tunnels, 'nl')!.domains, <String>[
      't2.example.test',
    ]);
    expect(dnsTunnelFor(store.tunnels)!.serverCode, 'study-lab-1');
    expect(dnsTunnelFor(store.tunnels, 'tehran'), isNull);
  });

  test('a copy an older app saved (one tunnel) still reads', () {
    final List<DnsTunnelDetails> old = DnsTunnelDetails.listFromJson(
      jsonDecode(jsonEncode(_served)),
    );
    expect(old.single.serverCode, 'study-lab-1');
    final List<DnsTunnelDetails> saved = DnsTunnelDetails.listFromJson(
      jsonDecode(jsonEncode(DnsTunnelDetails.listToJson(old))),
    );
    expect(saved.single.key, old.single.key);
  });

  test('a server without a tunnel (404) clears the stored copy', () async {
    final InMemoryDnsTunnelStore store = InMemoryDnsTunnelStore()
      ..tunnels = DnsTunnelDetails.listFromJson(_served);

    expect(await _sync(_Answering(404), store).refresh(), isTrue);

    expect(store.tunnels, isEmpty);
  });

  test('a failed request keeps the stored copy', () async {
    final InMemoryDnsTunnelStore store = InMemoryDnsTunnelStore()
      ..tunnels = DnsTunnelDetails.listFromJson(_served);

    expect(await _sync(_Answering(null), store).refresh(), isFalse);

    expect(store.tunnels, isNotEmpty);
  });

  test('details round-trip through JSON; a missing key is rejected', () {
    final DnsTunnelDetails details = DnsTunnelDetails.fromJson(_served)!;
    expect(
      DnsTunnelDetails.fromJson(jsonDecode(jsonEncode(details.toJson())))!.key,
      details.key,
    );
    expect(
      DnsTunnelDetails.fromJson(<String, Object>{..._served, 'key': ''}),
      isNull,
    );
  });
}
