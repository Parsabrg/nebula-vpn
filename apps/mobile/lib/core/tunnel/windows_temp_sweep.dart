import 'dart:io';

/// Removes what this app's Windows and Linux tunnels left in the temp folder when the
/// app did not get to clean up after itself.
///
/// Each connect writes its config, credentials included, to a folder of its
/// own and removes it afterwards. Closed at the wrong moment, the app left
/// them behind: a WireGuard config with its private key from a connect still
/// waiting on the permission prompt, and an Xray config with its credential
/// from a session that stopped while the app was gone. Run when the app
/// starts, before it could have begun anything of its own.
///
/// A tunnel folder whose engine is still running is left alone: a tunnel can
/// outlive the app, and its supervisor is stopped through that folder.
Future<void> sweepStaleTunnelFolders({
  Directory? root,
  DateTime? now,
  Future<bool> Function(int pid)? running,
}) async {
  final Directory temp = root ?? Directory.systemTemp;
  final DateTime at = now ?? DateTime.now();
  final Future<bool> Function(int) alive = running ?? _processIsRunning;
  try {
    await for (final FileSystemEntity entity in temp.list(followLinks: false)) {
      if (entity is Directory && await _isStale(entity, at, alive)) {
        try {
          await entity.delete(recursive: true);
        } on FileSystemException {
          // In use or not ours to remove: the next start tries again.
        }
      }
    }
  } on FileSystemException {
    // A temp folder that cannot be listed has nothing this can clean.
  }
}

/// Probes last seconds; a folder older than this belongs to no running one.
const Duration _youngFolder = Duration(minutes: 10);

Future<bool> _isStale(
  Directory folder,
  DateTime now,
  Future<bool> Function(int) alive,
) async {
  final String name = folder.uri.pathSegments.lastWhere(
    (String segment) => segment.isNotEmpty,
  );
  final bool old =
      now.difference((await folder.stat()).modified) > _youngFolder;
  if (name.startsWith('nebula-wg-')) {
    // Lives for one connect only; the app is starting, so none is running.
    return true;
  }
  if (name.startsWith('nebula-probe-')) {
    return old;
  }
  if (!name.startsWith('nebula-tun-')) {
    return false;
  }
  if (await File('${folder.path}${Platform.pathSeparator}stopped').exists()) {
    return true;
  }
  final File pidFile = File('${folder.path}${Platform.pathSeparator}xray.pid');
  if (await pidFile.exists()) {
    final int? pid = int.tryParse((await pidFile.readAsString()).trim());
    return pid == null || !await alive(pid);
  }
  // Never got as far as starting its engine, or a local proxy's, which
  // keeps no pid here.
  return old;
}

Future<bool> _processIsRunning(int pid) async {
  if (Platform.isLinux) {
    return Directory('/proc/$pid').exists();
  }
  try {
    final ProcessResult result = await Process.run('tasklist.exe', <String>[
      '/FI',
      'PID eq $pid',
      '/NH',
    ]);
    return (result.stdout as String).contains('$pid');
  } on ProcessException {
    // Cannot tell: keep the folder rather than pull one from under a tunnel.
    return true;
  }
}

/// Stops the speed and protocol-test engines a Windows app left running:
/// quit during a protocol test, 59 xray.exe and a resolver scan stayed up
/// with nobody to stop them (2026-11-13). Each runs from a nebula-probe- or
/// nebula-dnsscan- folder, which no tunnel uses. Run when the app starts --
/// only one runs at a time, so none of them is its own -- and when it exits.
Future<void> stopStaleProbes() async {
  if (!Platform.isWindows) {
    return;
  }
  try {
    await Process.run('powershell.exe', <String>[
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      "Get-CimInstance Win32_Process -Filter \"Name='xray.exe' or "
          "Name='hysteria.exe' or Name='cottendns_client.exe'\" | "
          "Where-Object { \$_.CommandLine -match 'nebula-probe-|nebula-dnsscan-' } | "
          'ForEach-Object { Stop-Process -Id \$_.ProcessId -Force '
          '-ErrorAction SilentlyContinue }',
    ]);
  } on ProcessException {
    // Housekeeping only.
  }
}
