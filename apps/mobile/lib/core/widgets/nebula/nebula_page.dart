import 'package:material_ui/material_ui.dart';

import '../../theme/color_tokens.dart';
import '../../theme/look.dart';
import 'nebula_nav.dart';
import 'nebula_surface.dart';

/// The page title: 28/34, weight 500 on Minimal and 600 elsewhere;
/// Expressive 30/36 at 500.
TextStyle nebulaTitleStyle(NebulaPalette p) => TextStyle(
  fontSize: p.look == NebulaLook.expressive ? 30 : 28,
  height: p.look == NebulaLook.expressive ? 36 / 30 : 34 / 28,
  fontWeight: p.look == NebulaLook.minimal || p.look == NebulaLook.expressive
      ? FontWeight.w500
      : FontWeight.w600,
  letterSpacing: -0.6,
  color: p.textPrimary,
);

/// Horizontal page padding: 24 on Minimal, 16 on the other looks; on a wide
/// window, a centred column up to 600 wide (DESIGN_SPEC §3, desktop shell).
EdgeInsets nebulaPagePadding(BuildContext context) {
  final NebulaPalette p = context.palette;
  final double window = MediaQuery.sizeOf(context).width;
  // The column is centred in the space beside the sidebar, not the window.
  final double width =
      window - (NebulaBesideSideNav.of(context) ? nebulaSideNavWidth : 0);
  final double side = window >= 900
      ? ((width - 600) / 2).clamp(32, double.infinity).toDouble()
      : (p.look == NebulaLook.minimal ? 24 : 16);
  return EdgeInsets.symmetric(horizontal: side);
}

/// A pushed screen: a back button, a large title, then [children] in a
/// scrolling column, and an optional [footer] pinned below.
class NebulaPage extends StatelessWidget {
  const NebulaPage({
    required this.title,
    required this.children,
    super.key,
    this.footer,
    this.trailing,
    this.showBack = true,
  });

  final String title;
  final List<Widget> children;
  final Widget? footer;
  final Widget? trailing;

  /// False for a tab's own page (Devices, Account): the tab header, the
  /// title beside its action, instead of a back button above the title.
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final NebulaPalette p = context.palette;
    final bool minimal = p.look == NebulaLook.minimal;
    final EdgeInsets pad = nebulaPagePadding(context);
    final Widget heading = Semantics(
      header: true,
      child: Text(title, style: nebulaTitleStyle(p)),
    );
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: pad.copyWith(bottom: 24),
                children: <Widget>[
                  if (showBack) ...<Widget>[
                    // The design's pushTop: 28 above the back button, 16 on
                    // a compact phone.
                    Padding(
                      padding: EdgeInsets.only(
                        top: nebulaCompact(context) ? 16 : 28,
                        bottom: 4,
                      ),
                      child: Row(
                        children: <Widget>[
                          const NebulaBackButton(),
                          const Spacer(),
                          ?trailing,
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsetsDirectional.fromSTEB(
                        minimal ? 0 : 4,
                        4,
                        0,
                        4,
                      ),
                      child: heading,
                    ),
                  ] else
                    NebulaTabHeader(title: heading, action: trailing),
                  ...children,
                ],
              ),
            ),
            if (footer != null)
              Padding(
                padding: pad.copyWith(
                  top: 12,
                  bottom: nebulaDesktopLayout(context)
                      ? 28
                      : p.look == NebulaLook.glass
                      ? 12
                      : 16,
                ),
                child: footer,
              ),
          ],
        ),
      ),
    );
  }
}

/// The design's compact phone (320 wide): less space above headers.
bool nebulaCompact(BuildContext context) =>
    MediaQuery.sizeOf(context).width < 340;

/// A tab's header row: [title] (the brand or the page title) and an
/// optional [action], 48 high, 32 below the top on a phone, 28 on desktop,
/// 20 on a compact phone.
class NebulaTabHeader extends StatelessWidget {
  const NebulaTabHeader({required this.title, super.key, this.action});

  final Widget title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final NebulaPalette p = context.palette;
    final double top = nebulaCompact(context)
        ? 20
        : nebulaDesktopLayout(context)
        ? 28
        : 32;
    final double side = p.look == NebulaLook.minimal ? 0 : 4;
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: 4, left: side, right: side),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: title,
              ),
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}

/// The 44 px icon button at the end of a tab header ("+" on Connect, the
/// gear on Account): bare on Minimal and Soft cards, where it sits 10 past
/// the column so the glyph lines up with the edge; a glass circle on Liquid
/// glass; a tonal rounded square on Expressive.
class NebulaHeaderAction extends StatelessWidget {
  const NebulaHeaderAction({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final NebulaPalette p = context.palette;
    final Widget glyph = Icon(icon, size: 24, color: p.textPrimary);
    final Widget button = switch (p.look) {
      NebulaLook.glass => NebulaPanel(
        radius: 22,
        child: SizedBox.square(dimension: 44, child: Center(child: glyph)),
      ),
      NebulaLook.expressive => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: p.subtle,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(child: glyph),
      ),
      NebulaLook.minimal || NebulaLook.soft => Transform.translate(
        offset: Offset(
          Directionality.of(context) == TextDirection.rtl ? -10 : 10,
          0,
        ),
        child: SizedBox.square(dimension: 44, child: Center(child: glyph)),
      ),
    };
    return Tooltip(
      message: label,
      child: NebulaPressable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        semanticLabel: label,
        excludeChildSemantics: true,
        child: button,
      ),
    );
  }
}

/// The 44 px back button: bare on Minimal and Soft cards, a glass circle on
/// Liquid glass, a tonal circle on Expressive.
class NebulaBackButton extends StatelessWidget {
  const NebulaBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    final NebulaPalette p = context.palette;
    final Widget icon = Icon(
      Directionality.of(context) == TextDirection.rtl
          ? Icons.arrow_forward
          : Icons.arrow_back,
      size: 22,
      color: p.textPrimary,
    );
    final Widget circle = switch (p.look) {
      NebulaLook.glass => NebulaPanel(
        radius: 22,
        child: SizedBox.square(dimension: 44, child: Center(child: icon)),
      ),
      NebulaLook.expressive => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: p.subtle, shape: BoxShape.circle),
        child: Center(child: icon),
      ),
      NebulaLook.minimal || NebulaLook.soft => Transform.translate(
        offset: const Offset(-10, 0),
        child: SizedBox.square(dimension: 44, child: Center(child: icon)),
      ),
    };
    return NebulaPressable(
      onTap: () => Navigator.of(context).maybePop(),
      borderRadius: BorderRadius.circular(22),
      semanticLabel: MaterialLocalizations.of(context).backButtonTooltip,
      excludeChildSemantics: true,
      child: circle,
    );
  }
}
