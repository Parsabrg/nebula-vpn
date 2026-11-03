import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../servers/server_repository.dart';

/// The WireGuard peer the server gave this device, per server and profile,
/// with the public key it was issued for.
///
/// Kept so a connect can bring the tunnel up at once, as v2rayNG starts from
/// its saved config, instead of asking the control plane first: that request
/// is a round trip to the API and from there to the server's agent, which
/// was most of a WireGuard connect from Iran (2026-11-03). The server keeps
/// the peer until sign-out, an admin, or the account's access or data
/// running out removes it; a saved peer that no longer answers is forgotten
/// and asked for again.
abstract interface class WireGuardPeerStore {
  /// The saved peer, if it was issued for [publicKey].
  Future<WireGuardPeerResult?> read({
    required String serverCode,
    required String profileCode,
    required String publicKey,
  });

  Future<void> write({
    required String serverCode,
    required String profileCode,
    required String publicKey,
    required WireGuardPeerResult peer,
  });

  Future<void> forget({
    required String serverCode,
    required String profileCode,
  });

  /// Dropped on sign-out, with everything else that identified the account.
  Future<void> clear();
}

Map<String, Object?> _encode(String publicKey, WireGuardPeerResult p) =>
    <String, Object?>{
      'publicKey': publicKey,
      'peerId': p.peerId,
      'assignedAddress': p.assignedAddress,
      'serverPublicKey': p.serverPublicKey,
      'listenPort': p.listenPort,
      'publicEndpoint': p.publicEndpoint,
      'clientDns': p.clientDns,
      'clientAllowedIps': p.clientAllowedIps,
      'persistentKeepaliveSeconds': p.persistentKeepaliveSeconds,
    };

WireGuardPeerResult? _decode(Map<String, dynamic> map, String publicKey) {
  if (map['publicKey'] != publicKey) {
    // Issued for a key this device no longer holds.
    return null;
  }
  return WireGuardPeerResult(
    peerId: map['peerId'] as String,
    assignedAddress: map['assignedAddress'] as String,
    serverPublicKey: map['serverPublicKey'] as String,
    listenPort: map['listenPort'] as int,
    publicEndpoint: map['publicEndpoint'] as String,
    clientDns: map['clientDns'] as String,
    clientAllowedIps: map['clientAllowedIps'] as String,
    persistentKeepaliveSeconds: map['persistentKeepaliveSeconds'] as int,
  );
}

class FlutterSecureWireGuardPeerStore implements WireGuardPeerStore {
  FlutterSecureWireGuardPeerStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _prefix = 'nebula.wireguard_peer.';

  final FlutterSecureStorage _storage;

  String _key(String serverCode, String profileCode) =>
      '$_prefix$serverCode.$profileCode';

  @override
  Future<WireGuardPeerResult?> read({
    required String serverCode,
    required String profileCode,
    required String publicKey,
  }) async {
    final String? stored = await _storage.read(
      key: _key(serverCode, profileCode),
    );
    if (stored == null) {
      return null;
    }
    try {
      return _decode(jsonDecode(stored) as Map<String, dynamic>, publicKey);
    } on Object {
      // A shape from an older build: asked for again rather than guessed.
      return null;
    }
  }

  @override
  Future<void> write({
    required String serverCode,
    required String profileCode,
    required String publicKey,
    required WireGuardPeerResult peer,
  }) => _storage.write(
    key: _key(serverCode, profileCode),
    value: jsonEncode(_encode(publicKey, peer)),
  );

  @override
  Future<void> forget({
    required String serverCode,
    required String profileCode,
  }) => _storage.delete(key: _key(serverCode, profileCode));

  @override
  Future<void> clear() async {
    final Map<String, String> all = await _storage.readAll();
    for (final String key in all.keys) {
      if (key.startsWith(_prefix)) {
        await _storage.delete(key: key);
      }
    }
  }
}

class InMemoryWireGuardPeerStore implements WireGuardPeerStore {
  final Map<String, Map<String, Object?>> _peers =
      <String, Map<String, Object?>>{};

  @override
  Future<WireGuardPeerResult?> read({
    required String serverCode,
    required String profileCode,
    required String publicKey,
  }) async {
    final Map<String, Object?>? stored = _peers['$serverCode.$profileCode'];
    return stored == null
        ? null
        : _decode(Map<String, dynamic>.from(stored), publicKey);
  }

  @override
  Future<void> write({
    required String serverCode,
    required String profileCode,
    required String publicKey,
    required WireGuardPeerResult peer,
  }) async {
    _peers['$serverCode.$profileCode'] = _encode(publicKey, peer);
  }

  @override
  Future<void> forget({
    required String serverCode,
    required String profileCode,
  }) async {
    _peers.remove('$serverCode.$profileCode');
  }

  @override
  Future<void> clear() async => _peers.clear();
}
