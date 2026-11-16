import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../format/case.dart';
import '../../theme/color_tokens.dart';
import '../../theme/look.dart';
import 'nebula_surface.dart';

/// The Connect screen's status: an eyebrow with a status dot and the
/// server, the display title, and a sub-line. Bare on Minimal, a container
/// on Liquid glass and Soft cards, an accent-tinted card on Expressive.
class NebulaStatusHero extends StatelessWidget {
  const NebulaStatusHero({
    required this.dotColor,
    required this.eyebrow,
    required this.title,
    super.key,
    this.subline,
    this.sublineColor,
    this.titleColor,
  });

  final Color dotColor;
  final String eyebrow;
  final String title;
  final String? subline;
  final Color? sublineColor;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final NebulaPalette p = context.palette;
    final bool minimal = p.look == NebulaLook.minimal;
    final bool compact = MediaQuery.sizeOf(context).width < 340;
    final double display = compact
        ? 34
        : (p.look == NebulaLook.expressive ? 44 : 40);
    final Widget column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                minimal ? upperCaseFor(context, eyebrow) : eyebrow,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: minimal
                    ? TextStyle(
                        fontFamily: 'GeistMono',
                        fontSize: 12,
                        height: 16 / 12,
                        letterSpacing: 1.2,
                        color: p.textMuted,
                      )
                    : TextStyle(
                        fontSize: 14,
                        height: 20 / 14,
                        fontWeight: FontWeight.w500,
                        color: p.textMuted,
                      ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Semantics(
          header: true,
          liveRegion: true,
          child: Text(
            title,
            style: TextStyle(
              fontSize: display,
              height: (display + 6) / display,
              fontWeight:
                  p.look == NebulaLook.minimal ||
                      p.look == NebulaLook.expressive
                  ? FontWeight.w500
                  : FontWeight.w600,
              letterSpacing: p.look == NebulaLook.expressive ? -1.8 : -1.4,
              color: titleColor ?? p.textPrimary,
            ),
          ),
        ),
        if (subline != null && subline!.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            subline!,
            style: TextStyle(
              fontSize: 15,
              height: 22 / 15,
              color: sublineColor ?? p.textMuted,
            ),
          ),
        ],
      ],
    );
    return switch (p.look) {
      NebulaLook.minimal => Padding(
        padding: EdgeInsets.only(top: compact ? 24 : 40, bottom: 8),
        child: column,
      ),
      NebulaLook.expressive => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(24),
        width: double.infinity,
        decoration: BoxDecoration(
          color: nebulaMix(p.blue, p.isDark ? 22 : 16, p.canvas),
          borderRadius: BorderRadius.circular(p.radiusLg),
        ),
        child: column,
      ),
      NebulaLook.glass || NebulaLook.soft => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: SizedBox(
          width: double.infinity,
          child: NebulaPanel(
            radius: p.radiusLg,
            padding: const EdgeInsets.all(20),
            child: column,
          ),
        ),
      ),
    };
  }
}

/// Figures in two columns: label, then value in mono. An odd last one takes
/// the full width.
class NebulaStatsGrid extends StatelessWidget {
  const NebulaStatsGrid({required this.stats, super.key});

  final List<(String, String)> stats;

  @override
  Widget build(BuildContext context) {
    final NebulaPalette p = context.palette;
    final bool minimal = p.look == NebulaLook.minimal;
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < stats.length; i += 2) {
      final bool pair = i + 1 < stats.length;
      rows.add(
        DecoratedBox(
          decoration: BoxDecoration(
            border: i > 0
                ? Border(top: BorderSide(color: p.hairline))
                : const Border(),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(child: _cell(p, stats[i], minimal, first: true)),
                if (pair) ...<Widget>[
                  VerticalDivider(width: 1, thickness: 1, color: p.hairline),
                  Expanded(
                    child: _cell(p, stats[i + 1], minimal, first: false),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    final Widget grid = Column(children: rows);
    return minimal
        ? DecoratedBox(
            decoration: BoxDecoration(
              border: Border.symmetric(
                horizontal: BorderSide(color: p.hairline),
              ),
            ),
            child: grid,
          )
        : NebulaPanel(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(p.radiusMd),
              child: grid,
            ),
          );
  }

  Widget _cell(
    NebulaPalette p,
    (String, String) stat,
    bool minimal, {
    required bool first,
  }) => Padding(
    padding: minimal
        ? EdgeInsets.fromLTRB(first ? 0 : 16, 16, 0, 16)
        : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          stat.$1,
          style: TextStyle(fontSize: 13, height: 18 / 13, color: p.textMuted),
        ),
        const SizedBox(height: 4),
        Text(
          stat.$2,
          style: TextStyle(
            fontFamily: 'GeistMono',
            fontSize: 16,
            height: 22 / 16,
            color: p.textPrimary,
          ),
        ),
      ],
    ),
  );
}

/// A 6 px meter, [fraction] full, in [color] or the accent.
class NebulaUsageMeter extends StatelessWidget {
  const NebulaUsageMeter({
    required this.fraction,
    super.key,
    this.color,
    this.semanticLabel,
  });

  final double fraction;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final NebulaPalette p = context.palette;
    return Semantics(
      label: semanticLabel,
      value: '${(fraction.clamp(0, 1) * 100).round()}%',
      child: Container(
        height: 6,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: p.look == NebulaLook.minimal ? p.hairline : p.subtle,
          borderRadius: BorderRadius.circular(3),
        ),
        alignment: AlignmentDirectional.centerStart,
        child: FractionallySizedBox(
          widthFactor: fraction.clamp(0.02, 1).toDouble(),
          heightFactor: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color ?? p.blue,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
    );
  }
}

/// Nothing to show: an icon, a title and what to do, in a dashed-looking
/// outline on Minimal and the look's container elsewhere.
class NebulaEmptyState extends StatelessWidget {
  const NebulaEmptyState({
    required this.title,
    super.key,
    this.icon = Icons.inbox_outlined,
    this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final NebulaPalette p = context.palette;
    final Widget column = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      child: Column(
        children: <Widget>[
          Icon(icon, size: 32, color: p.textMuted),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              height: 22 / 16,
              fontWeight: FontWeight.w500,
              color: p.textPrimary,
            ),
          ),
          if (body != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              body!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 20 / 14,
                color: p.textMuted,
              ),
            ),
          ],
          if (action != null) ...<Widget>[const SizedBox(height: 12), action!],
        ],
      ),
    );
    return SizedBox(
      width: double.infinity,
      child: p.look == NebulaLook.minimal
          ? DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: p.borderStrong),
                borderRadius: BorderRadius.circular(p.radiusMd),
              ),
              child: column,
            )
          : NebulaPanel(radius: p.radiusLg, child: column),
    );
  }
}

/// A form field: the label above (14/20, 500), a box at least 52 tall, help
/// below in muted, or the error in red (500) with the field marked invalid;
/// a password gets a 44 px show/hide button, a field an inline Add.
class NebulaField extends StatefulWidget {
  const NebulaField({
    required this.label,
    super.key,
    this.controller,
    this.hint,
    this.help,
    this.errorText,
    this.password = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.mono = false,
    this.addLabel,
    this.onAdd,
    this.showLabel,
    this.hideLabel,
    this.inputFormatters,
    this.autocorrect = true,
    this.prefixIcon,
    this.labelVisible = true,
    this.autofocus = false,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? help;
  final String? errorText;
  final bool password;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final bool mono;
  final String? addLabel;
  final VoidCallback? onAdd;
  final String? showLabel;
  final String? hideLabel;
  final List<TextInputFormatter>? inputFormatters;
  final bool autocorrect;
  final IconData? prefixIcon;

  /// The label is still read out when hidden (a search box).
  final bool labelVisible;

  final bool autofocus;

  @override
  State<NebulaField> createState() => _NebulaFieldState();
}

class _NebulaFieldState extends State<NebulaField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    final NebulaPalette p = context.palette;
    final bool minimal = p.look == NebulaLook.minimal;
    final bool bad = widget.errorText != null;
    final EdgeInsets inset = EdgeInsets.symmetric(horizontal: minimal ? 0 : 4);

    final BoxDecoration box = switch (p.look) {
      NebulaLook.minimal => BoxDecoration(
        borderRadius: BorderRadius.circular(p.radiusMd),
        border: Border.all(
          color: bad ? p.redText : p.borderStrong,
          width: bad ? 2 : 1,
        ),
      ),
      NebulaLook.glass => BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: bad
              ? p.redText
              : (p.isDark ? const Color(0x24FFFFFF) : const Color(0xE6FFFFFF)),
          width: bad ? 2 : 1,
        ),
      ),
      NebulaLook.expressive => BoxDecoration(
        color: p.subtle,
        borderRadius: BorderRadius.circular(16),
        border: bad ? Border.all(color: p.redText, width: 2) : null,
      ),
      NebulaLook.soft => BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(p.radiusSm + 4),
        border: Border.all(
          color: bad
              ? p.redText
              : (p.isDark ? p.hairline : const Color(0xFFDCDDE4)),
          width: bad ? 2 : 1,
        ),
      ),
    };

    final Widget input = TextField(
      controller: widget.controller,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      obscureText: widget.password && _obscured,
      enableSuggestions: !widget.password,
      autocorrect: widget.autocorrect && !widget.password,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      autofillHints: widget.autofillHints,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      inputFormatters: widget.inputFormatters,
      cursorColor: p.blue,
      style: TextStyle(
        fontFamily: widget.mono ? 'GeistMono' : null,
        fontSize: widget.mono ? 14 : 16,
        color: p.textPrimary,
      ),
      decoration: InputDecoration(
        isCollapsed: true,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        hintText: widget.hint,
        hintStyle: TextStyle(fontSize: 16, color: p.textMuted),
        contentPadding: const EdgeInsets.symmetric(vertical: 15),
      ),
    );

    return Semantics(
      label: widget.label,
      textField: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (widget.labelVisible) ...<Widget>[
            Padding(
              padding: inset,
              child: ExcludeSemantics(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 14,
                    height: 20 / 14,
                    fontWeight: FontWeight.w500,
                    color: p.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
          Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.only(left: 14, right: 6),
            decoration: box,
            child: Row(
              children: <Widget>[
                if (widget.prefixIcon != null) ...<Widget>[
                  Icon(widget.prefixIcon, size: 20, color: p.textMuted),
                  const SizedBox(width: 10),
                ],
                Expanded(child: input),
                if (widget.password)
                  Tooltip(
                    message: _obscured
                        ? (widget.showLabel ?? '')
                        : (widget.hideLabel ?? ''),
                    child: NebulaPressable(
                      onTap: () => setState(() => _obscured = !_obscured),
                      borderRadius: BorderRadius.circular(22),
                      semanticLabel: _obscured
                          ? widget.showLabel
                          : widget.hideLabel,
                      excludeChildSemantics: true,
                      child: SizedBox.square(
                        dimension: 44,
                        child: Icon(
                          _obscured
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                          color: p.textMuted,
                        ),
                      ),
                    ),
                  ),
                if (widget.onAdd != null && widget.addLabel != null)
                  NebulaPressable(
                    onTap: widget.onAdd,
                    borderRadius: BorderRadius.circular(
                      p.radiusButton < 20 ? p.radiusButton : 20,
                    ),
                    semanticLabel: widget.addLabel,
                    excludeChildSemantics: true,
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: p.blue,
                        borderRadius: BorderRadius.circular(
                          p.radiusButton < 20 ? p.radiusButton : 20,
                        ),
                      ),
                      child: Text(
                        widget.addLabel!,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: p.onAccent,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (bad || widget.help != null) ...<Widget>[
            const SizedBox(height: 6),
            Padding(
              padding: inset,
              child: Semantics(
                liveRegion: bad,
                child: Text(
                  bad ? widget.errorText! : widget.help!,
                  style: TextStyle(
                    fontSize: 13,
                    height: 18 / 13,
                    fontWeight: bad ? FontWeight.w500 : FontWeight.w400,
                    color: bad ? p.redText : p.textMuted,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The small status line with a dot: mono capitals on Minimal, 14 px
/// medium elsewhere (the design's eyebrow).
class NebulaEyebrow extends StatelessWidget {
  const NebulaEyebrow({required this.text, super.key, this.dot});

  final String text;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    final NebulaPalette p = context.palette;
    final bool minimal = p.look == NebulaLook.minimal;
    return Row(
      children: <Widget>[
        if (dot != null) ...<Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            minimal ? upperCaseFor(context, text) : text,
            style: minimal
                ? TextStyle(
                    fontFamily: 'GeistMono',
                    fontSize: 12,
                    height: 16 / 12,
                    letterSpacing: 1.2,
                    color: p.textMuted,
                  )
                : TextStyle(
                    fontSize: 14,
                    height: 20 / 14,
                    fontWeight: FontWeight.w500,
                    color: p.textMuted,
                  ),
          ),
        ),
      ],
    );
  }
}

/// A label and a mono figure on one line with a meter under it (the
/// design's lede meter: "3 of 100 devices" and "3 / 100").
class NebulaLedeMeter extends StatelessWidget {
  const NebulaLedeMeter({
    required this.label,
    required this.value,
    required this.fraction,
    super.key,
  });

  final String label;
  final String value;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final NebulaPalette p = context.palette;
    final TextStyle style = TextStyle(
      fontSize: 15,
      height: 22 / 15,
      color: p.textMuted,
    );
    return Padding(
      padding: EdgeInsets.only(
        top: 8,
        left: p.look == NebulaLook.minimal ? 0 : 4,
        right: p.look == NebulaLook.minimal ? 0 : 4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Expanded(child: Text(label, style: style)),
              const SizedBox(width: 12),
              Text(
                value,
                textDirection: TextDirection.ltr,
                style: style.copyWith(fontFamily: 'GeistMono'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          NebulaUsageMeter(fraction: fraction),
        ],
      ),
    );
  }
}

/// A label above any field, as the design draws every field: 14 px medium,
/// 6 above the box. The label names the field for screen readers too.
class NebulaLabeledField extends StatelessWidget {
  const NebulaLabeledField({
    required this.label,
    required this.child,
    super.key,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final NebulaPalette p = context.palette;
    final double inset = p.look == NebulaLook.minimal ? 0 : 4;
    return Semantics(
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.symmetric(horizontal: inset),
            child: ExcludeSemantics(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  height: 20 / 14,
                  fontWeight: FontWeight.w500,
                  color: p.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}
