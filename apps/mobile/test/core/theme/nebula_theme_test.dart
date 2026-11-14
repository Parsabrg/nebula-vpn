import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_mobile/core/theme/color_tokens.dart';
import 'package:nebula_mobile/core/theme/nebula_theme.dart';
import 'package:nebula_mobile/core/theme/type_scale.dart';

void main() {
  group('palette', () {
    test('dark carries the redesign values exactly', () {
      // Minimal, dark, blue: nebula-redesign/reference/source/app_tokens.js.
      const NebulaPalette dark = NebulaPalette.dark;
      expect(dark.bg, const Color(0xFF0B0B0F));
      expect(dark.surface, const Color(0xFF14141A));
      expect(dark.hairline, const Color(0xFF22222B));
      expect(dark.borderStrong, const Color(0xFF6A6A78));
      expect(dark.textMuted, const Color(0xFF9A9AA6));
      expect(dark.blue, const Color(0xFF8CA4FF));
      expect(dark.amberText, const Color(0xFFE8B24A));
      expect(dark.ok, const Color(0xFF6FD3A0));
      expect(dark.red, const Color(0xFFFF8A80));
    });

    test('text on an accent fill is the background colour, never white', () {
      // Called out explicitly in the handoff, and the easy thing to get wrong
      // because every other design puts white on a blue button.
      expect(NebulaPalette.dark.onAccent, NebulaPalette.dark.bg);
    });

    test('the line sits closer to the background than the outline', () {
      for (final NebulaPalette palette in <NebulaPalette>[
        NebulaPalette.dark,
        NebulaPalette.light,
      ]) {
        expect(
          _luminanceDistanceFromBg(palette, palette.hairline) <
              _luminanceDistanceFromBg(palette, palette.borderStrong),
          isTrue,
          reason: 'a row rule must be quieter than a control outline',
        );
      }
    });

    test('lerp between the themes stays a valid palette', () {
      final NebulaPalette mid = NebulaPalette.dark.lerp(
        NebulaPalette.light,
        0.5,
      );
      expect(mid.bg, isNot(NebulaPalette.dark.bg));
      expect(mid.bg, isNot(NebulaPalette.light.bg));
    });
  });

  group('theme', () {
    test('both themes expose the palette and the type scale', () {
      for (final ThemeData theme in <ThemeData>[
        NebulaTheme.dark(),
        NebulaTheme.light(),
      ]) {
        expect(theme.extension<NebulaPalette>(), isNotNull);
        expect(theme.extension<NebulaTypography>(), isNotNull);
      }
    });

    test('the screen background is exactly bg, with no elevation tint', () {
      final ThemeData dark = NebulaTheme.dark();
      expect(dark.scaffoldBackgroundColor, NebulaPalette.dark.bg);
      expect(dark.appBarTheme.surfaceTintColor, Colors.transparent);
      expect(dark.appBarTheme.elevation, 0);
    });

    test('the CTA is 60 tall with a 14 radius', () {
      final ThemeData theme = NebulaTheme.dark();
      final ButtonStyle? style = theme.filledButtonTheme.style;
      expect(
        style?.minimumSize?.resolve(<WidgetState>{}),
        const Size.fromHeight(60),
      );
      final RoundedRectangleBorder shape =
          style!.shape!.resolve(<WidgetState>{})! as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(14));
    });

    test('nothing falls back to Roboto', () {
      // The whole point of bundling the faces. A missing fontFamily here is
      // invisible in review and obvious on a device.
      final ThemeData theme = NebulaTheme.dark();
      expect(theme.textTheme.displayLarge?.fontFamily, 'Geist');
      expect(theme.textTheme.bodySmall?.fontFamily, 'GeistMono');
      expect(theme.textTheme.labelSmall?.fontFamily, 'GeistMono');
    });
  });

  group('type scale', () {
    test('line heights are the handoff pixel values, as multiples', () {
      const NebulaTypography type = NebulaTypography.standard;
      expect(type.stateWord.fontSize, 44);
      expect(type.stateWord.height, closeTo(50 / 44, 1e-9));
      expect(type.stateWord.letterSpacing, -1.6);
      expect(type.quotaFigure.height, closeTo(48 / 44, 1e-9));
      expect(type.statusLine.letterSpacing, 1.2);
    });

    test('every number and identifier role is mono', () {
      const NebulaTypography type = NebulaTypography.standard;
      for (final TextStyle style in <TextStyle>[
        type.quotaFigure,
        type.rowValue,
        type.statusLine,
        type.topBarMeta,
        type.wordmark,
        type.sectionHeader,
        type.listMeta,
        type.chipLabel,
      ]) {
        expect(style.fontFamily, 'GeistMono');
      }
    });

    test('prose roles are the sans face', () {
      const NebulaTypography type = NebulaTypography.standard;
      for (final TextStyle style in <TextStyle>[
        type.stateWord,
        type.authTitle,
        type.navTitle,
        type.ctaLabel,
        type.listTitleActive,
        type.inputText,
        type.rowLabel,
        type.tabLabel,
      ]) {
        expect(style.fontFamily, 'Geist');
      }
    });
  });

  test('every font pubspec declares is actually on disk', () {
    // A mistyped asset path is not an error at build time; Flutter falls back
    // to Roboto and the design quietly stops being the design. Parsed rather
    // than hardcoded so adding a weight to pubspec extends this check for free.
    final File pubspec = File('pubspec.yaml');
    expect(pubspec.existsSync(), isTrue, reason: 'run from apps/mobile');

    final List<String> assets = pubspec
        .readAsLinesSync()
        .map((String line) => line.trim())
        .where((String line) => line.startsWith('- asset:'))
        .map((String line) => line.substring('- asset:'.length).trim())
        .toList();

    expect(assets, hasLength(5), reason: 'three Geist weights and two mono');
    for (final String asset in assets) {
      expect(
        File(asset).existsSync(),
        isTrue,
        reason: '$asset is declared in pubspec.yaml but missing from disk',
      );
    }
  });
}

/// How far a colour sits from the palette's own background, so the assertion
/// reads the same way in a light theme as in a dark one.
double _luminanceDistanceFromBg(NebulaPalette palette, Color color) {
  return (color.computeLuminance() - palette.bg.computeLuminance()).abs();
}
