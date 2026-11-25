import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_mobile/core/diagnostics/debug_log.dart';
import 'package:nebula_mobile/core/network/api_exception.dart';
import 'package:nebula_mobile/core/servers/server_repository.dart';

const Map<String, Object?> _client = <String, Object?>{
  'client_id': 'c1',
  'uuid': '00000000-0000-4000-8000-000000000001',
  'server_address': 'vpn.example.test',
  'port': 8449,
  'sni': 'vpn.example.test',
  'transport': 'raw',
  'transport_security': 'tls',
  'ad_block': false,
};

/// Answers 409 ("still applying") [busy] times, then the credential.
class _Api implements HttpClientAdapter {
  _Api(this.busy);

  int busy;
  int asked = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    asked++;
    final bool wait = busy-- > 0;
    return ResponseBody.fromString(
      jsonEncode(
        wait
            ? <String, Object?>{
                'detail':
                    'An Xray operation is already in progress for this device',
              }
            : _client,
      ),
      wait ? 409 : 200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<XrayClientResult> _ask(_Api api) =>
    DioServerRepository(
      Dio(BaseOptions(baseUrl: 'https://api.example.test'))
        ..httpClientAdapter = api,
      applyWait: Duration.zero,
    ).requestXrayClient(
      deviceId: 'd',
      serverCode: 's',
      protocolProfileCode: 'vless-tcp-tls',
    );

void main() {
  test(
    'a credential still being applied is waited for, not an error',
    () async {
      final _Api api = _Api(2);
      expect((await _ask(api)).clientId, 'c1');
      expect(api.asked, 3);
    },
  );

  test('it gives up after a few asks', () async {
    final _Api api = _Api(99);
    await expectLater(_ask(api), throwsA(isA<NebulaApiException>()));
    expect(api.asked, 5);
  });

  test('a logged path hides what may be a token, keeps ids', () {
    expect(
      loggedPath(
        Uri.parse(
          'https://a.test/v1/devices/0b0e6c1e-8d3a-4f6e-9c1a-2b3c4d5e6f70/xray-client',
        ),
      ),
      'v1/devices/0b0e6c1e-8d3a-4f6e-9c1a-2b3c4d5e6f70/xray-client',
    );
    expect(
      loggedPath(
        Uri.parse('https://a.test/sub/AbCdEfGhIjKlMnOpQrStUvWxYz0123'),
      ),
      'sub/…',
    );
  });
}
