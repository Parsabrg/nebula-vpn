import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'dns_tunnel_resolvers.dart';

/// The DNS tunnel's resolver scan on Windows and Linux: the bundled engine
/// run with `-scan-only`, as Android runs it, its output read here.
class DesktopDnsTunnelPlatform implements DnsTunnelPlatform {
  DesktopDnsTunnelPlatform({String? runtimeDirectory})
    : _runtime = runtimeDirectory ?? _bundledRuntime();

  static String _bundledRuntime() =>
      '${File(Platform.resolvedExecutable).parent.path}/data/flutter_assets/'
      'assets/${Platform.isWindows ? 'windows' : 'linux'}_runtime';

  final String _runtime;
  _Scan? _scan;
  List<(int, int)>? _iranRanges;

  /// A computer has no carrier to tell apart: one list.
  @override
  Future<String> networkKey() async => 'desktop';

  @override
  Future<List<bool>> inIran(List<String> addresses) async {
    final List<(int, int)> ranges = _iranRanges ??= await _loadIran();
    return addresses.map((String address) {
      final int? ip = _ipv4(address);
      return ip != null &&
          ranges.any(((int, int) r) => ip >= r.$1 && ip <= r.$2);
    }).toList();
  }

  Future<List<(int, int)>> _loadIran() async {
    try {
      return geoipRanges(await File('$_runtime/geoip.dat').readAsBytes(), 'IR');
    } on FileSystemException {
      return const <(int, int)>[];
    }
  }

  @override
  Future<void> startScan(String config, String resolvers, int stopAfter) async {
    await stopScan();
    final String engine =
        '$_runtime/${Platform.isWindows ? 'cottendns_client.exe' : 'cottendns_client'}';
    if (!await File(engine).exists()) {
      throw StateError('The bundled DNS tunnel engine is missing.');
    }
    if (!Platform.isWindows) {
      await Process.run('chmod', <String>['u+x', engine]);
    }
    // The config holds the tunnel key: a folder only this user can read.
    final Directory folder = await Directory.systemTemp.createTemp(
      'nebula-dnsscan-',
    );
    final File configFile = File('${folder.path}/cottendns.toml');
    final File resolverFile = File('${folder.path}/resolvers.txt');
    await configFile.writeAsString(config);
    await resolverFile.writeAsString(resolvers);
    // Detached: no console window on Windows; its output still comes here.
    final Process process = await Process.start(
      engine,
      <String>[
        '-config',
        configFile.path,
        '-resolvers',
        resolverFile.path,
        '-scan-only',
      ],
      workingDirectory: _runtime,
      mode: ProcessStartMode.detachedWithStdio,
    );
    final _Scan scan = _Scan(
      process,
      const LineSplitter().convert(resolvers).where((String l) {
        return l.trim().isNotEmpty;
      }).length,
    );
    _scan = scan;
    void onLine(String line) {
      if (scan.read(line) && scan.valid.length >= stopAfter) {
        process.kill();
      }
    }

    Future<void> drain(Stream<List<int>> stream) => stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(onLine)
        .asFuture<void>()
        .catchError((Object _) {});
    unawaited(
      Future.wait(<Future<void>>[
        drain(process.stdout),
        drain(process.stderr),
      ]).whenComplete(() async {
        scan.done = true;
        await folder.delete(recursive: true).catchError((Object _) => folder);
      }),
    );
  }

  @override
  Future<DnsTunnelScanProgress> scanProgress() async {
    final _Scan? scan = _scan;
    if (scan == null) {
      return const DnsTunnelScanProgress(
        tested: 0,
        total: 0,
        valid: <String>[],
        seen: <String>[],
        done: true,
      );
    }
    return DnsTunnelScanProgress(
      tested: scan.tested,
      total: scan.total,
      valid: List<String>.of(scan.valid),
      seen: List<String>.of(scan.seen),
      done: scan.done,
    );
  }

  @override
  Future<void> stopScan() async {
    _scan?.process.kill();
  }
}

class _Scan {
  _Scan(this.process, this.total);

  final Process process;
  final int total;
  final List<String> valid = <String>[];
  final List<String> seen = <String>[];
  int tested = 0;
  bool done = false;

  /// Takes one output line; true when it found a working resolver.
  bool read(String line) {
    final String? good = _after(line, 'WD_SCAN event=valid resolver=');
    final String? bad = _after(line, 'WD_SCAN event=rejected resolver=');
    if (good != null) {
      valid.add(good);
      seen.add(good);
      tested++;
      return true;
    }
    if (bad != null) {
      seen.add(bad);
      tested++;
    }
    return false;
  }

  static String? _after(String line, String marker) {
    final int at = line.indexOf(marker);
    return at < 0
        ? null
        : line.substring(at + marker.length).trim().split(' ').first;
  }
}

int? _ipv4(String address) {
  final List<String> parts = address.split('.');
  if (parts.length != 4) return null;
  int value = 0;
  for (final String part in parts) {
    final int? byte = int.tryParse(part);
    if (byte == null || byte < 0 || byte > 255) return null;
    value = value * 256 + byte;
  }
  return value;
}

/// [country]'s IPv4 ranges from a geoip.dat: a protobuf GeoIPList of GeoIP
/// (field 1) with country_code (1) and CIDRs (2) of ip bytes (1) and
/// prefix (2). Other countries are skipped unread.
List<(int, int)> geoipRanges(Uint8List data, String country) {
  final List<(int, int)> ranges = <(int, int)>[];
  final _Reader top = _Reader(data, 0, data.length);
  while (!top.atEnd) {
    final int key = top.varint();
    final int length = top.varint();
    final int start = top.at;
    top.at += length;
    if (key != (1 << 3 | 2)) continue;
    final _Reader entry = _Reader(data, start, start + length);
    String? code;
    final List<(int, int)> cidrs = <(int, int)>[];
    while (!entry.atEnd) {
      final int field = entry.varint();
      if (field & 7 == 0) {
        entry.varint();
        continue;
      }
      if (field & 7 != 2) break;
      final int size = entry.varint();
      final int from = entry.at;
      entry.at += size;
      if (field >> 3 == 1) {
        code = ascii.decode(data.sublist(from, from + size));
        if (code.toUpperCase() != country) break;
      } else if (field >> 3 == 2) {
        cidrs.add((from, from + size));
      }
    }
    if (code?.toUpperCase() != country) continue;
    for (final (int from, int end) in cidrs) {
      final _Reader cidr = _Reader(data, from, end);
      Uint8List? ip;
      int prefix = 0;
      while (!cidr.atEnd) {
        final int field = cidr.varint();
        if (field >> 3 == 1) {
          final int size = cidr.varint();
          ip = data.sublist(cidr.at, cidr.at + size);
          cidr.at += size;
        } else if (field >> 3 == 2) {
          prefix = cidr.varint();
        } else {
          break;
        }
      }
      if (ip == null || ip.length != 4 || prefix > 32) continue;
      final int base = ip.fold(0, (int v, int b) => v * 256 + b);
      final int size = 1 << (32 - prefix);
      final int first = base & ~(size - 1) & 0xffffffff;
      ranges.add((first, first + size - 1));
    }
    break;
  }
  return ranges;
}

class _Reader {
  _Reader(this.data, this.at, this.end);

  final Uint8List data;
  int at;
  final int end;

  bool get atEnd => at >= end;

  int varint() {
    int result = 0;
    int shift = 0;
    while (true) {
      if (at >= end) throw const FormatException('geoip.dat truncated');
      final int b = data[at++];
      result |= (b & 0x7f) << shift;
      if (b & 0x80 == 0) return result;
      shift += 7;
    }
  }
}
