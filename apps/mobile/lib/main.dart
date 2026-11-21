import 'dart:async';
import 'dart:io' show Platform, SecurityContext;

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'core/auth/auth_notifier.dart';
import 'core/free/free_mode.dart';
import 'core/licenses/bundled_licenses.dart';
import 'core/network/public_roots.dart';
import 'core/pairing/pairing.dart';
import 'core/pairing/pairing_providers.dart';
import 'core/pairing/pairing_store.dart';
import 'core/storage/storage_providers.dart';
import 'core/tunnel/windows_temp_sweep.dart';
import 'core/window/desktop_tray_manager.dart';
import 'core/window/login_item.dart';
import 'src/nebula_app.dart';

DesktopTrayManager? _trayManager;

/// Set by Exit, so the close it asks for is not turned into a hide.
bool _exiting = false;

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  registerBundledLicenses();
  addPublicRoots(SecurityContext.defaultContext);

  if (Platform.isWindows) {
    final Window? window = WindowManager.instance.getCurrent();
    if (window != null) {
      // The redesign's desktop window: wide enough for the sidebar layout
      // (900 px and up). Narrower than that it shows the phone layout. The
      // standard title bar stays: what Windows users expect of a utility.
      window.title = 'Nebula VPN';
      window.minimumSize = const Size(380, 640).toNative();
      window.setSize(const Size(1040, 700).toNative(), false);
      window.center();
      // Started at sign-in: stay in the tray until opened from there.
      if (!arguments.contains(startHiddenArgument)) {
        window.show();
        window.focus();
      }

      // Close button hides to tray instead of killing the app, so the VPN
      // connection stays up when the user dismisses the window. Exit from
      // the tray lets the close through.
      window.addListener((WindowEvent event) {
        if (event is WindowCloseRequestedEvent && !_exiting) {
          event.request.cancel();
          window.hide();
        }
      });

      _trayManager = DesktopTrayManager(
        onShowWindow: _showWindow,
        onExit: () async {
          await stopStaleProbes();
          await _trayManager?.dispose();
          _exiting = true;
          window.close();
        },
      );
      await _trayManager!.init();
    }
  }
  if (Platform.isWindows || Platform.isLinux) {
    // Not awaited: nothing on screen waits for it.
    unawaited(sweepStaleTunnelFolders());
    unawaited(stopStaleProbes());
  }

  final SharedPreferences preferences = await SharedPreferences.getInstance();
  // Before the first frame, so the first request already goes to the paired
  // deployment -- or, unpaired, nowhere.
  final Pairing? pairing;
  try {
    pairing = await FlutterSecurePairingStore().read();
  } on PlatformException catch (error) {
    // Linux keeps secrets in the desktop's Secret Service; a desktop without
    // one (a bare window manager, some minimal installs) used to crash here.
    if (!Platform.isLinux) rethrow;
    runApp(_KeyringMissingApp(detail: error.message ?? error.code));
    return;
  }

  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(preferences),
      storedPairingProvider.overrideWithValue(pairing),
      storedFreeModeProvider.overrideWithValue(
        preferences.getBool(freeModeKey) ?? false,
      ),
    ],
    // Riverpod 3 retries a failed provider on its own, with backoff, up to ten
    // times. Every load here already has its own failure state and a Try
    // again the person presses, and a silent retry loop would both hide the
    // failure behind a spinner and send the same refused request to the API
    // over and over. Off, which is the behaviour the app was built against.
    retry: (int retryCount, Object error) => null,
  );

  // Deliberately not awaited: the app renders immediately (showing the
  // splash screen, since AuthNotifier.build()'s initial state is
  // AuthAuthenticating) while bootstrap runs in the background. Awaiting it
  // here would block the first frame until the refresh call resolves,
  // defeating the point of having a splash screen at all. Called once, here
  // -- not from any widget's build/initState -- so there is exactly one
  // bootstrap attempt per process start, independent of widget rebuilds.
  unawaited(container.read(authNotifierProvider.notifier).bootstrap());

  runApp(
    UncontrolledProviderScope(container: container, child: const NebulaApp()),
  );
}

/// Shows the window and makes sure it is painted. Started hidden at sign-in
/// and opened from the tray, the window stayed white: Flutter had not drawn
/// into it while it was hidden. A forced frame
/// and a one-pixel size nudge make it draw.
Future<void> _showWindow() async {
  final Window? window = WindowManager.instance.getCurrent();
  if (window == null) return;
  window.show();
  window.focus();
  WidgetsBinding.instance.scheduleForcedFrame();
  final Size size = window.size.toSize();
  window.setSize(Size(size.width + 1, size.height).toNative(), false);
  window.setSize(size.toNative(), false);
}

/// Shown instead of the app when Linux has nowhere safe to keep the pairing.
class _KeyringMissingApp extends StatelessWidget {
  const _KeyringMissingApp({required this.detail});

  final String detail;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Nebula VPN',
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: SelectableText(
            'Nebula VPN needs a keyring to store its sign-in safely.\n\n'
            'Install and start GNOME Keyring or KWallet (the package is '
            'usually "gnome-keyring"), sign out and back in, then open '
            'Nebula VPN again.\n\n$detail',
          ),
        ),
      ),
    ),
  );
}
