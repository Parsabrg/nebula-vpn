import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/auth/auth_notifier.dart';
import '../../core/auth/auth_state.dart';
import '../../core/free/free_mode.dart';
import '../../core/routing/home_branches.dart';
import '../../core/routing/route_paths.dart';
import '../../core/storage/storage_providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/widgets/nebula/nebula_nav.dart';
import '../../core/wireguard/tunnel_controller.dart';
import '../devices/devices_controller.dart';
import 'desktop_frame.dart';

/// The authenticated area's shell: three tabs over a hairline.
///
/// Connect, Devices, Account. Settings is deliberately not a tab -- it is
/// pushed from Account with a back arrow, because it is somewhere you go to
/// change something and then leave, not one of the three places the app is
/// about.
///
/// Each branch keeps its own navigation stack via [StatefulNavigationShell],
/// so switching tabs does not lose a tab's scroll position or its pushed
/// screens.
///
/// Also where the tunnel notification's Disconnect button is answered: the
/// tap opens the app on whichever tab was last showing, so it is handled
/// here rather than by one of them.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  StreamSubscription<void>? _disconnectRequests;

  @override
  void initState() {
    super.initState();
    _disconnectRequests = ref
        .read(tunnelControllerProvider)
        .disconnectRequests()
        .listen((_) {
          ref
              .read(devicesControllerProvider.notifier)
              .disconnectFromNotification(
                ref.read(deviceIdStoreProvider).read(),
              );
        });
  }

  @override
  void dispose() {
    _disconnectRequests?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final StatefulNavigationShell navigationShell = widget.navigationShell;
    final NebulaPalette palette = context.palette;

    // The session ended without this device asking: revoked by an admin,
    // or the account disabled. The router leaves for sign-in; the tunnel
    // must not stay up behind it, carrying nothing.
    final bool free = ref.watch(freeModeProvider);
    ref.listen<AuthState>(authNotifierProvider, (
      AuthState? previous,
      AuthState next,
    ) {
      // With no server there is no session to lose.
      if (free) {
        return;
      }
      if (next is AuthSessionExpired || next is AuthUnauthenticated) {
        unawaited(
          ref.read(devicesControllerProvider.notifier).endAfterSessionLost(),
        );
      }
      // The server answers again: a tunnel raised from a saved credential
      // while it could not be reached is replaced by a fresh one.
      if (previous is AuthUnreachable && next is AuthAuthenticated) {
        unawaited(
          ref
              .read(devicesControllerProvider.notifier)
              .refreshAfterOffline(ref.read(deviceIdStoreProvider).read()),
        );
      }
    });

    final List<String> roots = <String>[
      RoutePaths.homeConnect,
      RoutePaths.homeDevices,
      RoutePaths.homeAccount,
    ];
    // A tab tap lands on that tab's main page, however deep it was left:
    // several screens into Connection details, tapping Connect did nothing
    // (owner, 2026-11-15), because those screens are pushed straight onto
    // the tab's navigator, which the router's own reset leaves alone.
    void goBranch(int index) {
      popHomeBranch(ref, index);
      navigationShell.goBranch(index, initialLocation: true);
    }

    final bool desktop = nebulaDesktopLayout(context);
    final List<NebulaNavItem> items = appDestinations(
      context,
      ref,
      location: roots[navigationShell.currentIndex],
      // Settings is a tab wherever it would otherwise be hard to find: on a
      // narrow desktop window (phone layout, no sidebar) and in free mode,
      // where it sat at the bottom of the Free page, out of sight (owner,
      // 2026-11-20).
      withSettings: desktop || free || Platform.isWindows || Platform.isLinux,
      goBranch: goBranch,
    );
    if (desktop) {
      return Scaffold(
        backgroundColor: palette.bg,
        body: Row(
          children: <Widget>[
            NebulaSideNav(items: items),
            Expanded(child: NebulaBesideSideNav(child: navigationShell)),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: palette.bg,
      body: navigationShell,
      bottomNavigationBar: NebulaTabBar(items: items),
    );
  }
}
