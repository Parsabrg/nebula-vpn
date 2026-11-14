import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Cloudflare WARP (Aether) on Windows and Linux, run as the person, as on
/// Android.
///
/// In a full-device tunnel Aether's own traffic must not enter the tunnel it
/// carries. It dials out through [AetherBridge], a loopback SOCKS5 inbound
/// of the tunnel's Xray whose outbound leaves by the real network: bound to
/// it on Windows (`autoOutboundsInterface`), marked on Linux. UDP goes the
/// same way (SOCKS5 UDP associate).
///
/// With its identity on disk Aether dials IP addresses only (measured,
/// 2026-11-14); registering one looks the WARP API up by name, which inside
/// the tunnel would need the tunnel's DNS, carried by WARP itself. So the
/// identity is registered first, before the tunnel exists.

/// Where Aether keeps its identities and the last working gateway, kept
/// across sessions as Android keeps them in the app's files.
Directory aetherHome() {
  final Map<String, String> env = Platform.environment;
  final String base = Platform.isWindows
      ? '${env['LOCALAPPDATA'] ?? Directory.systemTemp.path}\\NebulaVPN\\aether'
      : '${env['XDG_DATA_HOME'] ?? '${env['HOME'] ?? Directory.systemTemp.path}/.local/share'}/nebula-vpn/aether';
  return Directory(base)..createSync(recursive: true);
}

/// The word Aether's `--register` takes for the protocol in [args].
String aetherRegisterWord(List<String> args) {
  if (args.contains('--gool-classic')) {
    return 'gool-classic';
  }
  final int at = args.indexOf('--protocol');
  return at < 0 || at + 1 >= args.length ? 'masque' : args[at + 1];
}

/// The loopback SOCKS5 inbound Aether dials out through, locked with a
/// password of its own: anything on this machine reaching it would leave
/// outside the tunnel.
class AetherBridge {
  AetherBridge(this.port) : user = _hex(8), password = _hex(16);

  final int port;
  final String user;
  final String password;

  String get upstream => 'socks5://$user:$password@127.0.0.1:$port';

  static String _hex(int bytes) {
    final Random random = Random.secure();
    return <String>[
      for (int i = 0; i < bytes; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }
}

const String _bridgeIn = 'aether-up';
const String _bridgeOut = 'aether-direct';

/// [config] (a full-device tunnel's, its inbounds already the TUN's) with
/// [bridge]'s inbound, a direct outbound for it, and the rule between them
/// first. [mark] is Linux's tunnel mark, which keeps the outbound out of the
/// tunnel there.
Map<String, dynamic> withAetherBridge(
  Map<String, dynamic> config,
  AetherBridge bridge, {
  int? mark,
}) {
  final Map<String, dynamic> routing =
      (config['routing'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  return <String, dynamic>{
    ...config,
    'inbounds': <dynamic>[
      ...((config['inbounds'] as List<dynamic>?) ?? <dynamic>[]),
      <String, dynamic>{
        'tag': _bridgeIn,
        'listen': '127.0.0.1',
        'port': bridge.port,
        'protocol': 'socks',
        'settings': <String, dynamic>{
          'auth': 'password',
          'accounts': <Map<String, String>>[
            <String, String>{'user': bridge.user, 'pass': bridge.password},
          ],
          'udp': true,
          'ip': '127.0.0.1',
        },
      },
    ],
    'outbounds': <dynamic>[
      ...((config['outbounds'] as List<dynamic>?) ?? <dynamic>[]),
      <String, dynamic>{
        'tag': _bridgeOut,
        'protocol': 'freedom',
        if (mark != null)
          'streamSettings': <String, dynamic>{
            'sockopt': <String, dynamic>{'mark': mark},
          },
      },
    ],
    'routing': <String, dynamic>{
      ...routing,
      'rules': <dynamic>[
        <String, dynamic>{
          'type': 'field',
          'inboundTag': <String>[_bridgeIn],
          'outboundTag': _bridgeOut,
        },
        ...((routing['rules'] as List<dynamic>?) ?? <dynamic>[]),
      ],
    },
  };
}

/// Registers the identity [args] name, unless it is there already (then
/// Aether returns at once). Run before the tunnel: see the top of this file.
Future<void> registerAether(
  String engine,
  List<String> args,
  void Function(String line) log,
) async {
  final Process process = await Process.start(
    engine,
    <String>[...args, '--register', aetherRegisterWord(args)],
    workingDirectory: aetherHome().path,
    mode: ProcessStartMode.detachedWithStdio,
  );
  bool ready = false;
  try {
    await Future.wait(<Future<void>>[
      for (final Stream<List<int>> output in <Stream<List<int>>>[
        process.stdout,
        process.stderr,
      ])
        output
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .forEach((String line) {
              log(line);
              ready = ready || line.contains('identities ready');
            })
            .catchError((Object _) {}),
    ]).timeout(const Duration(seconds: 60));
  } on TimeoutException {
    process.kill();
  }
  if (!ready) {
    throw StateError('Cloudflare WARP could not register this device.');
  }
}

/// Starts Aether and returns it once it serves SOCKS5, which it does only
/// after its scan and data check (21-25 s on the owner's line); its port
/// accepts connections before that, so the port is no sign. [upstream] is
/// the bridge, in a full-device tunnel.
Future<Process> startAether(
  String engine,
  List<String> args,
  String readyLine,
  void Function(String line) log, {
  String? upstream,
}) async {
  final Process process = await Process.start(
    engine,
    <String>[
      ...args,
      if (upstream != null) ...<String>['--upstream', upstream],
    ],
    workingDirectory: aetherHome().path,
    // No console window on Windows; its output is still read below, and
    // must be for as long as it runs, or a full pipe stalls it.
    mode: ProcessStartMode.detachedWithStdio,
  );
  // Also kept on disk, for the last session only: the in-app log is gone
  // with the session, and a WARP fault is often seen only after it ends.
  final IOSink file = File(
    '${aetherHome().path}${Platform.pathSeparator}aether.log',
  ).openWrite();
  final Completer<bool> serving = Completer<bool>();
  int open = 2;
  void onLine(String line) {
    log(line);
    file.writeln(line);
    if (!serving.isCompleted && line.contains(readyLine)) {
      file.writeln('== ${DateTime.now().toUtc().toIso8601String()} ready');
      serving.complete(true);
    }
  }

  void onDone() {
    if (--open == 0) {
      unawaited(file.close());
      if (!serving.isCompleted) {
        serving.complete(false);
      }
    }
  }

  for (final Stream<List<int>> output in <Stream<List<int>>>[
    process.stdout,
    process.stderr,
  ]) {
    output
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(onLine, onDone: onDone, onError: (Object _) {});
  }
  final bool ok = await serving.future.timeout(
    const Duration(seconds: 150),
    onTimeout: () => false,
  );
  if (!ok) {
    process.kill();
    throw StateError('Cloudflare WARP found no way through this network.');
  }
  return process;
}

/// Kills the Psiphon whose path ends with [binary] on Linux: Aether starts it, and a killed
/// Aether leaves it running (as on Windows, measured), still serving.
void killStrayPsiphon(String binary) {
  final Directory proc = Directory('/proc');
  if (!proc.existsSync()) {
    return;
  }
  for (final FileSystemEntity entry in proc.listSync(followLinks: false)) {
    final int? pid = int.tryParse(
      entry.uri.pathSegments.lastWhere((String s) => s.isNotEmpty),
    );
    if (pid == null) {
      continue;
    }
    try {
      final String command = File('${entry.path}/cmdline').readAsStringSync();
      if (command.split('\u0000').first.endsWith(binary)) {
        Process.killPid(pid, ProcessSignal.sigkill);
      }
    } on FileSystemException {
      // Gone, or not ours to read.
    }
  }
}

/// Windows: Aether with a hidden console of its own, returning its process
/// id once it serves. Started with no console at all (as the pipes of
/// [startAether] need), the Psiphon it runs got a new, visible terminal
/// window, and closing that window ended Psiphon and the connection. Its
/// output goes to aether.log, which is read for [readyLine].
Future<int> startAetherHidden(
  String engine,
  List<String> args,
  String readyLine,
  void Function(String line) log, {
  String? upstream,
}) async {
  final List<String> all = <String>[
    ...args,
    if (upstream != null) ...<String>['--upstream', upstream],
  ];
  if (all.any((String arg) => arg.contains('"') || arg.contains("'"))) {
    throw StateError('Cloudflare WARP got a setting it cannot take.');
  }
  final String home = aetherHome().path;
  final File out = File('$home\\aether.log');
  final File err = File('$home\\aether.err.log');
  String quoted(String value) => "'${value.replaceAll("'", "''")}'";
  // One command line, each argument in double quotes: Windows PowerShell
  // joins -ArgumentList items with bare spaces.
  final String commandLine = all.map((String a) => '"$a"').join(' ');
  final Process launcher = await Process.start('powershell.exe', <String>[
    '-NoProfile',
    '-NonInteractive',
    '-WindowStyle',
    'Hidden',
    '-Command',
    "(Start-Process -FilePath ${quoted(engine)} -ArgumentList ${quoted(commandLine)} "
        '-WorkingDirectory ${quoted(home)} -WindowStyle Hidden -PassThru '
        '-RedirectStandardOutput ${quoted(out.path)} '
        '-RedirectStandardError ${quoted(err.path)}).Id',
  ]);
  // Its first line, not its end: Aether inherits the launcher's pipes, so
  // they close only when Aether exits (a wait for them hung the connect).
  unawaited(launcher.stderr.drain<void>());
  final String first = await launcher.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .first
      .timeout(const Duration(seconds: 30), onTimeout: () => '')
      .catchError((Object _) => '');
  final int? pid = int.tryParse(first.trim());
  if (pid == null) {
    launcher.kill();
    throw StateError('Cloudflare WARP did not start.');
  }
  final Map<File, int> read = <File, int>{out: 0, err: 0};
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 150));
  while (DateTime.now().isBefore(deadline)) {
    for (final File file in read.keys.toList()) {
      try {
        final String text = await file.readAsString();
        if (text.length > read[file]!) {
          final String fresh = text.substring(read[file]!);
          read[file] = text.length;
          fresh
              .split('\n')
              .where((String l) => l.trim().isNotEmpty)
              .forEach((String l) => log(l.trimRight()));
          if (fresh.contains(readyLine)) {
            return pid;
          }
        }
      } on FileSystemException {
        // Not written yet.
      }
    }
    final ProcessResult alive = await Process.run('tasklist.exe', <String>[
      '/FI',
      'PID eq $pid',
      '/NH',
    ]);
    if (!(alive.stdout as String).contains('$pid')) {
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  await Process.run('taskkill.exe', <String>['/PID', '$pid', '/T', '/F']);
  throw StateError('Cloudflare WARP found no way through this network.');
}
