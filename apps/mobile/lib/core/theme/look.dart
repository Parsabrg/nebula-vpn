import 'package:flutter/material.dart';

/// The four looks of the redesign (nebula-redesign/DESIGN_SPEC.md §1): one
/// app, one set of widgets, four sets of token values. A look changes
/// surfaces, corner radii and the voice of headings, never layout or copy.
enum NebulaLook {
  minimal,
  glass,
  soft,
  expressive;

  static NebulaLook parse(String? name) => NebulaLook.values.firstWhere(
    (NebulaLook look) => look.name == name,
    orElse: () => NebulaLook.minimal,
  );
}

/// The accent marks the primary action, the current selection, focus rings
/// and switches that are on -- nothing else (§1.2). [dark] is the value on a
/// dark background, [light] on a light one (§2).
enum NebulaAccent {
  blue(Color(0xFF8CA4FF), Color(0xFF2A46BE)),
  violet(Color(0xFFB79CFF), Color(0xFF6D3FD1)),
  teal(Color(0xFF4FD1C5), Color(0xFF0F6E66)),
  amber(Color(0xFFE8B24A), Color(0xFF8A5A00)),
  mono(Color(0xFFEDEDF2), Color(0xFF101014));

  const NebulaAccent(this.dark, this.light);

  final Color dark;
  final Color light;

  Color on(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  static NebulaAccent parse(String? name) => NebulaAccent.values.firstWhere(
    (NebulaAccent accent) => accent.name == name,
    orElse: () => NebulaAccent.blue,
  );
}

/// What the person chose in Settings, Appearance: look, accent, and whether
/// Liquid glass draws its panels solid ("Reduce transparency").
@immutable
class AppearanceChoice {
  const AppearanceChoice({
    this.look = NebulaLook.minimal,
    this.accent = NebulaAccent.blue,
    this.reduceTransparency = false,
  });

  final NebulaLook look;
  final NebulaAccent accent;
  final bool reduceTransparency;

  static const AppearanceChoice defaults = AppearanceChoice();

  AppearanceChoice copyWith({
    NebulaLook? look,
    NebulaAccent? accent,
    bool? reduceTransparency,
  }) => AppearanceChoice(
    look: look ?? this.look,
    accent: accent ?? this.accent,
    reduceTransparency: reduceTransparency ?? this.reduceTransparency,
  );

  @override
  bool operator ==(Object other) =>
      other is AppearanceChoice &&
      other.look == look &&
      other.accent == accent &&
      other.reduceTransparency == reduceTransparency;

  @override
  int get hashCode => Object.hash(look, accent, reduceTransparency);
}
