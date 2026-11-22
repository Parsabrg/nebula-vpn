import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../routing/tunnel_routes.dart';
import '../tunnel/tunnel_traffic.dart';
import 'linux_vpn_supervisor.dart' show linuxPrivateTemp;
import 'linux_xray_tunnel.dart';
import 'macos_vpn_helper.dart';
import 'windows_tunnel_config.dart';
import 'xray_tunnel_controller.dart';

/// macOS implementation for Xray-backed profiles: the bundled xray with its
/// own utun and routes, started as root by [macosVpnHelperScript] after
/// macOS's administrator prompt. Hysteria2, WARP and the DNS tunnel are not
/// on macOS yet.
class MacosXrayTunnelController implements XrayTunnelController {
  MacosXrayTunnelController({MacosXrayRuntime? runtime})
    : _runtime = runtime ?? MacosXrayRuntime();

  final MacosXrayRuntime _runtime;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> connect(
    String xrayConfigJson, {
    List<String> excludedPackages = const <String>[],
    List<String>? routes,
    String sessionName = 'Nebula',
    bool notificationShowsSpeed = true,
    String disconnectLabel = 'Disconnect',
    bool proxyOnly = false,
    bool killSwitch = false,
  }) => _runtime.start(xrayConfigJson, proxyOnly: proxyOnly, routes: routes);

  @override
  Future<void> disconnect() => _runtime.stop();

  @override
  Future<void> attach() async {}

  @override
  Stream<TunnelTraffic> get traffic => _runtime.traffic;

  @override
  Future<List<String>> logs() => _runtime.logs();

  @override
  Future<bool> clearLogs() async => true;

  @override
  Future<bool?> engineRunning() => _runtime.engineRunning();

  // A local xray with an HTTP inbound, no root needed: the Linux probe
  // works unchanged here.
  @override
  Future<int?> measureDelay(String config, {required String url}) =>
      _runtime.probe.measureDelay(config, url: url);

  @override
  Future<double?> measureDownload(String config, {required String url}) =>
      _runtime.probe.measureDownload(config, url: url);
}

/// The full-device tunnel around a rendered Xray client config on macOS: the
/// Windows one (Xray sets the routes and binds its own connections to the
/// real interface on both), on a utun.
Map<String, dynamic> macosXrayTunConfig(
  Map<String, dynamic> config, {
  bool localNetworkDirect = false,
}) {
  final Map<String, dynamic> tun = windowsXrayTunConfig(
    config,
    localNetworkDirect: localNetworkDirect,
  );
  final Map<String, dynamic> inbound =
      (tun['inbounds'] as List<Map<String, dynamic>>).single;
  final Map<String, dynamic> settings = <String, dynamic>{
    ...(inbound['settings'] as Map<String, dynamic>),
    'name': macosTunnelInterface,
  }..remove('desc');
  return <String, dynamic>{
    ...tun,
    'inbounds': <Map<String, dynamic>>[
      <String, dynamic>{...inbound, 'settings': settings},
    ],
  };
}

/// The byte counters of [interface] from `netstat -ibI`: its link row ends
/// with Ibytes, Opkts, Oerrs, Obytes, Coll.
TunnelTraffic? macosTunnelTraffic(String netstat, String interface) {
  for (final String line in const LineSplitter().convert(netstat)) {
    final List<String> fields = line.trim().split(RegExp(r'\s+'));
    if (fields.length >= 7 &&
        fields.first == interface &&
        fields.any((String field) => field.startsWith('<Link#'))) {
      final int? rx = int.tryParse(fields[fields.length - 5]);
      final int? tx = int.tryParse(fields[fields.length - 2]);
      if (rx != null && tx != null) {
        return TunnelTraffic(rxBytes: rx, txBytes: tx);
      }
    }
  }
  return null;
}

class MacosXrayRuntime {
  /// [runtimeDirectory] holds xray and its geo files; the app bundle's by
  /// default.
  MacosXrayRuntime({String? runtimeDirectory})
    : _runtimeDirectory =
          runtimeDirectory ??
          '${File(Platform.resolvedExecutable).parent.parent.path}'
              '/Frameworks/App.framework/Resources/flutter_assets/assets/macos_runtime';

  final String _runtimeDirectory;
  late final LinuxXrayRuntime probe = LinuxXrayRuntime(
    runtimeDirectory: _runtimeDirectory,
  );
  Directory? _state;
  int? _localPid;
  Timer? _trafficTimer;
  final StreamController<TunnelTraffic> _trafficController =
      StreamController<TunnelTraffic>.broadcast();

  Stream<TunnelTraffic> get traffic => _trafficController.stream;

  Future<void> start(
    String encodedConfig, {
    required bool proxyOnly,
    List<String>? routes,
  }) async {
    await stop();
    final Map<String, dynamic> source =
        jsonDecode(encodedConfig) as Map<String, dynamic>;
    for (final (String key, String name) in <(String, String)>[
      ('nebulaHysteriaConfig', 'Hysteria2'),
      ('nebulaAether', 'WARP'),
      ('nebulaDnsTunnel', 'The DNS tunnel'),
    ]) {
      if (source.containsKey(key)) {
        throw StateError('$name is not available on macOS yet.');
      }
    }
    final String xray = await _binary('xray');
    final Directory state = await linuxPrivateTemp('nebula-tun-');
    _state = state;
    try {
      final File configFile = File('${state.path}/xray.json');
      if (proxyOnly) {
        await configFile.writeAsString(jsonEncode(source));
        _localPid = (await Process.start(xray, <String>[
          'run',
          '-c',
          configFile.path,
        ], mode: ProcessStartMode.detached)).pid;
        return;
      }
      // The server by address: once the tunnel is up the system's DNS goes
      // through it, so Xray must not need the system to find its server.
      final String? host = macosUpstreamAddress(source);
      final String? upstreamIp =
          pinnedUpstream(source, host) ?? await _resolveIpv4(host);
      if (host == null || upstreamIp == null) {
        throw StateError('macOS could not resolve the VPN server address.');
      }
      final List<String> resolvers = windowsTunnelDnsServers(source);
      await configFile.writeAsString(
        jsonEncode(
          macosXrayTunConfig(
            windowsXrayPinnedUpstream(source, host, upstreamIp),
            localNetworkDirect: routesSkipLocalNetwork(routes),
          ),
        ),
      );
      final File helper = File('${state.path}/helper.sh');
      await helper.writeAsString(macosVpnHelperScript);
      // AppleScript quotes each argument for the shell itself.
      final ProcessResult result = await Process.run('/usr/bin/osascript', <
        String
      >[
        '-e',
        'on run argv',
        '-e',
        'set command to "/bin/bash"',
        '-e',
        'repeat with arg in argv',
        '-e',
        'set command to command & " " & quoted form of arg',
        '-e',
        'end repeat',
        '-e',
        'do shell script command with prompt "Nebula VPN wants to start '
            'the VPN." with administrator privileges',
        '-e',
        'end run',
        helper.path,
        'start',
        xray,
        configFile.path,
        state.path,
        '$pid',
        resolvers.join(','),
      ]);
      if (result.exitCode != 0) {
        final String error = await File(
          '${macosSessionOutputs(state.path)}/startup.error',
        ).readAsString().catchError((Object _) => '');
        throw StateError(
          error.isNotEmpty
              ? 'The VPN did not start: $error'
              : 'The VPN did not start (administrator access was not given).',
        );
      }
      _startTrafficMonitoring();
    } catch (_) {
      await stop();
      rethrow;
    }
  }

  Future<void> stop() async {
    _trafficTimer?.cancel();
    _trafficTimer = null;
    final int? local = _localPid;
    _localPid = null;
    if (local != null) {
      Process.killPid(local);
    }
    final Directory? state = _state;
    _state = null;
    if (state == null) {
      return;
    }
    final String out = macosSessionOutputs(state.path);
    if (await File('$out/routes-ready').exists()) {
      await File('${state.path}/stop').writeAsString('');
      final DateTime deadline = DateTime.now().add(
        const Duration(seconds: 10),
      );
      while (DateTime.now().isBefore(deadline) &&
          !await File('$out/stopped').exists()) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    try {
      await state.delete(recursive: true);
    } on FileSystemException {
      // The system sweeps its temp folder.
    }
  }

  Future<bool?> engineRunning() async {
    final Directory? state = _state;
    if (state == null) {
      return null;
    }
    if (_localPid != null) {
      return (await Process.run('/bin/ps', <String>['-p', '$_localPid']))
              .exitCode ==
          0;
    }
    return !await File(
      '${macosSessionOutputs(state.path)}/stopped',
    ).exists();
  }

  Future<List<String>> logs() async {
    final Directory? state = _state;
    if (state == null) {
      return const <String>[];
    }
    try {
      return await File(
        '${macosSessionOutputs(state.path)}/xray.log',
      ).readAsLines();
    } on FileSystemException {
      return const <String>[];
    }
  }

  void _startTrafficMonitoring() {
    _trafficTimer?.cancel();
    _trafficTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final ProcessResult result = await Process.run(
        '/usr/sbin/netstat',
        <String>['-ibI', macosTunnelInterface],
      );
      final TunnelTraffic? reading = macosTunnelTraffic(
        '${result.stdout}',
        macosTunnelInterface,
      );
      if (reading != null && !_trafficController.isClosed) {
        _trafficController.add(reading);
      }
    });
  }

  Future<String> _binary(String name) async {
    final String path = '$_runtimeDirectory/$name';
    if (!await File(path).exists()) {
      throw StateError(
        'Nebula runtime file "$name" is missing. Reinstall the app.',
      );
    }
    await Process.run('chmod', <String>['u+x', path]);
    return path;
  }

  static Future<String?> _resolveIpv4(String? host) async {
    if (host == null || host.isEmpty) return null;
    if (InternetAddress.tryParse(host)?.type == InternetAddressType.IPv4) {
      return host;
    }
    try {
      final List<InternetAddress> addresses = await InternetAddress.lookup(
        host,
        type: InternetAddressType.IPv4,
      );
      return addresses.isEmpty ? null : addresses.first.address;
    } on SocketException {
      return null;
    }
  }
}

/// The server the first outbound dials: under vnext (VLESS, VMess),
/// servers (Shadowsocks, Trojan) or, for MASQUE, the settings themselves.
String? macosUpstreamAddress(Map<String, dynamic> source) {
  try {
    final Map<String, dynamic> settings =
        ((source['outbounds'] as List<dynamic>).first
                as Map<String, dynamic>)['settings']
            as Map<String, dynamic>;
    final Object? servers = settings['vnext'] ?? settings['servers'];
    if (servers == null) {
      return settings['address'] as String?;
    }
    return ((servers as List<dynamic>).first as Map<String, dynamic>)['address']
        as String?;
  } on Object {
    return null;
  }
}
