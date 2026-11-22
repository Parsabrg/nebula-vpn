import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nebula_mobile/core/theme/color_tokens.dart';
import 'package:nebula_mobile/core/theme/look.dart';

/// WCAG 2.2 AA for every text token on every ground it is drawn on, in
/// every look, mode and accent (and Liquid glass with Reduce transparency):
/// 4.5:1, as all of these are drawn at body sizes.
void main() {
  test('every text and background pair meets WCAG AA', () {
    final List<String> failures = <String>[];
    int pairs = 0;
    for (final NebulaLook look in NebulaLook.values) {
      for (final Brightness brightness in Brightness.values) {
        for (final NebulaAccent accent in NebulaAccent.values) {
          for (final bool solid in <bool>[false, true]) {
            if (solid && look != NebulaLook.glass) {
              continue;
            }
            final NebulaPalette p = NebulaPalette.resolve(
              look: look,
              brightness: brightness,
              accent: accent,
              reduceTransparency: solid,
            );
            final String name =
                '${look.name}${solid ? '/solid' : ''} ${brightness.name} ${accent.name}';
            final Map<String, Color> grounds = <String, Color>{
              'canvas': p.canvas,
              'surface': _over(p.surface, p.canvas),
              'dialog': p.dialog,
            };
            final GlassBackdropColors? glow = p.backdrop;
            if (glow != null) {
              // Where a glow is brightest: the worst case behind text.
              for (final (String label, Color c) in <(String, Color)>[
                ('glow 1', glow.first),
                ('glow 2', glow.second),
              ]) {
                final Color lit = _over(c, p.canvas);
                grounds['canvas+$label'] = lit;
                grounds['surface+$label'] = _over(p.surface, lit);
              }
            }
            final Map<String, Color> texts = <String, Color>{
              'text': p.textPrimary,
              'muted': p.textMuted,
              'accent': p.blueText,
              'ok': p.ok,
              'warning': p.amberText,
              'danger': p.redText,
            };
            for (final MapEntry<String, Color> ground in grounds.entries) {
              for (final MapEntry<String, Color> text in texts.entries) {
                pairs++;
                final double r = _ratio(
                  _over(text.value, ground.value),
                  ground.value,
                );
                if (r < 4.5) {
                  failures.add(
                    '$name: ${text.key} on ${ground.key} '
                    '${r.toStringAsFixed(2)}',
                  );
                }
              }
            }
            pairs += 2;
            if (_ratio(p.onAccent, p.blue) < 4.5) {
              failures.add('$name: on-accent on accent');
            }
            if (_ratio(p.onDanger, p.red) < 4.5) {
              failures.add('$name: on-danger on danger');
            }
          }
        }
      }
    }
    // ignore: avoid_print
    print('contrast: $pairs pairs, ${failures.length} below 4.5:1');
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('the default palettes are Minimal and blue, as resolved', () {
    for (final (NebulaPalette fixed, Brightness b)
        in <(NebulaPalette, Brightness)>[
          (NebulaPalette.dark, Brightness.dark),
          (NebulaPalette.light, Brightness.light),
        ]) {
      final NebulaPalette resolved = NebulaPalette.resolve(
        look: NebulaLook.minimal,
        brightness: b,
      );
      expect(fixed.bg, resolved.bg);
      expect(fixed.textMuted, resolved.textMuted);
      expect(fixed.hairline, resolved.hairline);
      expect(fixed.blue, resolved.blue);
      expect(fixed.ok, resolved.ok);
      expect(fixed.red, resolved.red);
      expect(fixed.radiusMd, resolved.radiusMd);
    }
  });
}

Color _over(Color fg, Color bg) {
  final double a = fg.a;
  return Color.from(
    alpha: 1,
    red: fg.r * a + bg.r * (1 - a),
    green: fg.g * a + bg.g * (1 - a),
    blue: fg.b * a + bg.b * (1 - a),
  );
}

double _luminance(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _ratio(Color a, Color b) {
  final double la = _luminance(a);
  final double lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}
