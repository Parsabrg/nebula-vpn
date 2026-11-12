import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';

/// What the DNS tunnel needs (plan 10): asked for while the API is
/// reachable, because in a shutdown -- when only DNS still gets out -- there
/// is no API to ask.
class DnsTunnelDetails {
  const DnsTunnelDetails({
    required this.domains,
    required this.key,
    required this.encryptionMethod,
    required this.serverCode,
  });

  /// Tried in turn: a second name on another domain needs no app update.
  final List<String> domains;
  final String key;
  final int encryptionMethod;

  /// The server whose VLESS Encryption inbound the tunnel reaches; the
  /// person's credential for it is still needed.
  final String serverCode;

  static DnsTunnelDetails? fromJson(Object? body) {
    if (body is! Map<String, dynamic>) {
      return null;
    }
    final Object? domains = body['domains'];
    final Object? key = body['key'];
    final Object? method = body['encryption_method'];
    final Object? server = body['server_code'];
    if (domains is! List<Object?> ||
        key is! String ||
        key.isEmpty ||
        method is! int ||
        server is! String ||
        server.isEmpty) {
      return null;
    }
    final List<String> names = domains
        .whereType<String>()
        .where((String name) => name.isNotEmpty)
        .toList();
    if (names.isEmpty) {
      return null;
    }
    return DnsTunnelDetails(
      domains: names,
      key: key,
      encryptionMethod: method,
      serverCode: server,
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    'domains': domains,
    'key': key,
    'encryption_method': encryptionMethod,
    'server_code': serverCode,
  };
}

/// The key is a secret, so it lives in the Keystore/DPAPI-backed store.
abstract interface class DnsTunnelStore {
  Future<DnsTunnelDetails?> read();
  Future<void> write(DnsTunnelDetails details);
  Future<void> clear();
}

class FlutterDnsTunnelStore implements DnsTunnelStore {
  FlutterDnsTunnelStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _key = 'nebula.dns_tunnel';

  final FlutterSecureStorage _storage;

  @override
  Future<DnsTunnelDetails?> read() async {
    final String? raw = await _storage.read(key: _key);
    if (raw == null) {
      return null;
    }
    try {
      return DnsTunnelDetails.fromJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(DnsTunnelDetails details) =>
      _storage.write(key: _key, value: jsonEncode(details.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class InMemoryDnsTunnelStore implements DnsTunnelStore {
  DnsTunnelDetails? details;

  @override
  Future<DnsTunnelDetails?> read() async => details;

  @override
  Future<void> write(DnsTunnelDetails value) async {
    details = value;
  }

  @override
  Future<void> clear() async {
    details = null;
  }
}

/// Refreshes the stored details. A 404 is the server's answer that it runs
/// no tunnel, so the stored copy goes; any other failure keeps it, since a
/// stale copy is as useful as it was a minute ago.
class DnsTunnelSync {
  DnsTunnelSync(this._dio, this._store);

  final Dio _dio;
  final DnsTunnelStore _store;

  /// Whether the details changed: the server list is built from them, so
  /// a first sign-in listed no DNS tunnel until the next load (Linux,
  /// 2026-11-13).
  Future<bool> refresh() async {
    try {
      final DnsTunnelDetails? before = await _store.read();
      final Response<dynamic> response = await _dio.get<dynamic>(
        '/v1/dns-tunnel/',
      );
      final DnsTunnelDetails? details = DnsTunnelDetails.fromJson(
        response.data,
      );
      if (details != null) {
        await _store.write(details);
        return before == null ||
            jsonEncode(before.toJson()) != jsonEncode(details.toJson());
      }
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        final bool had = await _store.read() != null;
        await _store.clear();
        return had;
      }
    } catch (_) {
      // Housekeeping: never worth failing anything the person asked for.
    }
    return false;
  }
}

final dnsTunnelStoreProvider = Provider<DnsTunnelStore>((Ref ref) {
  return FlutterDnsTunnelStore();
});

final dnsTunnelSyncProvider = Provider<DnsTunnelSync>((Ref ref) {
  return DnsTunnelSync(
    ref.watch(dioProvider),
    ref.watch(dnsTunnelStoreProvider),
  );
});
