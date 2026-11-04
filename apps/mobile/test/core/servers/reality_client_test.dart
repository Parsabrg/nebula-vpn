import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_mobile/core/servers/server_repository.dart';
import 'package:nebula_mobile/core/xray/local_proxy.dart';
import 'package:nebula_mobile/core/xray/xray_config.dart';

/// A VLESS + REALITY (Vision) credential as the API hands it out.
const Map<String, Object?> _reality = <String, Object?>{
  'client_id': 'c1',
  'uuid': '00000000-0000-4000-8000-000000000001',
  'server_address': 'vpn.example.test',
  'port': 8456,
  'sni': 'www.example.com',
  'transport': 'raw',
  'transport_security': 'reality',
  'ad_block': false,
  'reality_public_key': 'public-key-canary',
  'reality_short_id': '0123abcd',
  'flow': 'xtls-rprx-vision',
};

class _Api implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(_reality),
    200,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>['application/json'],
    },
  );

  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'a REALITY credential from the server renders REALITY with Vision',
    () async {
      final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'))
        ..httpClientAdapter = _Api();
      final XrayClientResult client = await DioServerRepository(dio)
          .requestXrayClient(
            deviceId: 'd',
            serverCode: 's',
            protocolProfileCode: 'vless-reality-vision',
          );

      final Map<String, dynamic> config =
          jsonDecode(
                renderXrayClientConfigJson(
                  client,
                  localProxy: const LocalProxy(
                    port: 1,
                    username: 'u',
                    password: 'p',
                  ),
                ),
              )
              as Map<String, dynamic>;
      final Map<String, dynamic> proxy = (config['outbounds'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .firstWhere((Map<String, dynamic> o) => o['tag'] == 'proxy');
      final Map<String, dynamic> stream =
          proxy['streamSettings'] as Map<String, dynamic>;
      expect(stream['security'], 'reality');
      final Map<String, dynamic> reality =
          stream['realitySettings'] as Map<String, dynamic>;
      expect(reality['serverName'], 'www.example.com');
      expect(reality['publicKey'], 'public-key-canary');
      expect(reality['shortId'], '0123abcd');
      final Map<String, dynamic> user =
          ((((proxy['settings'] as Map<String, dynamic>)['vnext']
                                  as List<dynamic>)
                              .first
                          as Map<String, dynamic>)['users']
                      as List<dynamic>)
                  .first
              as Map<String, dynamic>;
      expect(user['flow'], 'xtls-rprx-vision');
    },
  );
}
