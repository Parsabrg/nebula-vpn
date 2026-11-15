import 'dart:ui';

import 'package:flutter/material.dart';

import '../../theme/color_tokens.dart';
import '../../theme/look.dart';

/// [c] mixed into [base] at [percent] (CSS `color-mix(in srgb, c p%, base)`).
Color nebulaMix(Color c, double percent, Color base) =>
    Color.lerp(base, c, percent / 100)!;

/// A tint of [c] over the ground it sits on: the card on Soft cards and
/// Expressive, the background elsewhere.
Color nebulaTint(NebulaPalette p, Color c, double percent) => nebulaMix(
  c,
  percent,
  p.look == NebulaLook.soft || p.look == NebulaLook.expressive
      ? p.surface
      : p.canvas,
);

/// The look's container: nothing on Minimal, a translucent blurred panel on
/// Liquid glass (solid with Reduce transparency), a solid card on Soft and
/// Expressive.
class NebulaPanel extends StatelessWidget {
  const NebulaPanel({
    required this.child,
    super.key,
    this.radius,
    this.padding,
    this.color,
  });

  final Widget child;
  final double? radius;
  final EdgeInsetsGeometry? padding;

  /// A fill of its own, instead of the look's.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final NebulaPalette p = context.palette;
    final double r = radius ?? p.radiusMd;
    final BorderRadius corners = BorderRadius.circular(r);
    final Widget inner = padding == null
        ? child
        : Padding(padding: padding!, child: child);
    switch (p.look) {
      case NebulaLook.minimal:
        return color == null
            ? inner
            : DecoratedBox(
                decoration: BoxDecoration(color: color, borderRadius: corners),
                child: inner,
              );
      case NebulaLook.soft:
      case NebulaLook.expressive:
        return DecoratedBox(
          decoration: BoxDecoration(
            color: color ?? p.surface,
            borderRadius: corners,
          ),
          child: inner,
        );
      case NebulaLook.glass:
        final bool dark = p.isDark;
        final BoxDecoration decoration = BoxDecoration(
          color: color ?? p.surface,
          borderRadius: corners,
          border: Border.all(
            color: p.solidPanels
                ? (dark ? const Color(0x1AFFFFFF) : const Color(0xFFDADCE8))
                : (dark ? const Color(0x24FFFFFF) : const Color(0xE6FFFFFF)),
          ),
          boxShadow: p.solidPanels
              ? null
              : <BoxShadow>[
                  BoxShadow(
                    color: dark
                        ? const Color(0x47000000)
                        : const Color(0x1A28326E),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
        );
        if (p.solidPanels) {
          return DecoratedBox(decoration: decoration, child: inner);
        }
        // The blur is the expensive part, so only here, clipped to the
        // panel; Reduce transparency (above) has none at all. The shadow is
        // painted outside the panel only: under a see-through panel it
        // showed through as a dark band along the bottom.
        return CustomPaint(
          painter: _OuterShadow(
            shadow: decoration.boxShadow!.first,
            corners: corners,
          ),
          child: ClipRRect(
            borderRadius: corners,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: DecoratedBox(
                decoration: decoration.copyWith(boxShadow: <BoxShadow>[]),
                child: inner,
              ),
            ),
          ),
        );
    }
  }
}

/// A box shadow drawn only outside a rounded rectangle, as a CSS
/// box-shadow is. Flutter's own fills under the box, which shows through a
/// translucent panel.
class _OuterShadow extends CustomPainter {
  const _OuterShadow({required this.shadow, required this.corners});

  final BoxShadow shadow;
  final BorderRadius corners;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect box = corners.toRRect(Offset.zero & size);
    canvas.save();
    canvas.clipPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect((Offset.zero & size).inflate(shadow.blurRadius * 3)),
        Path()..addRRect(box),
      ),
    );
    canvas.drawRRect(
      box.shift(shadow.offset).inflate(shadow.spreadRadius),
      Paint()
        ..color = shadow.color
        // CSS blur B is a Gaussian of sigma B / 2.
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, shadow.blurRadius / 2),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OuterShadow old) =>
      old.shadow != shadow || old.corners != corners;
}

/// A tap target with the redesign's interaction states: an overlay in the
/// text colour at 6% on hover and 12% pressed, and a 2 px accent focus ring
/// for the keyboard (DESIGN_SPEC §1.6-7).
class NebulaPressable extends StatefulWidget {
  const NebulaPressable({
    required this.child,
    required this.onTap,
    super.key,
    this.borderRadius = BorderRadius.zero,
    this.semanticLabel,
    this.selected,
    this.toggled,
    this.excludeChildSemantics = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final String? semanticLabel;
  final bool? selected;
  final bool? toggled;
  final bool excludeChildSemantics;

  @override
  State<NebulaPressable> createState() => _NebulaPressableState();
}

class _NebulaPressableState extends State<NebulaPressable> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final NebulaPalette p = context.palette;
    final bool enabled = widget.onTap != null;
    return Semantics(
      button: widget.toggled == null,
      enabled: enabled,
      selected: widget.selected,
      toggled: widget.toggled,
      label: widget.semanticLabel,
      excludeSemantics: widget.excludeChildSemantics,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: widget.borderRadius,
          onFocusChange: (bool focused) => setState(() => _focused = focused),
          splashFactory: NoSplash.splashFactory,
          overlayColor: WidgetStateProperty.resolveWith((
            Set<WidgetState> states,
          ) {
            if (!enabled) {
              return null;
            }
            if (states.contains(WidgetState.pressed)) {
              return p.textPrimary.withValues(alpha: 0.12);
            }
            if (states.contains(WidgetState.hovered)) {
              return p.textPrimary.withValues(alpha: 0.06);
            }
            return Colors.transparent;
          }),
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius,
              border: _focused
                  ? Border.all(color: p.blue, width: 2)
                  : const Border.fromBorderSide(BorderSide.none),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
