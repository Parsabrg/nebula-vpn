import 'dart:io';

/// The command that starts [executable] so it ends when the app ends.
///
/// The engines the app starts on the desktop (the DNS tunnel, proxy-mode
/// Xray and Hysteria, Aether) are processes of their own, stopped by the
/// app on disconnect -- which a crash or a kill skips, and a DNS tunnel
/// engine was found running three days on.
/// Windows ends them through the job object the runner puts the app in. On
/// Linux a watcher does: the shell starts it in the background, then becomes
/// the engine (`exec`, so the engine keeps the pid the app tracks), and the
/// watcher ends the engine within a second of the app being gone. The
/// watcher's own output goes nowhere, so it never holds the engine's pipes
/// open.
(String, List<String>) ownedCommand(
  String executable,
  List<String> arguments, {
  int? ownerPid,
}) {
  if (!Platform.isLinux) {
    return (executable, arguments);
  }
  return (
    '/bin/sh',
    <String>[
      '-c',
      r'e=$$; o=$1; shift; '
          r'(while kill -0 "$o" 2>/dev/null && kill -0 "$e" 2>/dev/null; '
          r'do sleep 1; done; kill "$e" 2>/dev/null) '
          r'</dev/null >/dev/null 2>&1 & '
          r'exec "$@"',
      'nebula-engine',
      '${ownerPid ?? pid}',
      executable,
      ...arguments,
    ],
  );
}
