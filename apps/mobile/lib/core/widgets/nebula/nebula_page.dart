import 'package:flutter/material.dart';

import '../../theme/color_tokens.dart';
import '../../theme/look.dart';
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
  final double width = MediaQuery.sizeOf(context).width;
  final double side = width >= 900
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
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final NebulaPalette p = context.palette;
    final bool minimal = p.look == NebulaLook.minimal;
    final EdgeInsets pad = nebulaPagePadding(context);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: pad.copyWith(bottom: 24),
                children: <Widget>[
                  Padding(
                    padding: EdgeInsets.only(top: 16, left: minimal ? 0 : 4),
                    child: Row(
                      children: <Widget>[
                        if (showBack) const NebulaBackButton(),
                        const Spacer(),
                        ?trailing,
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(minimal ? 0 : 4, 4, 0, 4),
                    child: Semantics(
                      header: true,
                      child: Text(title, style: nebulaTitleStyle(p)),
                    ),
                  ),
                  ...children,
                ],
              ),
            ),
            if (footer != null)
              Padding(
                padding: pad.copyWith(top: 12, bottom: 16),
                child: footer,
              ),
          ],
        ),
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
