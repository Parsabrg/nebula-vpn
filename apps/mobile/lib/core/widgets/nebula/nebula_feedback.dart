import 'package:material_ui/material_ui.dart';

import '../../theme/color_tokens.dart';
import 'nebula_controls.dart';
import 'nebula_surface.dart';

/// A dialog in the redesign's shape: up to 340 wide, the large radius, a
/// 20/26 title, a 15/22 muted body, then [actions]. Flutter's dialog route
/// already traps focus, closes on Escape and gives focus back on close.
class NebulaDialog extends StatelessWidget {
  const NebulaDialog({
    required this.title,
    super.key,
    this.body,
    this.content,
    this.actions = const <Widget>[],
    this.alert = false,
  });

  final String title;
  final String? body;
  final Widget? content;
  final List<Widget> actions;

  /// A destructive confirmation: announced as an alert dialog.
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final NebulaPalette p = context.palette;
    return Dialog(
      backgroundColor: p.dialog,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(p.radiusLg),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Semantics(
          scopesRoute: true,
          namesRoute: true,
          explicitChildNodes: true,
          label: title,
          // "alertdialog" for the destructive ones.
          liveRegion: alert,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 20,
                    height: 26 / 20,
                    fontWeight: FontWeight.w600,
                    color: p.textPrimary,
                  ),
                ),
                if (body != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(
                    body!,
                    style: TextStyle(
                      fontSize: 15,
                      height: 22 / 15,
                      color: p.textMuted,
                    ),
                  ),
                ],
                if (content != null) ...<Widget>[
                  const SizedBox(height: 12),
                  content!,
                ],
                if (actions.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 24),
                  Row(
                    children: <Widget>[
                      for (int i = 0; i < actions.length; i++) ...<Widget>[
                        if (i > 0) const SizedBox(width: 10),
                        Expanded(child: actions[i]),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks [title] with Cancel and [action]; true when the action was chosen.
/// [destructive] makes the action red and the dialog an alert.
Future<bool> showNebulaConfirm(
  BuildContext context, {
  required String title,
  required String action,
  required String cancel,
  String? body,
  bool destructive = false,
}) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => NebulaDialog(
      title: title,
      body: body,
      alert: destructive,
      actions: <Widget>[
        NebulaButton.secondary(
          label: cancel,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        if (destructive)
          NebulaButton.danger(
            label: action,
            onPressed: () => Navigator.of(context).pop(true),
          )
        else
          NebulaButton(
            label: action,
            onPressed: () => Navigator.of(context).pop(true),
          ),
      ],
    ),
  );
  return ok ?? false;
}

/// A radio list in a dialog: every option set of more than three items
/// (DESIGN_SPEC §3). Null when dismissed.
Future<T?> showNebulaChoice<T>(
  BuildContext context, {
  required String title,
  required List<(T, String)> options,
  required T selected,
  String? subtitle,
}) => showDialog<T>(
  context: context,
  builder: (BuildContext context) {
    final NebulaPalette p = context.palette;
    return NebulaDialog(
      title: title,
      body: subtitle,
      content: RadioGroup<T>(
        groupValue: selected,
        onChanged: (T? value) => Navigator.of(context).pop(value),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final (T value, String label) in options)
              NebulaPressable(
                onTap: () => Navigator.of(context).pop(value),
                selected: value == selected,
                borderRadius: BorderRadius.circular(p.radiusSm),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(
                    children: <Widget>[
                      Radio<T>(value: value, activeColor: p.blue),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 16,
                            height: 22 / 16,
                            color: p.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  },
);

/// The snackbar: inverse colours, at least 48 tall, above the footer and
/// tab bar, gone after about 3 s; read out as a status.
void showNebulaSnackbar(BuildContext context, String message) {
  final NebulaPalette p = context.palette;
  final bool dark = p.isDark;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        backgroundColor: dark
            ? const Color(0xFFEDEDF2)
            : const Color(0xFF1F1F26),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            p.radiusMd < 14 ? p.radiusMd : 14,
          ),
        ),
        content: Semantics(
          liveRegion: true,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 24),
            child: Text(
              message,
              style: TextStyle(
                fontSize: 14,
                height: 20 / 14,
                color: dark ? const Color(0xFF101014) : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
}
