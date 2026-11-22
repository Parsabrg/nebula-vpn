import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/appearance_controller.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/look.dart';
import '../../core/theme/theme_mode_controller.dart';
import '../../core/widgets/nebula/nebula_controls.dart';
import '../../core/widgets/nebula/nebula_page.dart';
import '../../core/widgets/nebula/nebula_rows.dart';
import '../../core/widgets/nebula/nebula_surface.dart';
import '../../l10n/app_localizations.dart';

/// Settings, Appearance (DESIGN_SPEC §4): look, theme mode, accent, and
/// Reduce transparency on Liquid glass. Every change applies app-wide at
/// once and persists.
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppText text = AppText.of(context);
    final AppearanceChoice choice = ref.watch(appearanceProvider);
    final AppearanceController appearance = ref.read(
      appearanceProvider.notifier,
    );
    final ThemeMode mode = ref.watch(themeModeProvider);

    return NebulaPage(
      title: text.sectionAppearance,
      children: <Widget>[
        NebulaSectionLabel(text.lookLabel),
        _LookGrid(
          selected: choice.look,
          onSelected: appearance.setLook,
          names: <NebulaLook, String>{
            NebulaLook.minimal: text.lookMinimal,
            NebulaLook.glass: text.lookGlass,
            NebulaLook.soft: text.lookSoft,
            NebulaLook.expressive: text.lookExpressive,
          },
        ),
        NebulaSectionLabel(text.themeModeLabel),
        NebulaSegmented<ThemeMode>(
          semanticsLabel: text.themeModeLabel,
          segments: <(ThemeMode, String, IconData?)>[
            (ThemeMode.light, text.themeLight, Icons.light_mode_outlined),
            (ThemeMode.dark, text.themeDark, Icons.dark_mode_outlined),
            (ThemeMode.system, text.themeSystem, Icons.contrast),
          ],
          selected: mode,
          onChanged: (ThemeMode next) =>
              ref.read(themeModeProvider.notifier).setMode(next),
        ),
        NebulaSectionLabel(
          '${text.accentLabel} · ${accentName(text, choice.accent)}',
        ),
        _AccentSwatches(
          selected: choice.accent,
          onSelected: appearance.setAccent,
          name: (NebulaAccent a) => accentName(text, a),
        ),
        if (choice.look == NebulaLook.glass) ...<Widget>[
          NebulaSectionLabel(text.lookGlass),
          NebulaRowGroup(
            children: <Widget>[
              NebulaSwitchRow(
                title: text.reduceTransparency,
                subtitle: text.reduceTransparencyMeta,
                value: choice.reduceTransparency,
                onChanged: (bool on) =>
                    appearance.setReduceTransparency(enabled: on),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

String accentName(AppText text, NebulaAccent accent) => switch (accent) {
  NebulaAccent.blue => text.accentBlue,
  NebulaAccent.violet => text.accentViolet,
  NebulaAccent.teal => text.accentTeal,
  NebulaAccent.amber => text.accentAmber,
  NebulaAccent.mono => text.accentMono,
};

String lookName(AppText text, NebulaLook look) => switch (look) {
  NebulaLook.minimal => text.lookMinimal,
  NebulaLook.glass => text.lookGlass,
  NebulaLook.soft => text.lookSoft,
  NebulaLook.expressive => text.lookExpressive,
};

class _LookGrid extends StatelessWidget {
  const _LookGrid({
    required this.selected,
    required this.onSelected,
    required this.names,
  });

  final NebulaLook selected;
  final ValueChanged<NebulaLook> onSelected;
  final Map<NebulaLook, String> names;

  @override
  Widget build(BuildContext context) {
    final List<NebulaLook> looks = NebulaLook.values;
    return Column(
      children: <Widget>[
        for (int row = 0; row < 2; row++) ...<Widget>[
          if (row > 0) const SizedBox(height: 16),
          Row(
            children: <Widget>[
              for (int col = 0; col < 2; col++) ...<Widget>[
                if (col > 0) const SizedBox(width: 12),
                Expanded(
                  child: _LookTile(
                    look: looks[row * 2 + col],
                    name: names[looks[row * 2 + col]]!,
                    selected: looks[row * 2 + col] == selected,
                    onTap: () => onSelected(looks[row * 2 + col]),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _LookTile extends StatelessWidget {
  const _LookTile({
    required this.look,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final NebulaLook look;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final NebulaPalette here = context.palette;
    // The preview is drawn in its own look, in the current mode and accent.
    final NebulaPalette p = NebulaPalette.resolve(
      look: look,
      brightness: here.isDark ? Brightness.dark : Brightness.light,
      accent: _accentOf(here),
    );
    return NebulaPressable(
      onTap: onTap,
      selected: selected,
      semanticLabel: name,
      excludeChildSemantics: true,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // The design's tile: 116 high whatever the width, so it keeps
          // its proportions from a phone to a desktop window.
          Container(
            height: 116,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: p.canvas,
              gradient: p.backdrop == null
                  ? null
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        nebulaMix(p.backdrop!.first, 60, p.canvas),
                        p.canvas,
                        nebulaMix(p.backdrop!.second, 60, p.canvas),
                      ],
                    ),
              borderRadius: BorderRadius.circular(here.radiusMd),
              border: Border.all(
                color: selected
                    ? here.blue
                    : (here.isDark
                          ? const Color(0x2EFFFFFF)
                          : const Color(0x29101014)),
                width: selected ? 2 : 1,
              ),
            ),
            padding: const EdgeInsets.all(12),
            child: _Preview(p: p),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: here.textPrimary,
                  ),
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, size: 20, color: here.blueText),
            ],
          ),
        ],
      ),
    );
  }

  static NebulaAccent _accentOf(NebulaPalette p) =>
      NebulaAccent.values.firstWhere(
        (NebulaAccent a) => a.dark == p.blue || a.light == p.blue,
        orElse: () => NebulaAccent.blue,
      );
}

/// A miniature of a screen in [p]'s look: a title bar, the status hero with
/// an accent mark, and two rows.
class _Preview extends StatelessWidget {
  const _Preview({required this.p});

  final NebulaPalette p;

  @override
  Widget build(BuildContext context) {
    final bool minimal = p.look == NebulaLook.minimal;
    final bool expressive = p.look == NebulaLook.expressive;
    BoxDecoration block({required bool hero}) => minimal
        ? BoxDecoration(
            border: Border(bottom: BorderSide(color: p.hairline)),
          )
        : BoxDecoration(
            color: hero && expressive
                ? nebulaMix(p.blue, p.isDark ? 22 : 16, p.canvas)
                : (p.look == NebulaLook.glass
                      ? p.surface.withValues(
                          alpha: (p.surface.a + 0.08).clamp(0, 1),
                        )
                      : p.surface),
            borderRadius: expressive
                ? (hero
                      ? BorderRadius.circular(12)
                      : const BorderRadius.vertical(
                          top: Radius.circular(8),
                          bottom: Radius.circular(3),
                        ))
                : BorderRadius.circular(hero ? 10 : 7),
            border: p.look == NebulaLook.glass
                ? Border.all(color: p.hairline)
                : null,
          );
    // Fixed heights as designed (a 6 bar, a 40 hero, two 18 rows, 7
    // apart); the box clips the last row.
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.topCenter,
        maxHeight: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: 0.42,
              child: Opacity(
                opacity: 0.75,
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: minimal ? p.textMuted : p.textPrimary,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 7),
            Container(
              height: 40,
              decoration: block(hero: true),
              alignment: AlignmentDirectional.bottomStart,
              padding: const EdgeInsets.all(7),
              child: Container(
                width: 22,
                height: 5,
                decoration: BoxDecoration(
                  color: p.blue,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 7),
            Container(height: 18, decoration: block(hero: false)),
            const SizedBox(height: 7),
            Container(height: 18, decoration: block(hero: false)),
          ],
        ),
      ),
    );
  }
}

class _AccentSwatches extends StatelessWidget {
  const _AccentSwatches({
    required this.selected,
    required this.onSelected,
    required this.name,
  });

  final NebulaAccent selected;
  final ValueChanged<NebulaAccent> onSelected;
  final String Function(NebulaAccent) name;

  @override
  Widget build(BuildContext context) {
    final NebulaPalette p = context.palette;
    final Brightness b = p.isDark ? Brightness.dark : Brightness.light;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final NebulaAccent accent in NebulaAccent.values)
          NebulaPressable(
            onTap: () => onSelected(accent),
            selected: accent == selected,
            semanticLabel: name(accent),
            excludeChildSemantics: true,
            borderRadius: BorderRadius.circular(26),
            // A 52 px target around a 40 px swatch.
            child: SizedBox.square(
              dimension: 52,
              child: Center(
                child: Container(
                  width: 44,
                  height: 44,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: accent == selected
                        ? Border.all(color: accent.on(b), width: 2)
                        : null,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.on(b),
                      border: Border.all(color: p.hairline),
                    ),
                    child: accent == selected
                        ? Icon(
                            Icons.check,
                            size: 20,
                            color: b == Brightness.dark
                                ? const Color(0xFF0B0B0F)
                                : Colors.white,
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
