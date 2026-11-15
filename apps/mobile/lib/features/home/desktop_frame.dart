import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/free/free_mode.dart';
import '../../core/routing/route_paths.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/widgets/nebula/nebula_nav.dart';
import '../../l10n/app_localizations.dart';

/// The app's destinations, for the tab bar (phone) and the sidebar
/// (desktop): Connect, Devices, Account (Free without a server), and on
/// desktop Settings. [location] says which is current.
List<NebulaNavItem> appDestinations(
  BuildContext context,
  WidgetRef ref, {
  required String location,
  required bool withSettings,
  void Function(int branch)? goBranch,
}) {
  final AppText text = AppText.of(context);
  final bool free = ref.watch(freeModeProvider);
  final bool settings = location.startsWith(RoutePaths.homeSettings);
  void go(int branch, String path) =>
      goBranch != null ? goBranch(branch) : context.go(path);
  return <NebulaNavItem>[
    NebulaNavItem(
      label: text.tabConnect,
      icon: Icons.shield_outlined,
      selectedIcon: Icons.shield,
      selected: location.startsWith(RoutePaths.homeConnect),
      onTap: () => go(0, RoutePaths.homeConnect),
    ),
    if (!free)
      NebulaNavItem(
        label: text.tabDevices,
        icon: Icons.devices_outlined,
        selectedIcon: Icons.devices,
        selected: location.startsWith(RoutePaths.homeDevices),
        onTap: () => go(1, RoutePaths.homeDevices),
      ),
    NebulaNavItem(
      label: free ? text.freeTab : text.tabAccount,
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
      selected: location.startsWith(RoutePaths.homeAccount),
      onTap: () => go(2, RoutePaths.homeAccount),
    ),
    if (withSettings)
      NebulaNavItem(
        label: text.settingsTitle,
        // The design's sliders, not a gear (the gear is Account's way in).
        icon: Icons.tune,
        selectedIcon: Icons.tune,
        selected: settings,
        onTap: () => settings
            ? context.go(RoutePaths.homeSettings)
            : context.push(RoutePaths.homeSettings),
      ),
  ];
}

/// A pushed screen on desktop: the sidebar beside it, so a settings screen
/// does not take the whole window. On a phone, the screen as it is.
class DesktopFrame extends ConsumerWidget {
  const DesktopFrame({required this.location, required this.child, super.key});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!nebulaDesktopLayout(context)) {
      return child;
    }
    // A Material under the sidebar: without one its text had no default
    // style (Flutter's yellow underline) and the window showed black.
    return Material(
      color: context.palette.bg,
      child: Row(
        children: <Widget>[
          NebulaSideNav(
            items: appDestinations(
              context,
              ref,
              location: location,
              withSettings: true,
            ),
          ),
          Expanded(child: NebulaBesideSideNav(child: child)),
        ],
      ),
    );
  }
}
