import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/storage_providers.dart';
import 'dns_tunnel_engine.dart';
import 'dns_tunnel_sync.dart';

/// Where a scan is: resolvers tested so far, how many carry the tunnel.
@immutable
class DnsTunnelScanProgress {
  const DnsTunnelScanProgress({
    required this.tested,
    required this.total,
    required this.valid,
    required this.seen,
    required this.done,
    this.error,
  });

  factory DnsTunnelScanProgress.fromMap(Map<Object?, Object?> map) =>
      DnsTunnelScanProgress(
        tested: map['tested'] as int? ?? 0,
        total: map['total'] as int? ?? 0,
        valid: _strings(map['valid']),
        seen: _strings(map['seen']),
        done: map['done'] as bool? ?? true,
        error: map['error'] as String?,
      );

  static List<String> _strings(Object? value) =>
      (value as List<Object?>? ?? const <Object?>[])
          .whereType<String>()
          .toList();

  final int tested;
  final int total;
  final List<String> valid;
  final List<String> seen;
  final bool done;
  final String? error;
}

/// The phone side the resolver lists need: the engine's scan, which network
/// the phone is on, and which addresses are in Iran.
abstract interface class DnsTunnelPlatform {
  /// `wifi`, `mobile-<MCC><MNC>` or `other`.
  Future<String> networkKey();
  Future<List<bool>> inIran(List<String> addresses);
  Future<void> startScan(String config, String resolvers, int stopAfter);
  Future<DnsTunnelScanProgress> scanProgress();
  Future<void> stopScan();
}

class ChannelDnsTunnelPlatform implements DnsTunnelPlatform {
  const ChannelDnsTunnelPlatform();

  static const MethodChannel _channel = MethodChannel(
    'org.nebulavpn/wireguard_tunnel',
  );

  @override
  Future<String> networkKey() async =>
      await _channel.invokeMethod<String>('networkKey') ?? 'other';

  @override
  Future<List<bool>> inIran(List<String> addresses) async =>
      (await _channel.invokeMethod<List<Object?>>('inIran', <String, Object>{
                'addresses': addresses,
              }) ??
              const <Object?>[])
          .map((Object? v) => v == true)
          .toList();

  @override
  Future<void> startScan(String config, String resolvers, int stopAfter) =>
      _channel.invokeMethod<void>('dnsTunnelScanStart', <String, Object>{
        'config': config,
        'resolvers': resolvers,
        'stopAfter': stopAfter,
      });

  @override
  Future<DnsTunnelScanProgress> scanProgress() async =>
      DnsTunnelScanProgress.fromMap(
        await _channel.invokeMethod<Map<Object?, Object?>>(
              'dnsTunnelScanProgress',
            ) ??
            const <Object?, Object?>{},
      );

  @override
  Future<void> stopScan() => _channel.invokeMethod<void>('dnsTunnelScanStop');
}

/// What a running scan is for, shown beside its progress.
enum DnsTunnelScanKind { quick, growing, full }

/// The DNS tunnel's resolvers, one list per network: each mobile carrier,
/// and Wi-Fi as one (telling Wi-Fi networks apart needs the location
/// permission). The candidates are the person's own pasted list, saved
/// once, or CottenDNS's Iran list.
///
/// A quick test stops at [quickTarget] working; the rest is then tested in
/// the background, slowly, until [growTarget] work with at least
/// [iranTarget] inside Iran -- in a shutdown, resolvers abroad go first.
/// Each network's list is retested once it is a week old, while on it.
class DnsTunnelResolvers extends ChangeNotifier {
  DnsTunnelResolvers(
    this._preferences, {
    this._platform = const ChannelDnsTunnelPlatform(),
    Future<String> Function()? bundled,
    DateTime Function()? now,
    this._pollEvery = const Duration(milliseconds: 500),
    Random? random,
  }) : _bundled = bundled ?? _loadBundled,
       _now = now ?? DateTime.now,
       _random = random ?? Random();

  /// The person's resolver sets, `{name: list}`, and the one in use (none:
  /// the bundled list). Choosing another set keeps every other.
  static const String setsKey = 'nebula.dns_tunnel.sets';
  static const String activeKey = 'nebula.dns_tunnel.active';
  static const String _builtIn = '#built-in';

  /// Each set has its own working list per network.
  String listKey(String network) =>
      'nebula.dns_tunnel.resolvers.${active ?? _builtIn}/$network';
  String scannedAtKey(String network) =>
      'nebula.dns_tunnel.scanned_at.${active ?? _builtIn}/$network';

  static const int quickTarget = 10;
  static const int growTarget = 30;
  static const int iranTarget = 10;
  static const Duration maxAge = Duration(days: 7);

  /// A test someone waits for runs wide; growth runs narrow, beside a
  /// tunnel that may be in use.
  static const int quickParallelism = 64;
  static const int growParallelism = 8;

  final SharedPreferences _preferences;
  final DnsTunnelPlatform _platform;
  final Future<String> Function() _bundled;
  final DateTime Function() _now;
  final Duration _pollEvery;
  final Random _random;
  final Map<String, bool> _iran = <String, bool>{};

  int _generation = 0;
  DnsTunnelScanProgress? progress;
  DnsTunnelScanKind? scanning;

  /// The network last looked up, for screens that cannot wait for one.
  String? network;

  static Future<String> _loadBundled() =>
      rootBundle.loadString('assets/dns_tunnel/resolvers_ir.txt');

  Map<String, String> get _sets {
    try {
      return (jsonDecode(_preferences.getString(setsKey) ?? '{}')
              as Map<String, dynamic>)
          .cast<String, String>();
    } on FormatException {
      return <String, String>{};
    }
  }

  Future<void> _saveSets(Map<String, String> sets) =>
      _preferences.setString(setsKey, jsonEncode(sets));

  /// The saved sets' names, A to Z.
  List<String> get setNames => _sets.keys.toList()..sort();

  /// The set in use, or null for the bundled list.
  String? get active {
    final String? name = _preferences.getString(activeKey);
    return name != null && _sets.containsKey(name) ? name : null;
  }

  /// The set in use's list as saved, or null for the bundled list.
  String? get source => active == null ? null : _sets[active];
  bool get custom => active != null;

  /// The bundled list's text, for showing it.
  Future<String> builtInList() => _bundled();

  /// Uses [name]'s set, or the bundled list for null. Nothing is deleted.
  Future<void> select(String? name) async {
    _endScan();
    await _platform.stopScan();
    if (name == null) {
      await _preferences.remove(activeKey);
    } else {
      await _preferences.setString(activeKey, name);
    }
    await _classify(network == null ? const <String>[] : workingOn(network!));
    notifyListeners();
  }

  /// Saves [resolvers] under [name] (replacing a set of that name) and
  /// uses it.
  Future<void> saveAs(String name, List<String> resolvers) async {
    await _saveSets(<String, String>{
      ..._sets,
      name: '${resolvers.join('\n')}\n',
    });
    await select(name);
  }

  /// Deletes [name]'s set and its tested lists; the bundled list is used
  /// if it was in use.
  Future<void> deleteSet(String name) async {
    final Map<String, String> sets = _sets..remove(name);
    await _saveSets(sets);
    for (final String key in _preferences.getKeys().toList()) {
      if (key.startsWith('nebula.dns_tunnel.resolvers.$name/') ||
          key.startsWith('nebula.dns_tunnel.scanned_at.$name/')) {
        await _preferences.remove(key);
      }
    }
    if (_preferences.getString(activeKey) == name) {
      await select(null);
    } else {
      notifyListeners();
    }
  }

  /// A name not yet taken: "My list", "My list 2", ...
  String freeName(String base) {
    final Set<String> taken = _sets.keys.toSet();
    if (!taken.contains(base)) {
      return base;
    }
    int n = 2;
    while (taken.contains('$base $n')) {
      n++;
    }
    return '$base $n';
  }

  List<String> workingOn(String network) =>
      _lines(_preferences.getString(listKey(network)) ?? '');

  DateTime? scannedAtOn(String network) {
    final int? millis = _preferences.getInt(scannedAtKey(network));
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  int iranCountOn(String network) =>
      workingOn(network).where((String r) => _iran[r] ?? false).length;

  Future<String> currentNetwork() async {
    final String here = await _platform.networkKey();
    if (here != network) {
      network = here;
      await _classify(workingOn(here));
      notifyListeners();
    }
    return here;
  }

  /// Resolver addresses in [text]: IPv4, IPv4:port or [IPv6]:port,
  /// separated by lines, spaces, commas or semicolons; anything else is
  /// left out.
  static List<String> parse(String text) {
    final RegExp ipv4 = RegExp(r'^(\d{1,3}\.){3}\d{1,3}(:\d{1,5})?$');
    final RegExp ipv6 = RegExp(r'^\[[0-9a-fA-F:]+\](:\d{1,5})?$');
    return <String>{
      for (final String token in text.split(RegExp(r'[\s,;]+')))
        if (ipv4.hasMatch(token) || ipv6.hasMatch(token)) token,
    }.toList();
  }

  /// The form the engine reports a resolver in: always with a port.
  static String normalise(String resolver) {
    if (resolver.startsWith('[')) {
      return resolver.endsWith(']') ? '$resolver:53' : resolver;
    }
    return resolver.contains(':') ? resolver : '$resolver:53';
  }

  static List<String> _lines(String text) =>
      text.split('\n').where((String l) => l.trim().isNotEmpty).toList();

  Future<List<String>> _candidates() async =>
      _lines(source ?? await _bundled());

  /// Saves [resolvers] into the set in use -- pasted once, kept even when
  /// none work today. With the bundled list in use, they become a new set
  /// named [newName].
  Future<void> saveSource(
    List<String> resolvers, {
    String newName = 'My list',
  }) async {
    final String? name = active;
    if (name == null) {
      await saveAs(freeName(newName), resolvers);
      return;
    }
    await _saveSets(<String, String>{
      ..._sets,
      name: '${resolvers.join('\n')}\n',
    });
    notifyListeners();
  }

  /// What the tunnel starts from on [network]: its tested list, else every
  /// candidate (the engine then finds its own).
  Future<String> current(String network) async {
    final List<String> working = workingOn(network);
    return working.isNotEmpty
        ? '${working.join('\n')}\n'
        : '${(await _candidates()).join('\n')}\n';
  }

  /// Before a connect: the current network's list, retested first when it
  /// is missing or a week old (for at most [limit]). Returns the network.
  Future<String> ensureFresh(
    DnsTunnelDetails details, {
    Duration limit = const Duration(seconds: 30),
  }) async {
    final String here = await currentNetwork();
    final DateTime? at = scannedAtOn(here);
    if (at == null || _now().difference(at) >= maxAge) {
      await quickTest(details, limit: limit);
    }
    return here;
  }

  /// On opening the app: the same, but only on Wi-Fi.
  Future<void> refreshIfDue(DnsTunnelDetails details) async {
    try {
      final String here = await currentNetwork();
      final DateTime? at = scannedAtOn(here);
      if (here == 'wifi' && (at == null || _now().difference(at) >= maxAge)) {
        await quickTest(details, limit: const Duration(seconds: 60));
      }
    } catch (_) {
      // Housekeeping; the previous list stays as useful as it was.
    }
  }

  /// Tests the candidates, shuffled, until [quickTarget] work; keeps them
  /// for this network and goes on in the background. Returns how many
  /// worked.
  Future<int> quickTest(DnsTunnelDetails details, {Duration? limit}) async {
    final int generation = ++_generation;
    final String here = await currentNetwork();
    final List<String> candidates = (await _candidates())..shuffle(_random);
    final DnsTunnelScanProgress result = await _scan(
      details,
      candidates,
      generation: generation,
      kind: DnsTunnelScanKind.quick,
      stopAfter: quickTarget,
      parallelism: quickParallelism,
      limit: limit,
    );
    if (result.valid.isNotEmpty) {
      await _keep(here, result.valid, replace: true);
    }
    if (generation == _generation) {
      unawaited(_grow(details, here, generation, candidates, result.seen));
    }
    return result.valid.length;
  }

  /// Every candidate, each kept if it works. Wi-Fi only: never on mobile
  /// data. Returns how many worked, or null when not on Wi-Fi.
  Future<int?> fullScan(DnsTunnelDetails details) async {
    final String here = await currentNetwork();
    if (here != 'wifi') {
      return null;
    }
    final int generation = ++_generation;
    final DnsTunnelScanProgress result = await _scan(
      details,
      await _candidates(),
      generation: generation,
      kind: DnsTunnelScanKind.full,
      stopAfter: 1 << 30,
      parallelism: quickParallelism,
    );
    if (result.valid.isNotEmpty) {
      await _keep(here, result.valid, replace: true);
    }
    return result.valid.length;
  }

  /// Stops whatever is being tested; what was found is kept.
  Future<void> stop() async {
    _endScan();
    await _platform.stopScan();
  }

  /// Leaves any running scan behind: the screen is idle at once, and the
  /// abandoned one's own cleanup no longer applies (it checks this number).
  void _endScan() {
    _generation++;
    scanning = null;
    notifyListeners();
  }

  Future<void> _grow(
    DnsTunnelDetails details,
    String here,
    int generation,
    List<String> candidates,
    List<String> seen,
  ) async {
    try {
      final Set<String> tested = seen.map(normalise).toSet();
      bool enough() =>
          workingOn(here).length >= growTarget &&
          iranCountOn(here) >= iranTarget;
      bool enoughIran() => iranCountOn(here) >= iranTarget;
      final List<(List<String>, bool Function())> pools =
          <(List<String>, bool Function())>[
            (candidates, enough),
            // Still short inside Iran: the bundled list is all Iranian.
            (_lines(await _bundled()), enoughIran),
          ];
      for (final (List<String> pool, bool Function() done) in pools) {
        final List<String> rest = pool
            .where((String r) => !tested.contains(normalise(r)))
            .toList();
        if (done() || rest.isEmpty || generation != _generation) {
          continue;
        }
        final DnsTunnelScanProgress result = await _scan(
          details,
          rest,
          generation: generation,
          kind: DnsTunnelScanKind.growing,
          stopAfter: 1 << 30,
          parallelism: growParallelism,
          enough: (List<String> valid) async {
            if (valid.isNotEmpty) {
              await _keep(here, valid);
            }
            return done();
          },
        );
        if (result.valid.isNotEmpty) {
          await _keep(here, result.valid);
        }
        tested.addAll(result.seen.map(normalise));
      }
    } catch (_) {
      // Background work: what was kept stays.
    }
  }

  Future<void> _classify(List<String> resolvers) async {
    final List<String> unknown = resolvers
        .where((String r) => !_iran.containsKey(r))
        .toList();
    if (unknown.isEmpty) {
      return;
    }
    final List<bool> answers = await _platform.inIran(unknown);
    for (int i = 0; i < unknown.length && i < answers.length; i++) {
      _iran[unknown[i]] = answers[i];
    }
  }

  /// Adds [found] to [network]'s list, or replaces it with them.
  Future<void> _keep(
    String network,
    List<String> found, {
    bool replace = false,
  }) async {
    final List<String> merged = <String>{
      if (!replace) ...workingOn(network),
      ...found,
    }.toList();
    await _classify(merged);
    await _preferences.setString(listKey(network), '${merged.join('\n')}\n');
    await _preferences.setInt(
      scannedAtKey(network),
      _now().millisecondsSinceEpoch,
    );
    notifyListeners();
  }

  Future<DnsTunnelScanProgress> _scan(
    DnsTunnelDetails details,
    List<String> resolvers, {
    required int generation,
    required DnsTunnelScanKind kind,
    required int stopAfter,
    required int parallelism,
    Duration? limit,
    Future<bool> Function(List<String> valid)? enough,
  }) async {
    scanning = kind;
    progress = DnsTunnelScanProgress(
      tested: 0,
      total: resolvers.length,
      valid: const <String>[],
      seen: const <String>[],
      done: false,
    );
    notifyListeners();
    final DateTime started = _now();
    DnsTunnelScanProgress latest = progress!;
    try {
      await _platform.startScan(
        renderDnsTunnelConfig(details, 1, scanParallelism: parallelism),
        '${resolvers.join('\n')}\n',
        stopAfter,
      );
      bool stopping = false;
      while (true) {
        await Future<void>.delayed(_pollEvery);
        // A newer scan replaced this one (the engine runs one at a time):
        // what this one found so far is its answer.
        if (generation != _generation) {
          return latest;
        }
        latest = await _platform.scanProgress();
        progress = latest;
        notifyListeners();
        if (latest.done) {
          if (latest.error != null) {
            throw StateError(latest.error!);
          }
          return latest;
        }
        final bool overTime =
            limit != null && _now().difference(started) >= limit;
        if (!stopping &&
            (overTime || (enough != null && await enough(latest.valid)))) {
          stopping = true;
          await _platform.stopScan();
        }
      }
    } finally {
      if (generation == _generation) {
        scanning = null;
        notifyListeners();
      }
    }
  }
}

/// The resolvers the running DNS tunnel uses now, read every few seconds
/// while something shows them.
final dnsTunnelActiveResolversProvider =
    StreamProvider.autoDispose<List<String>>((Ref ref) async* {
      const MethodChannel channel = MethodChannel(
        'org.nebulavpn/wireguard_tunnel',
      );
      while (true) {
        try {
          yield (await channel.invokeMethod<List<Object?>>('dnsTunnelActive') ??
                  const <Object?>[])
              .whereType<String>()
              .toList();
        } catch (_) {
          yield const <String>[];
        }
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    });

final dnsTunnelResolversProvider = Provider<DnsTunnelResolvers>((Ref ref) {
  final DnsTunnelResolvers resolvers = DnsTunnelResolvers(
    ref.watch(sharedPreferencesProvider),
  );
  ref.onDispose(resolvers.dispose);
  return resolvers;
});
