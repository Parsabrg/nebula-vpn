import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../theme/color_tokens.dart';
import '../../theme/look.dart';
import 'nebula_surface.dart';

/// Windows and Linux at 900 dp and wider: a sidebar instead of the tab bar
/// and a centred content column (DESIGN_SPEC §3, desktop shell).
bool nebulaDesktopLayout(BuildContext context) =>
    (Platform.isWindows || Platform.isLinux) &&
    MediaQuery.sizeOf(context).width >= 900;

/// One destination in the tab bar or the sidebar.
class NebulaNavItem {
  const NebulaNavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.onTap,
    required this.selected,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final VoidCallback onTap;
  final bool selected;
}

/// The wordmark: mono capitals on Minimal, "Nebula" at 20 px elsewhere. Not
/// localised: it is the product's name.
class NebulaBrand extends StatelessWidget {
  const NebulaBrand({super.key});

  @override
  Widget build(BuildContext context) {
    final NebulaPalette p = context.palette;
    return p.look == NebulaLook.minimal
        ? Text(
            'NEBULA',
            style: TextStyle(
              fontFamily: 'GeistMono',
              fontSize: 13,
              height: 18 / 13,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.2,
              color: p.textMuted,
            ),
          )
        : Text(
            'Nebula',
            style: TextStyle(
              fontSize: 20,
              height: 26 / 20,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
              color: p.textPrimary,
            ),
          );
  }
}

/// The phone tab bar. Minimal: icon and label side by side, a 2 px accent
/// bar on the active tab. Liquid glass: a floating pill. Soft cards: plain.
/// Expressive: a tonal pill behind the active icon.
class NebulaTabBar extends StatelessWidget {
  const NebulaTabBar({required this.items, super.key});

  final List<NebulaNavItem> items;

  @override
  Widget build(BuildContext context) {
    final NebulaPalette p = context.palette;
    final List<Widget> tabs = <Widget>[
      for (final NebulaNavItem item in items) Expanded(child: _Tab(item: item)),
    ];
    // The system inset goes below the bar, not inside it: inside a fixed
    // height, 3-button navigation cut the icons in half.
    switch (p.look) {
      case NebulaLook.minimal:
        return _plain(
          p,
          height: 60,
          color: p.canvas,
          border: true,
          children: tabs,
        );
      case NebulaLook.soft:
        return _plain(
          p,
          height: 64,
          color: p.canvas,
          border: true,
          children: tabs,
        );
      case NebulaLook.expressive:
        return _plain(
          p,
          height: 80,
          color: p.surface,
          border: false,
          children: tabs,
        );
      case NebulaLook.glass:
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            // Pages scroll under the tab bar: the one panel that blurs.
            child: NebulaPanel(
              blur: true,
              radius: 32,
              child: SizedBox(
                height: 64,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Row(
                    children: <Widget>[
                      for (int i = 0; i < tabs.length; i++) ...<Widget>[
                        if (i > 0) const SizedBox(width: 4),
                        tabs[i],
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
    }
  }

  Widget _plain(
    NebulaPalette p, {
    required double height,
    required Color color,
    required bool border,
    required List<Widget> children,
  }) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      border: border ? Border(top: BorderSide(color: p.hairline)) : null,
    ),
    child: SafeArea(
      top: false,
      child: SizedBox(
        height: height,
        child: Row(children: children),
      ),
    ),
  );
}

class _Tab extends StatelessWidget {
  const _Tab({required this.item});

  final NebulaNavItem item;

  @override
  Widget build(BuildContext context) {
    final NebulaPalette p = context.palette;
    final bool on = item.selected;
    final Color labelColor = on ? p.textPrimary : p.textMuted;
    final IconData icon = on ? item.selectedIcon : item.icon;
    // Shrinks to fit rather than cut: Russian "Подключение" did not fit a
    // third of a phone beside an icon.
    Widget label(double size) => Flexible(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          item.label,
          maxLines: 1,
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w500,
            color: labelColor,
          ),
        ),
      ),
    );

    late final Widget body;
    BorderRadius radius = BorderRadius.zero;
    switch (p.look) {
      case NebulaLook.minimal:
        body = DecoratedBox(
          decoration: BoxDecoration(
            border: on
                ? Border(top: BorderSide(color: p.blue, width: 2))
                : const Border(),
          ),
          // The full tab height, so the selected line sits on the bar's top
          // edge as designed, not just above the icon.
          child: SizedBox.expand(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, size: 20, color: on ? p.blueText : labelColor),
                const SizedBox(width: 8),
                label(13),
              ],
            ),
          ),
        );
      case NebulaLook.glass:
        radius = BorderRadius.circular(26);
        body = DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: on
                ? (p.isDark ? const Color(0x29FFFFFF) : const Color(0xF2FFFFFF))
                : Colors.transparent,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 22, color: on ? p.blueText : labelColor),
              const SizedBox(height: 2),
              label(12),
            ],
          ),
        );
      case NebulaLook.soft:
        body = Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 22, color: on ? p.blueText : labelColor),
            const SizedBox(height: 4),
            label(12),
          ],
        );
      case NebulaLook.expressive:
        body = Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 56,
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: on
                    ? nebulaMix(p.blue, p.isDark ? 30 : 22, p.surface)
                    : Colors.transparent,
              ),
              child: Icon(icon, size: 22, color: labelColor),
            ),
            const SizedBox(height: 4),
            label(12),
          ],
        );
    }
    return NebulaPressable(
      onTap: item.onTap,
      selected: on,
      semanticLabel: item.label,
      excludeChildSemantics: true,
      borderRadius: radius,
      child: body,
    );
  }
}

/// The sidebar's width.
const double nebulaSideNavWidth = 220;

/// Marks content laid out beside the desktop sidebar, so its page padding
/// centres the column in the space right of the sidebar rather than in the
/// whole window (which left a 380 px column in a 1040 px window).
class NebulaBesideSideNav extends InheritedWidget {
  const NebulaBesideSideNav({required super.child, super.key});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NebulaBesideSideNav>() != null;

  @override
  bool updateShouldNotify(NebulaBesideSideNav oldWidget) => false;
}

/// The desktop sidebar: 220 wide, the brand, then the destinations; the
/// current one tinted (with a 2 px accent bar on Minimal).
class NebulaSideNav extends StatelessWidget {
  const NebulaSideNav({required this.items, super.key});

  final List<NebulaNavItem> items;

  @override
  Widget build(BuildContext context) {
    final NebulaPalette p = context.palette;
    final Widget column = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 20),
            child: NebulaBrand(),
          ),
          for (final NebulaNavItem item in items) ...<Widget>[
            _SideItem(item: item),
            const SizedBox(height: 2),
          ],
        ],
      ),
    );
    return SizedBox(
      width: nebulaSideNavWidth,
      child: switch (p.look) {
        NebulaLook.minimal => DecoratedBox(
          decoration: BoxDecoration(
            border: Border(right: BorderSide(color: p.hairline)),
          ),
          child: column,
        ),
        NebulaLook.glass => Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 0, 12),
          child: NebulaPanel(child: column),
        ),
        NebulaLook.expressive => ColoredBox(color: p.surface, child: column),
        NebulaLook.soft => column,
      },
    );
  }
}

class _SideItem extends StatelessWidget {
  const _SideItem({required this.item});

  final NebulaNavItem item;

  @override
  Widget build(BuildContext context) {
    final NebulaPalette p = context.palette;
    final bool on = item.selected;
    final BorderRadius radius = BorderRadius.circular(switch (p.look) {
      NebulaLook.expressive => 22,
      NebulaLook.minimal => 8,
      _ => p.radiusSm + 2,
    });
    final Color? fill = !on
        ? null
        : switch (p.look) {
            NebulaLook.minimal => p.subtle,
            NebulaLook.glass =>
              p.isDark ? const Color(0x24FFFFFF) : const Color(0xF2FFFFFF),
            NebulaLook.soft => p.surface,
            NebulaLook.expressive => nebulaMix(
              p.blue,
              p.isDark ? 28 : 20,
              p.surface,
            ),
          };
    return NebulaPressable(
      onTap: item.onTap,
      selected: on,
      semanticLabel: item.label,
      excludeChildSemantics: true,
      borderRadius: radius,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: radius,
          // Minimal's 2 px accent bar, as an inset shadow would draw it:
          // Flutter has no one-sided border with rounded corners.
          boxShadow: on && p.look == NebulaLook.minimal
              ? <BoxShadow>[
                  BoxShadow(color: p.blue, offset: const Offset(-2, 0)),
                ]
              : null,
        ),
        child: Row(
          children: <Widget>[
            Icon(
              on ? item.selectedIcon : item.icon,
              size: 20,
              color: on ? p.blueText : p.textMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: on ? p.textPrimary : p.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
