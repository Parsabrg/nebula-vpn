import 'package:material_ui/material_ui.dart';

import 'look.dart';

/// The app's colours, radii and surfaces for one look, mode and accent, as a
/// theme extension.
///
/// The values are the redesign's (nebula-redesign/reference/source/
/// app_tokens.js, `makeTokens()`); [resolve] computes them. A widget reads
/// one object, and light and dark cannot drift apart: a token added to one
/// is a compile error until the other has it too.
///
/// The fields from before the redesign are kept and mapped onto the new
/// tokens, so a screen not yet redesigned takes every look as it is:
/// [blue] and [blueText] are the accent, [hairline] the line, [amber] the
/// warning colour and [red] the danger one.
@immutable
class NebulaPalette extends ThemeExtension<NebulaPalette> {
  const NebulaPalette({
    required this.bg,
    required this.surface,
    required this.hairline,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textMax,
    required this.textMuted,
    required this.blue,
    required this.blueText,
    required this.onAccent,
    required this.amber,
    required this.amberText,
    required this.amberDim,
    required this.red,
    required this.redText,
    required this.dotOff,
    required this.look,
    required this.canvas,
    required this.subtle,
    required this.dialog,
    required this.ok,
    required this.onDanger,
    required this.radiusSm,
    required this.radiusMd,
    required this.radiusLg,
    required this.radiusButton,
    required this.solidPanels,
    this.backdrop,
  });

  /// Screen background. Transparent on Liquid glass, whose [backdrop] is
  /// painted once behind every screen.
  final Color bg;

  /// Cards, panels, fields: the look's container fill.
  final Color surface;

  /// Row rules and separators (the token set's `line`).
  final Color hairline;

  /// Input borders.
  final Color border;

  /// Outlines that must read as a control: secondary buttons, switches off.
  final Color borderStrong;

  /// Text (`ink`).
  final Color textPrimary;

  /// The state word when protected. The same as [textPrimary] since the
  /// redesign; kept for the screens that read it.
  final Color textMax;

  /// Secondary text, labels, inactive tabs.
  final Color textMuted;

  /// The accent, as a fill.
  final Color blue;

  /// The accent, as text and icons.
  final Color blueText;

  /// Text and icons on an accent fill.
  final Color onAccent;

  /// Warning: not protected.
  final Color amber;
  final Color amberText;
  final Color amberDim;

  /// Destructive, failure.
  final Color red;
  final Color redText;

  /// The status dot when disconnected.
  final Color dotOff;

  final NebulaLook look;

  /// An opaque background: menus, the tab bar, anything that must hide what
  /// is behind it (on Liquid glass [bg] is transparent).
  final Color canvas;

  /// The second surface: icon tiles, meter tracks, selected segments
  /// (the token set's `s2`).
  final Color subtle;

  /// Dialog fill.
  final Color dialog;

  /// Protected, OK.
  final Color ok;

  /// Text on a [red] fill.
  final Color onDanger;

  final double radiusSm;
  final double radiusMd;
  final double radiusLg;
  final double radiusButton;

  /// Liquid glass with "Reduce transparency" on: solid panels, no blur.
  final bool solidPanels;

  /// Liquid glass's background, painted behind every screen; null on the
  /// other looks.
  final GlassBackdropColors? backdrop;

  bool get isDark =>
      ThemeData.estimateBrightnessForColor(canvas) == Brightness.dark;

  /// Minimal, dark, blue: the default.
  static const NebulaPalette dark = NebulaPalette(
    bg: Color(0xFF0B0B0F),
    surface: Color(0xFF14141A),
    hairline: Color(0xFF22222B),
    border: Color(0xFF6A6A78),
    borderStrong: Color(0xFF6A6A78),
    textPrimary: Color(0xFFEDEDF2),
    textMax: Color(0xFFEDEDF2),
    textMuted: Color(0xFF9A9AA6),
    blue: Color(0xFF8CA4FF),
    blueText: Color(0xFF8CA4FF),
    onAccent: Color(0xFF0B0B0F),
    amber: Color(0xFFE8B24A),
    amberText: Color(0xFFE8B24A),
    amberDim: Color(0xFFE8B24A),
    red: Color(0xFFFF8A80),
    redText: Color(0xFFFF8A80),
    dotOff: Color(0xFF9A9AA6),
    look: NebulaLook.minimal,
    canvas: Color(0xFF0B0B0F),
    subtle: Color(0xFF1B1B23),
    dialog: Color(0xFF16161C),
    ok: Color(0xFF6FD3A0),
    onDanger: Color(0xFF1A0505),
    radiusSm: 8,
    radiusMd: 12,
    radiusLg: 12,
    radiusButton: 12,
    solidPanels: false,
  );

  /// Minimal, light, blue.
  static const NebulaPalette light = NebulaPalette(
    bg: Color(0xFFF7F7F9),
    surface: Color(0xFFFFFFFF),
    hairline: Color(0xFFE1E1E7),
    border: Color(0xFF8A8A96),
    borderStrong: Color(0xFF8A8A96),
    textPrimary: Color(0xFF101014),
    textMax: Color(0xFF101014),
    textMuted: Color(0xFF55555F),
    blue: Color(0xFF2A46BE),
    blueText: Color(0xFF2A46BE),
    onAccent: Color(0xFFFFFFFF),
    amber: Color(0xFF8A5A00),
    amberText: Color(0xFF8A5A00),
    amberDim: Color(0xFF8A5A00),
    red: Color(0xFFB42318),
    redText: Color(0xFFB42318),
    dotOff: Color(0xFF55555F),
    look: NebulaLook.minimal,
    canvas: Color(0xFFF7F7F9),
    subtle: Color(0xFFECECF0),
    dialog: Color(0xFFFFFFFF),
    ok: Color(0xFF12703F),
    onDanger: Color(0xFFFFFFFF),
    radiusSm: 8,
    radiusMd: 12,
    radiusLg: 12,
    radiusButton: 12,
    solidPanels: false,
  );

  /// The palette for [look] in [brightness] with [accent]; [reduceTransparency]
  /// only changes Liquid glass.
  factory NebulaPalette.resolve({
    required NebulaLook look,
    required Brightness brightness,
    NebulaAccent accent = NebulaAccent.blue,
    bool reduceTransparency = false,
  }) {
    final bool dark = brightness == Brightness.dark;
    final Color a = accent.on(brightness);
    final Color onA = dark ? const Color(0xFF0B0B0F) : const Color(0xFFFFFFFF);
    final Color ok = dark ? const Color(0xFF6FD3A0) : const Color(0xFF12703F);
    final Color warn = dark ? const Color(0xFFE8B24A) : const Color(0xFF8A5A00);
    final Color danger = dark
        ? const Color(0xFFFF8A80)
        : const Color(0xFFB42318);
    final Color onDanger = dark
        ? const Color(0xFF1A0505)
        : const Color(0xFFFFFFFF);

    late final _Surfaces p;
    late final List<double> r;
    GlassBackdropColors? backdrop;
    bool solid = false;
    switch (look) {
      case NebulaLook.minimal:
        p = dark
            ? const _Surfaces(
                bg: Color(0xFF0B0B0F),
                ink: Color(0xFFEDEDF2),
                muted: Color(0xFF9A9AA6),
                line: Color(0xFF22222B),
                s2: Color(0xFF1B1B23),
                strong: Color(0xFF6A6A78),
                dialog: Color(0xFF16161C),
                surface: Color(0xFF14141A),
              )
            : const _Surfaces(
                bg: Color(0xFFF7F7F9),
                ink: Color(0xFF101014),
                muted: Color(0xFF55555F),
                line: Color(0xFFE1E1E7),
                s2: Color(0xFFECECF0),
                strong: Color(0xFF8A8A96),
                dialog: Color(0xFFFFFFFF),
                surface: Color(0xFFFFFFFF),
              );
        r = const <double>[8, 12, 12, 12];
      case NebulaLook.glass:
        solid = reduceTransparency;
        p = dark
            ? _Surfaces(
                bg: const Color(0xFF08080E),
                ink: const Color(0xFFFFFFFF),
                muted: const Color(0xB8FFFFFF),
                line: const Color(0x1AFFFFFF),
                s2: const Color(0x1FFFFFFF),
                strong: const Color(0x73FFFFFF),
                dialog: const Color(0xFF1C1D29),
                surface: solid
                    ? const Color(0xFF1A1B26)
                    : const Color(0x12FFFFFF),
              )
            : _Surfaces(
                bg: const Color(0xFFEEF0F7),
                ink: const Color(0xFF101014),
                muted: const Color(0xB3101014),
                line: const Color(0x14101014),
                s2: const Color(0xBFFFFFFF),
                strong: const Color(0x6B101014),
                dialog: const Color(0xFFFFFFFF),
                surface: solid
                    ? const Color(0xFFFFFFFF)
                    : const Color(0x9EFFFFFF),
              );
        r = const <double>[10, 20, 22, 26];
        // Two soft radial glows over the base (§2); none when solid, so
        // panels and background read as two clear layers.
        backdrop = solid
            ? null
            : GlassBackdropColors(
                base: p.bg,
                // The prototype's glows (0.32/0.20 dark, 0.40/0.32 light)
                // at 90% and 50%: at full strength accent, warning, OK and
                // danger text fell below 4.5:1 where a glow is brightest
                // (test/core/theme/contrast_test.dart).
                first: dark ? const Color(0x496E8BFF) : const Color(0x338CA4FF),
                second: dark
                    ? const Color(0x2EB06EFF)
                    : const Color(0x29D2AAFF),
              );
      case NebulaLook.soft:
        p = dark
            ? const _Surfaces(
                bg: Color(0xFF0E0F12),
                ink: Color(0xFFEDEDF2),
                muted: Color(0xFFA3A3AF),
                line: Color(0xFF2A2B32),
                s2: Color(0xFF26272E),
                strong: Color(0xFF6E6E7A),
                surface: Color(0xFF1B1C21),
                dialog: Color(0xFF1F2026),
              )
            : const _Surfaces(
                bg: Color(0xFFF1F2F6),
                ink: Color(0xFF101014),
                muted: Color(0xFF55555F),
                line: Color(0xFFECEDF1),
                s2: Color(0xFFE7E8EE),
                strong: Color(0xFF8E8E9A),
                surface: Color(0xFFFFFFFF),
                dialog: Color(0xFFFFFFFF),
              );
        r = const <double>[10, 20, 24, 16];
      case NebulaLook.expressive:
        p = dark
            ? const _Surfaces(
                bg: Color(0xFF111318),
                ink: Color(0xFFE2E2E9),
                muted: Color(0xFFC4C6D0),
                line: Color(0xFF111318),
                s2: Color(0xFF282B34),
                strong: Color(0xFF8E909A),
                surface: Color(0xFF1D2027),
                dialog: Color(0xFF262931),
              )
            : const _Surfaces(
                bg: Color(0xFFF9F9FF),
                ink: Color(0xFF1A1B21),
                muted: Color(0xFF45464F),
                line: Color(0xFFF9F9FF),
                s2: Color(0xFFE1E2EC),
                strong: Color(0xFF74777F),
                surface: Color(0xFFECEDF6),
                dialog: Color(0xFFF0F0FA),
              );
        r = const <double>[12, 20, 28, 26];
    }

    return NebulaPalette(
      bg: backdrop != null ? Colors.transparent : p.bg,
      surface: p.surface,
      hairline: p.line,
      border: p.strong,
      borderStrong: p.strong,
      textPrimary: p.ink,
      textMax: p.ink,
      textMuted: p.muted,
      blue: a,
      blueText: a,
      onAccent: onA,
      amber: warn,
      amberText: warn,
      amberDim: warn,
      red: danger,
      redText: danger,
      dotOff: p.muted,
      look: look,
      canvas: p.bg,
      subtle: p.s2,
      dialog: p.dialog,
      ok: ok,
      onDanger: onDanger,
      radiusSm: r[0],
      radiusMd: r[1],
      radiusLg: r[2],
      radiusButton: r[3],
      solidPanels: solid,
      backdrop: backdrop,
    );
  }

  @override
  NebulaPalette copyWith({
    Color? bg,
    Color? surface,
    Color? hairline,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textMax,
    Color? textMuted,
    Color? blue,
    Color? blueText,
    Color? onAccent,
    Color? amber,
    Color? amberText,
    Color? amberDim,
    Color? red,
    Color? redText,
    Color? dotOff,
  }) {
    return NebulaPalette(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      hairline: hairline ?? this.hairline,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textMax: textMax ?? this.textMax,
      textMuted: textMuted ?? this.textMuted,
      blue: blue ?? this.blue,
      blueText: blueText ?? this.blueText,
      onAccent: onAccent ?? this.onAccent,
      amber: amber ?? this.amber,
      amberText: amberText ?? this.amberText,
      amberDim: amberDim ?? this.amberDim,
      red: red ?? this.red,
      redText: redText ?? this.redText,
      dotOff: dotOff ?? this.dotOff,
      look: look,
      canvas: canvas,
      subtle: subtle,
      dialog: dialog,
      ok: ok,
      onDanger: onDanger,
      radiusSm: radiusSm,
      radiusMd: radiusMd,
      radiusLg: radiusLg,
      radiusButton: radiusButton,
      solidPanels: solidPanels,
      backdrop: backdrop,
    );
  }

  /// Colours blend; the look, radii and backdrop switch at the midpoint,
  /// so nothing of one look is left on another (the prototype's stale
  /// borders after a switch).
  @override
  NebulaPalette lerp(ThemeExtension<NebulaPalette>? other, double t) {
    if (other is! NebulaPalette) {
      return this;
    }
    final NebulaPalette near = t < 0.5 ? this : other;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return NebulaPalette(
      bg: c(bg, other.bg),
      surface: c(surface, other.surface),
      hairline: c(hairline, other.hairline),
      border: c(border, other.border),
      borderStrong: c(borderStrong, other.borderStrong),
      textPrimary: c(textPrimary, other.textPrimary),
      textMax: c(textMax, other.textMax),
      textMuted: c(textMuted, other.textMuted),
      blue: c(blue, other.blue),
      blueText: c(blueText, other.blueText),
      onAccent: c(onAccent, other.onAccent),
      amber: c(amber, other.amber),
      amberText: c(amberText, other.amberText),
      amberDim: c(amberDim, other.amberDim),
      red: c(red, other.red),
      redText: c(redText, other.redText),
      dotOff: c(dotOff, other.dotOff),
      look: near.look,
      canvas: c(canvas, other.canvas),
      subtle: c(subtle, other.subtle),
      dialog: c(dialog, other.dialog),
      ok: c(ok, other.ok),
      onDanger: c(onDanger, other.onDanger),
      radiusSm: near.radiusSm,
      radiusMd: near.radiusMd,
      radiusLg: near.radiusLg,
      radiusButton: near.radiusButton,
      solidPanels: near.solidPanels,
      backdrop: near.backdrop,
    );
  }
}

class _Surfaces {
  const _Surfaces({
    required this.bg,
    required this.ink,
    required this.muted,
    required this.line,
    required this.s2,
    required this.strong,
    required this.dialog,
    required this.surface,
  });

  final Color bg;
  final Color ink;
  final Color muted;
  final Color line;
  final Color s2;
  final Color strong;
  final Color dialog;
  final Color surface;
}

/// Liquid glass's background: the base colour under two radial glows, at
/// the prototype's positions (10% 0% and 100% 60%).
@immutable
class GlassBackdropColors {
  const GlassBackdropColors({
    required this.base,
    required this.first,
    required this.second,
  });

  final Color base;
  final Color first;
  final Color second;

  List<RadialGradient> get glows => <RadialGradient>[
    RadialGradient(
      center: const Alignment(-0.8, -1),
      radius: 1.2,
      colors: <Color>[first, first.withValues(alpha: 0)],
      stops: const <double>[0, 0.62],
    ),
    RadialGradient(
      center: const Alignment(1, 0.2),
      radius: 0.9,
      colors: <Color>[second, second.withValues(alpha: 0)],
      stops: const <double>[0, 0.62],
    ),
  ];
}

/// Paints Liquid glass's background behind [child]: the base colour and
/// two glows. Nothing on the other looks.
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final GlassBackdropColors? backdrop = context.palette.backdrop;
    if (backdrop == null) {
      return child;
    }
    return DecoratedBox(
      decoration: BoxDecoration(color: backdrop.base),
      child: Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          for (final RadialGradient glow in backdrop.glows)
            Positioned.fill(
              child: DecoratedBox(decoration: BoxDecoration(gradient: glow)),
            ),
          child,
        ],
      ),
    );
  }
}

/// Reads the palette without the `extension<...>()!` ceremony at every call
/// site; under a bare MaterialApp (most widget tests) it falls back to the
/// default palette for the ambient brightness.
extension NebulaPaletteAccess on BuildContext {
  NebulaPalette get palette {
    final ThemeData theme = Theme.of(this);
    return theme.extension<NebulaPalette>() ??
        (theme.brightness == Brightness.dark
            ? NebulaPalette.dark
            : NebulaPalette.light);
  }
}
