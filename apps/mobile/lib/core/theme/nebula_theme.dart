import 'package:material_ui/material_ui.dart';

import 'color_tokens.dart';
import 'look.dart';
import 'type_scale.dart';

/// Theme builders for the Panel design language.
///
/// The palette is applied literally rather than seeded. `ColorScheme.fromSeed`
/// built the placeholder shell this replaces, and it cannot express this
/// design: `hairline`, `border` and `borderStrong` are three deliberate greys
/// within 0x20 of one another, and a tonal palette derives its own values
/// instead. Screens read [NebulaPalette] and [NebulaTypography] from the theme
/// extensions; the `ColorScheme` below exists so Material's own widgets --
/// dialogs, text selection, the ripple -- land somewhere sensible rather than
/// on purple defaults.
abstract final class NebulaTheme {
  static ThemeData light() => _themeFrom(NebulaPalette.light, Brightness.light);

  /// The theme for a look, mode and accent chosen in Settings, Appearance.
  static ThemeData resolve(Brightness brightness, AppearanceChoice choice) =>
      _themeFrom(
        NebulaPalette.resolve(
          look: choice.look,
          brightness: brightness,
          accent: choice.accent,
          reduceTransparency: choice.reduceTransparency,
        ),
        brightness,
      );

  /// Dark is the primary theme.
  static ThemeData dark() => _themeFrom(NebulaPalette.dark, Brightness.dark);

  static ThemeData _themeFrom(NebulaPalette palette, Brightness brightness) {
    final ColorScheme scheme = ColorScheme(
      brightness: brightness,
      primary: palette.blue,
      onPrimary: palette.onAccent,
      secondary: palette.amber,
      onSecondary: palette.onAccent,
      error: palette.red,
      onError: palette.onAccent,
      surface: palette.bg,
      onSurface: palette.textPrimary,
      // Material reaches for these for cards, sheets and disabled fills.
      surfaceContainerHighest: palette.surface,
      onSurfaceVariant: palette.textMuted,
      outline: palette.border,
      outlineVariant: palette.hairline,
    );

    final NebulaTypography type = NebulaTypography.standard;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // Not scheme.surface via Material's own derivation: the design wants the
      // screen to be exactly `bg`, with no elevation tint anywhere.
      scaffoldBackgroundColor: palette.bg,
      canvasColor: palette.canvas,
      fontFamily: 'Geist',
      extensions: <ThemeExtension<dynamic>>[palette, type],
      textTheme: _textTheme(palette, type),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.bg,
        foregroundColor: palette.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: type.navTitle.copyWith(color: palette.textPrimary),
      ),
      // NebulaButton's geometry -- 52 px and the look's button radius -- so
      // a Material button left on a screen matches the redesigned ones.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: palette.blue,
          foregroundColor: palette.onAccent,
          disabledBackgroundColor: palette.surface,
          disabledForegroundColor: palette.textMuted,
          textStyle: type.ctaLabel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(palette.radiusButton),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: palette.textPrimary,
          textStyle: type.ctaLabel,
          side: BorderSide(color: palette.borderStrong),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(palette.radiusButton),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.blueText,
          textStyle: type.ctaLabel,
        ),
      ),
      // 56px tall, 14px radius, `surface` fill, 1px `border`, 16px left pad.
      // NebulaField's box per look, so a Material field matches it.
      inputDecorationTheme: InputDecorationTheme(
        filled: palette.look != NebulaLook.minimal,
        fillColor: palette.look == NebulaLook.expressive
            ? palette.subtle
            : palette.surface,
        constraints: const BoxConstraints(minHeight: 52),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 16,
        ),
        hintStyle: type.inputText.copyWith(color: palette.textMuted),
        border: _inputBorder(palette, palette.borderStrong),
        enabledBorder: _inputBorder(
          palette,
          palette.look == NebulaLook.expressive
              ? Colors.transparent
              : (palette.look == NebulaLook.minimal
                    ? palette.borderStrong
                    : palette.hairline),
        ),
        focusedBorder: _inputBorder(palette, palette.blue, width: 2),
        errorBorder: _inputBorder(palette, palette.redText, width: 2),
        focusedErrorBorder: _inputBorder(palette, palette.redText, width: 2),
        errorStyle: TextStyle(fontSize: 13, color: palette.redText),
      ),
      dividerTheme: DividerThemeData(
        color: palette.hairline,
        thickness: 1,
        space: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.dialog,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(palette.radiusLg),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.blue,
        linearTrackColor: palette.hairline,
      ),
      splashFactory: InkSparkle.splashFactory,
    );
  }

  static OutlineInputBorder _inputBorder(
    NebulaPalette palette,
    Color color, {
    double width = 1,
  }) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(
        palette.look == NebulaLook.glass ||
                palette.look == NebulaLook.expressive
            ? 16
            : palette.radiusMd,
      ),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  /// Material's slots, filled from the Panel scale.
  ///
  /// Screens should reach for [NebulaTypography] by role. This exists so a
  /// widget that was not written for this design -- a dialog's body, a
  /// `SnackBar` -- inherits Geist and a sane colour instead of Roboto.
  static TextTheme _textTheme(NebulaPalette palette, NebulaTypography type) {
    return TextTheme(
      displayLarge: type.stateWord.copyWith(color: palette.textPrimary),
      displayMedium: type.authTitle.copyWith(color: palette.textPrimary),
      headlineSmall: type.navTitle.copyWith(color: palette.textPrimary),
      titleMedium: type.listTitleActive.copyWith(color: palette.textPrimary),
      bodyLarge: type.inputText.copyWith(color: palette.textPrimary),
      bodyMedium: type.rowLabel.copyWith(color: palette.textPrimary),
      bodySmall: type.listMeta.copyWith(color: palette.textMuted),
      labelLarge: type.ctaLabel,
      labelMedium: type.tabLabel.copyWith(color: palette.textMuted),
      labelSmall: type.sectionHeader.copyWith(color: palette.textMuted),
    );
  }
}
