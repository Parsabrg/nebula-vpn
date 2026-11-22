import 'package:material_ui/material_ui.dart';

import '../../theme/color_tokens.dart';
import '../../theme/look.dart';
import 'nebula_surface.dart';

enum NebulaButtonKind { primary, secondary, danger, text, dangerText }

/// The redesign's buttons: 52 tall (text buttons 48), the look's button
/// radius, 600 weight at 16 px, an optional 20 px leading icon.
class NebulaButton extends StatelessWidget {
  const NebulaButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.kind = NebulaButtonKind.primary,
    this.icon,
    this.busy = false,
  }) : row = false;

  const NebulaButton.secondary({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.busy = false,
  }) : kind = NebulaButtonKind.secondary,
       row = false;

  const NebulaButton.danger({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.busy = false,
  }) : kind = NebulaButtonKind.danger,
       row = false;

  const NebulaButton.text({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.busy = false,
    bool danger = false,
  }) : kind = danger ? NebulaButtonKind.dangerText : NebulaButtonKind.text,
       row = false;

  /// The action at a row's end (Revoke, Change server, Remove): 44 tall,
  /// 14 px medium, sitting 8 into the row's edge, as the design draws it.
  const NebulaButton.rowAction({
    required this.label,
    required this.onPressed,
    super.key,
    this.busy = false,
    bool danger = false,
  }) : kind = danger ? NebulaButtonKind.dangerText : NebulaButtonKind.text,
       icon = null,
       row = true;

  final String label;
  final VoidCallback? onPressed;
  final NebulaButtonKind kind;

  /// A row's end action (see [NebulaButton.rowAction]).
  final bool row;
  final IconData? icon;

  /// Shows a spinner in place of the icon; the label says what is happening.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final NebulaPalette p = context.palette;
    final bool text =
        kind == NebulaButtonKind.text || kind == NebulaButtonKind.dangerText;
    final double height = row ? 44 : (text ? 48 : 52);
    final BorderRadius radius = BorderRadius.circular(p.radiusButton);
    final Color foreground = switch (kind) {
      NebulaButtonKind.primary => p.onAccent,
      NebulaButtonKind.danger => p.onDanger,
      NebulaButtonKind.dangerText => p.redText,
      NebulaButtonKind.secondary || NebulaButtonKind.text => p.textPrimary,
    };
    final Widget caption = Text(
      this.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: row ? 14 : (text ? 15 : 16),
        fontWeight: row ? FontWeight.w500 : FontWeight.w600,
        color: foreground,
      ),
    );
    // A text button in a row is given a width limit; elsewhere it may not
    // be, and a Flexible caption needs one.
    final Widget label = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) => Row(
        mainAxisSize: text ? MainAxisSize.min : MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (busy)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 10),
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foreground,
                ),
              ),
            )
          else if (icon != null) ...<Widget>[
            Icon(icon, size: 20, color: foreground),
            const SizedBox(width: 10),
          ],
          // A text button sizes to its label (it sits in rows); the others
          // fill the width and shorten a long label instead.
          if (text && !constraints.hasBoundedWidth)
            caption
          else
            Flexible(child: caption),
        ],
      ),
    );
    Widget box = SizedBox(
      height: height,
      width: text ? null : double.infinity,
      child: Center(
        widthFactor: text ? 1 : null,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: row ? 12 : 16),
          child: label,
        ),
      ),
    );
    switch (kind) {
      case NebulaButtonKind.primary:
        box = DecoratedBox(
          decoration: BoxDecoration(color: p.blue, borderRadius: radius),
          child: box,
        );
      case NebulaButtonKind.danger:
        box = DecoratedBox(
          decoration: BoxDecoration(color: p.red, borderRadius: radius),
          child: box,
        );
      case NebulaButtonKind.secondary:
        box = switch (p.look) {
          NebulaLook.minimal || NebulaLook.expressive => DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: p.borderStrong),
            ),
            child: box,
          ),
          NebulaLook.glass ||
          NebulaLook.soft => NebulaPanel(radius: p.radiusButton, child: box),
        };
      case NebulaButtonKind.text:
      case NebulaButtonKind.dangerText:
        break;
    }
    final Widget button = NebulaPressable(
      onTap: busy ? null : onPressed,
      borderRadius: row ? BorderRadius.circular(p.radiusSm) : radius,
      semanticLabel: this.label,
      excludeChildSemantics: true,
      child: box,
    );
    // A row's action sits 8 into the row's end, so its label lines up
    // closer to the edge, as designed.
    return row
        ? Transform.translate(
            offset: Offset(
              Directionality.of(context) == TextDirection.rtl ? -8 : 8,
              0,
            ),
            child: button,
          )
        : button;
  }
}

/// The accent-coloured link used for "Connection details", "Forgot
/// password" and the like: at least 44 tall.
class NebulaLinkButton extends StatelessWidget {
  const NebulaLinkButton({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final NebulaPalette p = context.palette;
    return NebulaPressable(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(p.radiusSm),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: p.blueText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The segmented control: an outlined bar with the selected segment
/// inverted on Minimal, connected pills on Expressive, a raised segment in a
/// pill track on Liquid glass and Soft cards.
class NebulaSegmented<T> extends StatelessWidget {
  const NebulaSegmented({
    required this.segments,
    required this.selected,
    required this.onChanged,
    super.key,
    this.semanticsLabel,
  });

  /// Value, label and an optional icon.
  final List<(T, String, IconData?)> segments;
  final T selected;
  final ValueChanged<T> onChanged;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final NebulaPalette p = context.palette;
    final int n = segments.length;
    final List<Widget> items = <Widget>[];
    for (int i = 0; i < n; i++) {
      final (T value, String label, IconData? icon) = segments[i];
      final bool on = value == selected;
      late final Color fg;
      late final BoxDecoration decoration;
      late final BorderRadius radius;
      switch (p.look) {
        case NebulaLook.minimal:
          fg = on ? p.canvas : p.textPrimary;
          radius = BorderRadius.zero;
          decoration = BoxDecoration(
            color: on ? p.textPrimary : Colors.transparent,
            border: i > 0
                ? Border(left: BorderSide(color: p.borderStrong))
                : const Border(),
          );
        case NebulaLook.expressive:
          fg = on ? p.onAccent : p.textPrimary;
          radius = on
              ? BorderRadius.circular(24)
              : BorderRadius.horizontal(
                  left: Radius.circular(i == 0 ? 24 : 6),
                  right: Radius.circular(i == n - 1 ? 24 : 6),
                );
          decoration = BoxDecoration(
            color: on ? p.blue : p.surface,
            borderRadius: radius,
          );
        case NebulaLook.glass:
        case NebulaLook.soft:
          fg = p.textPrimary;
          radius = BorderRadius.circular(p.radiusMd - 4);
          final bool glass = p.look == NebulaLook.glass;
          decoration = BoxDecoration(
            borderRadius: radius,
            color: on
                ? (glass
                      ? (p.isDark ? const Color(0x33FFFFFF) : Colors.white)
                      : p.surface)
                : Colors.transparent,
            boxShadow: on && !glass
                ? const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x1F000000),
                      blurRadius: 3,
                      offset: Offset(0, 1),
                    ),
                  ]
                : null,
          );
      }
      items.add(
        Expanded(
          child: NebulaPressable(
            onTap: () => onChanged(value),
            borderRadius: radius,
            selected: on,
            semanticLabel: label,
            excludeChildSemantics: true,
            child: DecoratedBox(
              decoration: decoration,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (icon != null) ...<Widget>[
                      Icon(icon, size: 18, color: fg),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: fg,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      if (p.look == NebulaLook.expressive && i < n - 1) {
        items.add(const SizedBox(width: 2));
      } else if ((p.look == NebulaLook.glass || p.look == NebulaLook.soft) &&
          i < n - 1) {
        items.add(const SizedBox(width: 4));
      }
    }
    final Widget row = Row(children: items);
    final Widget track = switch (p.look) {
      NebulaLook.minimal => Container(
        height: 48,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          border: Border.all(color: p.borderStrong),
          borderRadius: BorderRadius.circular(p.radiusMd),
        ),
        child: row,
      ),
      NebulaLook.expressive => SizedBox(height: 48, child: row),
      NebulaLook.glass => SizedBox(
        height: 56,
        child: NebulaPanel(padding: const EdgeInsets.all(4), child: row),
      ),
      NebulaLook.soft => Container(
        height: 56,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: p.subtle,
          borderRadius: BorderRadius.circular(p.radiusMd),
        ),
        child: row,
      ),
    };
    return Semantics(
      container: true,
      label: semanticsLabel,
      explicitChildNodes: true,
      child: track,
    );
  }
}

enum NebulaNoticeKind { info, warning, error, success }

/// An icon and text on a 10-16% tint of its colour: info in the accent.
class NebulaNotice extends StatelessWidget {
  const NebulaNotice({
    required this.text,
    super.key,
    this.kind = NebulaNoticeKind.info,
  });

  final String text;
  final NebulaNoticeKind kind;

  @override
  Widget build(BuildContext context) {
    final NebulaPalette p = context.palette;
    final (Color c, IconData icon) = switch (kind) {
      NebulaNoticeKind.info => (p.blueText, Icons.info_outline),
      NebulaNoticeKind.warning => (p.amberText, Icons.warning_amber_rounded),
      NebulaNoticeKind.error => (p.redText, Icons.error_outline),
      NebulaNoticeKind.success => (p.ok, Icons.check_circle_outline),
    };
    return Semantics(
      liveRegion: kind == NebulaNoticeKind.error,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: nebulaTint(p, c, p.isDark ? 16 : 10),
          borderRadius: BorderRadius.circular(p.radiusMd),
          border: p.look == NebulaLook.minimal
              ? Border.all(color: nebulaMix(c, 45, p.canvas))
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 20, color: c),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 14,
                  height: 20 / 14,
                  color: p.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
