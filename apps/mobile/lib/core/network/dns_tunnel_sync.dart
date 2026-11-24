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

  /// Every tunnel in [body]: the server's list, or the single tunnel an
  /// older server (or an older copy on this device) gave.
  static List<DnsTunnelDetails> listFromJson(Object? body) {
    if (body is Map<String, dynamic> && body['tunnels'] is List<Object?>) {
      return <DnsTunnelDetails>[
        for (final Object? item in body['tunnels'] as List<Object?>)
          if (DnsTunnelDetails.fromJson(item) case final DnsTunnelDetails one)
            one,
      ];
    }
    final DnsTunnelDetails? one = DnsTunnelDetails.fromJson(body);
    return one == null ? const <DnsTunnelDetails>[] : <DnsTunnelDetails>[one];
  }

  static Map<String, Object> listToJson(List<DnsTunnelDetails> tunnels) =>
      <String, Object>{
        'tunnels': <Map<String, Object>>[
          for (final DnsTunnelDetails tunnel in tunnels) tunnel.toJson(),
        ],
      };

  Map<String, Object> toJson() => <String, Object>{
    'domains': domains,
    'key': key,
    'encryption_method': encryptionMethod,
    'server_code': serverCode,
  };
}

/// The tunnel on [serverCode], or the first one when no server is named.
DnsTunnelDetails? dnsTunnelFor(
  List<DnsTunnelDetails> tunnels, [
  String? serverCode,
]) {
  for (final DnsTunnelDetails tunnel in tunnels) {
    if (serverCode == null || tunnel.serverCode == serverCode) {
      return tunnel;
    }
  }
  return null;
}

/// The keys are secrets, so they live in the Keystore/DPAPI-backed store.
/// One tunnel per server at most.
abstract interface class DnsTunnelStore {
  Future<List<DnsTunnelDetails>> read();
  Future<void> write(List<DnsTunnelDetails> tunnels);
  Future<void> clear();
}

class FlutterDnsTunnelStore implements DnsTunnelStore {
  FlutterDnsTunnelStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _key = 'nebula.dns_tunnel';

  final FlutterSecureStorage _storage;

  @override
  Future<List<DnsTunnelDetails>> read() async {
    final String? raw = await _storage.read(key: _key);
    if (raw == null) {
      return const <DnsTunnelDetails>[];
    }
    try {
      return DnsTunnelDetails.listFromJson(jsonDecode(raw));
    } on FormatException {
      return const <DnsTunnelDetails>[];
    }
  }

  @override
  Future<void> write(List<DnsTunnelDetails> tunnels) => _storage.write(
    key: _key,
    value: jsonEncode(DnsTunnelDetails.listToJson(tunnels)),
  );

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class InMemoryDnsTunnelStore implements DnsTunnelStore {
  List<DnsTunnelDetails> tunnels = const <DnsTunnelDetails>[];

  @override
  Future<List<DnsTunnelDetails>> read() async => tunnels;

  @override
  Future<void> write(List<DnsTunnelDetails> value) async {
    tunnels = value;
  }

  @override
  Future<void> clear() async {
    tunnels = const <DnsTunnelDetails>[];
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
  /// without this a first sign-in listed no DNS tunnel until the next load.
  Future<bool> refresh() async {
    try {
      final List<DnsTunnelDetails> before = await _store.read();
      final Response<dynamic> response = await _dio.get<dynamic>(
        '/v1/dns-tunnel/',
      );
      final List<DnsTunnelDetails> tunnels = DnsTunnelDetails.listFromJson(
        response.data,
      );
      if (tunnels.isNotEmpty) {
        await _store.write(tunnels);
        return jsonEncode(DnsTunnelDetails.listToJson(before)) !=
            jsonEncode(DnsTunnelDetails.listToJson(tunnels));
      }
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        final bool had = (await _store.read()).isNotEmpty;
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
