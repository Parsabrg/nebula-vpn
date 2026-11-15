import 'package:flutter/material.dart';

import '../../format/case.dart';
import '../../theme/color_tokens.dart';
import '../../theme/look.dart';
import 'nebula_surface.dart';

/// What a row's icon and subtitle signal: nothing, a warning, or danger.
enum NebulaTone { normal, warn, danger }

/// A section label: mono capitals on Minimal, a quiet heading elsewhere.
class NebulaSectionLabel extends StatelessWidget {
  const NebulaSectionLabel(this.label, {super.key, this.first = false});

  final String label;

  /// The first on the screen: less space above.
  final bool first;

  @override
  Widget build(BuildContext context) {
    final NebulaPalette p = context.palette;
    final bool minimal = p.look == NebulaLook.minimal;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        minimal ? 0 : (p.look == NebulaLook.expressive ? 12 : 8),
        first ? 8 : (minimal ? 28 : 24),
        minimal ? 0 : 8,
        8,
      ),
      child: Semantics(
        header: true,
        child: Text(
          minimal ? upperCaseFor(context, label) : label,
          style: minimal
              ? TextStyle(
                  fontFamily: 'GeistMono',
                  fontSize: 12,
                  height: 16 / 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.2,
                  color: p.textMuted,
                )
              : TextStyle(
                  fontSize: 13,
                  height: 18 / 13,
                  fontWeight: FontWeight.w500,
                  color: p.textMuted,
                ),
        ),
      ),
    );
  }
}

/// Where a row sits in its group: Expressive rounds only the outer corners
/// of its connected segments, the containers rule off all but the first.
class _RowSlot extends InheritedWidget {
  const _RowSlot({
    required this.index,
    required this.count,
    required super.child,
  });

  final int index;
  final int count;

  static _RowSlot? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_RowSlot>();

  @override
  bool updateShouldNotify(_RowSlot old) =>
      old.index != index || old.count != count;
}

/// Rows drawn as one group: hairlines on Minimal, connected segments on
/// Expressive, one container on Liquid glass and Soft cards.
class NebulaRowGroup extends StatelessWidget {
  const NebulaRowGroup({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final NebulaPalette p = context.palette;
    final int n = children.length;
    final List<Widget> rows = <Widget>[
      for (int i = 0; i < n; i++)
        _RowSlot(index: i, count: n, child: children[i]),
    ];
    switch (p.look) {
      case NebulaLook.minimal:
        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: p.hairline)),
          ),
          child: Column(children: rows),
        );
      case NebulaLook.expressive:
        return Column(
          children: <Widget>[
            for (int i = 0; i < n; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: 2),
              rows[i],
            ],
          ],
        );
      case NebulaLook.glass:
      case NebulaLook.soft:
        return NebulaPanel(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(p.radiusMd),
            child: Column(children: rows),
          ),
        );
    }
  }
}

/// One row: an icon in the look's tile, a title and subtitle, and a trailing
/// part ([NebulaRowTrailing], a [NebulaSwitch], a radio, a checkbox or an
/// inline action).
class NebulaRow extends StatelessWidget {
  const NebulaRow({
    required this.title,
    super.key,
    this.icon,
    this.subtitle,
    this.subtitleColor,
    this.trailing,
    this.onTap,
    this.tone = NebulaTone.normal,
    this.selected,
    this.toggled,
    this.titleColor,
  });

  final String title;
  final IconData? icon;
  final String? subtitle;
  final Color? subtitleColor;
  final Color? titleColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final NebulaTone tone;
  final bool? selected;
  final bool? toggled;

  @override
  Widget build(BuildContext context) {
    final NebulaPalette p = context.palette;
    final _RowSlot? slot = _RowSlot.of(context);
    final int i = slot?.index ?? 0;
    final int n = slot?.count ?? 1;
    final Color toneColor = switch (tone) {
      NebulaTone.warn => p.amberText,
      NebulaTone.danger => p.redText,
      NebulaTone.normal => p.textPrimary,
    };

    final Widget content = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) => Row(
        children: <Widget>[
          if (icon != null) ...<Widget>[
            _Tile(icon: icon!, tone: tone),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    height: 22 / 16,
                    color:
                        titleColor ??
                        (tone == NebulaTone.danger ? p.redText : p.textPrimary),
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 13,
                      height: 18 / 13,
                      color:
                          subtitleColor ??
                          (tone == NebulaTone.warn ? toneColor : p.textMuted),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // At most two fifths of the row, so a long value or button label
          // on a small phone or with large text shortens instead of pushing
          // past the screen edge. A cap rather than a flex share, which kept
          // the trailing part off the row's end.
          if (trailing != null) ...<Widget>[
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: box.hasBoundedWidth
                    ? box.maxWidth * 0.4
                    : double.infinity,
              ),
              child: trailing,
            ),
          ],
        ],
      ),
    );

    late final EdgeInsets padding;
    late final BoxDecoration decoration;
    late final BorderRadius pressRadius;
    double minHeight = 56;
    switch (p.look) {
      case NebulaLook.minimal:
        padding = const EdgeInsets.symmetric(vertical: 12);
        decoration = BoxDecoration(
          border: Border(bottom: BorderSide(color: p.hairline)),
        );
        pressRadius = BorderRadius.zero;
      case NebulaLook.expressive:
        padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12);
        minHeight = 64;
        final Radius outer = Radius.circular(p.radiusMd);
        const Radius inner = Radius.circular(6);
        pressRadius = n == 1
            ? BorderRadius.all(outer)
            : BorderRadius.vertical(
                top: i == 0 ? outer : inner,
                bottom: i == n - 1 ? outer : inner,
              );
        decoration = BoxDecoration(color: p.surface, borderRadius: pressRadius);
      case NebulaLook.glass:
      case NebulaLook.soft:
        padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10);
        decoration = BoxDecoration(
          border: i > 0
              ? Border(top: BorderSide(color: p.hairline))
              : const Border(),
        );
        pressRadius = BorderRadius.zero;
    }

    final Widget body = DecoratedBox(
      decoration: decoration,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: Padding(padding: padding, child: content),
      ),
    );
    if (onTap == null) {
      return Semantics(container: true, child: body);
    }
    return NebulaPressable(
      onTap: onTap,
      borderRadius: pressRadius,
      selected: selected,
      toggled: toggled,
      child: body,
    );
  }
}

/// The icon in the look's tile: bare on Minimal, a rounded square on Liquid
/// glass and Soft cards (accent-tinted there), a circle on Expressive.
class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.tone});

  final IconData icon;
  final NebulaTone tone;

  @override
  Widget build(BuildContext context) {
    final NebulaPalette p = context.palette;
    final bool dark = p.isDark;
    final Color? toneColor = switch (tone) {
      NebulaTone.warn => p.amberText,
      NebulaTone.danger => p.redText,
      NebulaTone.normal => null,
    };
    late final double size;
    late final BoxDecoration? decoration;
    late final Color color;
    switch (p.look) {
      case NebulaLook.minimal:
        return SizedBox(
          width: 24,
          height: 36,
          child: Icon(icon, size: 20, color: toneColor ?? p.textMuted),
        );
      case NebulaLook.glass:
        size = 32;
        color = toneColor ?? p.textPrimary;
        decoration = BoxDecoration(
          borderRadius: BorderRadius.circular(p.radiusSm),
          color: toneColor == null
              ? p.subtle
              : toneColor.withValues(
                  alpha: tone == NebulaTone.warn ? 0.22 : 0.20,
                ),
        );
      case NebulaLook.soft:
        size = 36;
        final Color c = toneColor ?? p.blueText;
        color = c;
        decoration = BoxDecoration(
          borderRadius: BorderRadius.circular(p.radiusSm + 2),
          color: nebulaMix(c, dark ? 20 : 12, p.surface),
        );
      case NebulaLook.expressive:
        size = 40;
        color = toneColor ?? p.textPrimary;
        decoration = BoxDecoration(
          shape: BoxShape.circle,
          color: toneColor == null
              ? p.subtle
              : nebulaMix(
                  toneColor,
                  dark ? 24 : (tone == NebulaTone.warn ? 18 : 14),
                  p.surface,
                ),
        );
    }
    return Container(
      width: size,
      height: size,
      decoration: decoration,
      alignment: Alignment.center,
      child: Icon(icon, size: 20, color: color),
    );
  }
}

/// The ready-made trailing parts of a [NebulaRow].
abstract final class NebulaRowTrailing {
  static Widget chevron(BuildContext context) => ExcludeSemantics(
    child: Icon(
      Icons.chevron_right,
      size: 22,
      color: context.palette.textMuted,
    ),
  );

  static Widget external(BuildContext context) => ExcludeSemantics(
    child: Icon(Icons.open_in_new, size: 20, color: context.palette.textMuted),
  );

  /// A value: mono, muted, cut short with an ellipsis.
  static Widget value(BuildContext context, String text, {bool mono = true}) =>
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 180),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: mono ? 'GeistMono' : null,
            fontSize: 14,
            height: 20 / 14,
            color: context.palette.textMuted,
          ),
        ),
      );

  /// A value and a chevron: "Change >".
  static Widget valueChevron(BuildContext context, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      value(context, text, mono: false),
      const SizedBox(width: 6),
      chevron(context),
    ],
  );

  static Widget badge(BuildContext context, String text) {
    final NebulaPalette p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: nebulaTint(p, p.blue, p.isDark ? 22 : 14),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          height: 16 / 12,
          fontWeight: FontWeight.w500,
          color: p.textPrimary,
        ),
      ),
    );
  }
}

/// The redesign's switch: 52 x 32; on, an accent track with a 24 px knob in
/// the accent's text colour; off, a 2 px outline with a 16 px grey knob.
class NebulaSwitch extends StatelessWidget {
  const NebulaSwitch({
    required this.value,
    super.key,
    this.onChanged,
    this.semanticLabel,
  });

  final bool value;

  /// Null when the row around it takes the tap (the switch is then only a
  /// picture of the state, and is not focusable on its own).
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final NebulaPalette p = context.palette;
    final Duration duration = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 160);
    final Widget track = AnimatedContainer(
      duration: duration,
      curve: Curves.easeOut,
      width: 52,
      height: 32,
      padding: EdgeInsets.only(left: value ? 0 : 6, right: value ? 4 : 0),
      alignment: value ? Alignment.centerRight : Alignment.centerLeft,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: value ? p.blue : Colors.transparent,
        border: value ? null : Border.all(color: p.borderStrong, width: 2),
      ),
      child: AnimatedContainer(
        duration: duration,
        width: value ? 24 : 16,
        height: value ? 24 : 16,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: value ? p.onAccent : p.borderStrong,
        ),
      ),
    );
    if (onChanged == null) {
      return ExcludeSemantics(child: track);
    }
    return NebulaPressable(
      onTap: () => onChanged!(!value),
      toggled: value,
      semanticLabel: semanticLabel,
      borderRadius: BorderRadius.circular(16),
      child: Padding(padding: const EdgeInsets.all(6), child: track),
    );
  }
}

/// A row whose whole width toggles a [NebulaSwitch].
class NebulaSwitchRow extends StatelessWidget {
  const NebulaSwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
    super.key,
    this.icon,
    this.subtitle,
    this.subtitleColor,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;
  final String? subtitle;
  final Color? subtitleColor;

  @override
  Widget build(BuildContext context) => NebulaRow(
    title: title,
    icon: icon,
    subtitle: subtitle,
    subtitleColor: subtitleColor,
    toggled: value,
    onTap: () => onChanged(!value),
    trailing: NebulaSwitch(value: value),
  );
}
