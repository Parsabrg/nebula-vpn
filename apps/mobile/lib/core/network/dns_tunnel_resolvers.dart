import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/storage_providers.dart';
import 'dns_tunnel_engine.dart';
import 'dns_tunnel_sync.dart';

/// The resolvers the DNS tunnel starts from: the last scan's survivors, or
/// CottenDNS's Iran list until a scan has run. Rescanned weekly, on Wi-Fi
/// only (a scan sends a few thousand queries).
class DnsTunnelResolvers {
  DnsTunnelResolvers(
    this._preferences, {
    Future<String> Function()? bundled,
    Future<bool> Function()? onWifi,
    Future<List<String>> Function(DnsTunnelDetails, String)? scan,
    DateTime Function()? now,
  }) : _bundled = bundled ?? _loadBundled,
       _onWifi = onWifi ?? _nativeOnWifi,
       _scan = scan ?? scanDnsTunnelResolvers,
       _now = now ?? DateTime.now;

  static const String listKey = 'nebula.dns_tunnel.resolvers';
  static const String scannedAtKey = 'nebula.dns_tunnel.scanned_at';
  static const Duration interval = Duration(days: 7);
  static const MethodChannel _channel = MethodChannel(
    'org.nebulavpn/wireguard_tunnel',
  );

  final SharedPreferences _preferences;
  final Future<String> Function() _bundled;
  final Future<bool> Function() _onWifi;
  final Future<List<String>> Function(DnsTunnelDetails, String) _scan;
  final DateTime Function() _now;
  bool _scanning = false;

  static Future<String> _loadBundled() =>
      rootBundle.loadString('assets/dns_tunnel/resolvers_ir.txt');

  static Future<bool> _nativeOnWifi() async =>
      await _channel.invokeMethod<bool>('onWifi') ?? false;

  /// One address per line, for the engine's resolver file.
  Future<String> current() async {
    final String? scanned = _preferences.getString(listKey);
    return (scanned != null && scanned.trim().isNotEmpty)
        ? scanned
        : _bundled();
  }

  DateTime? get scannedAt {
    final int? millis = _preferences.getInt(scannedAtKey);
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  /// Scans the bundled list when the last scan is a week old and the phone
  /// is on Wi-Fi. A scan that finds nothing keeps the previous list.
  Future<void> refreshIfDue(DnsTunnelDetails details) async {
    final DateTime? last = scannedAt;
    if (_scanning || (last != null && _now().difference(last) < interval)) {
      return;
    }
    _scanning = true;
    try {
      if (!await _onWifi()) {
        return;
      }
      final List<String> valid = await _scan(details, await _bundled());
      await _preferences.setInt(scannedAtKey, _now().millisecondsSinceEpoch);
      if (valid.isNotEmpty) {
        await _preferences.setString(listKey, '${valid.join('\n')}\n');
      }
    } catch (_) {
      // Housekeeping; the previous list stays as useful as it was.
    } finally {
      _scanning = false;
    }
  }
}

final dnsTunnelResolversProvider = Provider<DnsTunnelResolvers>((Ref ref) {
  return DnsTunnelResolvers(ref.watch(sharedPreferencesProvider));
});
