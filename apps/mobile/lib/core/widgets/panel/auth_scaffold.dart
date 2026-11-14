import 'package:flutter/material.dart';

import '../../theme/color_tokens.dart';
import '../../theme/type_scale.dart';
import '../nebula/nebula_controls.dart';
import '../nebula/nebula_page.dart';

/// The shape every auth screen shares.
///
/// Back arrow, a 40px title, one mono sub-line, a 14px-gap stack of fields,
/// and the action at the thumb. Six screens use it, which is exactly why it
/// is one widget: the six drifted apart in the old design -- different
/// paddings, two of them with a card, one centring its button -- and a person
/// moving between sign-in, activation and password reset saw three different
/// apps.
///
/// Scrollable, and the action sits below the fields rather than pinned to the
/// bottom of the viewport: with a keyboard open on a short phone, a pinned
/// button either covers a field or is covered by the keyboard.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    required this.title,
    required this.fields,
    required this.action,
    super.key,
    this.subline,
    this.showBack = true,
    this.footer,
    this.errorMessage,
    this.aboveAction,
    this.notice,
  });

  /// A notice above the title: why this screen is showing (the session ended).
  final Widget? notice;

  /// Rendered as given, so a screen can break it across lines the way the
  /// design does ("Check\nyour email").
  final String title;

  /// The one mono line under the title.
  final String? subline;

  /// Inputs, laid out with 14px between them.
  final List<Widget> fields;

  /// The primary action.
  final Widget action;

  /// Anything between the fields and the action -- a right-aligned "Forgot
  /// password", a minimum-length note.
  final Widget? aboveAction;

  /// A row of secondary routes under the action.
  final Widget? footer;

  /// Shown above the action, in the error colour. Null hides the space
  /// entirely rather than reserving an empty gap.
  final String? errorMessage;

  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final NebulaPalette palette = context.palette;
    final NebulaTypography type = context.type;
    final EdgeInsets pad = nebulaPagePadding(context);

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              height: 60,
              child: showBack && Navigator.of(context).canPop()
                  ? Padding(
                      padding: EdgeInsets.only(left: pad.left, top: 16),
                      child: const Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: NebulaBackButton(),
                      ),
                    )
                  : null,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: pad.left),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const SizedBox(height: 8),
                    if (notice != null) ...<Widget>[
                      notice!,
                      const SizedBox(height: 20),
                    ],
                    Text(
                      title,
                      style: type.authTitle.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                    if (subline != null) ...<Widget>[
                      const SizedBox(height: 12),
                      Text(
                        subline!,
                        style: type.topBarMeta.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                    const SizedBox(height: 36),
                    for (int i = 0; i < fields.length; i++) ...<Widget>[
                      if (i > 0) const SizedBox(height: 14),
                      fields[i],
                    ],
                    if (aboveAction != null) ...<Widget>[
                      const SizedBox(height: 14),
                      aboveAction!,
                    ],
                    if (errorMessage != null) ...<Widget>[
                      const SizedBox(height: 16),
                      NebulaNotice(
                        text: errorMessage!,
                        kind: NebulaNoticeKind.error,
                      ),
                    ],
                    const SizedBox(height: 28),
                    action,
                    if (footer != null) ...<Widget>[
                      const SizedBox(height: 12),
                      footer!,
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The mono note under a password field, which turns accent once satisfied.
///
/// The design shows a `check` appearing when the minimum is met. Saying only
/// "12 characters minimum" leaves someone counting; showing when it is
/// satisfied answers the question they actually have.
class PasswordRequirementNote extends StatelessWidget {
  const PasswordRequirementNote({
    required this.satisfied,
    required this.text,
    super.key,
  });

  final bool satisfied;
  final String text;

  @override
  Widget build(BuildContext context) {
    final NebulaPalette palette = context.palette;
    return Row(
      children: <Widget>[
        if (satisfied) ...<Widget>[
          Icon(Icons.check, size: 16, color: palette.blue),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            text,
            style: context.type.listMeta.copyWith(
              color: satisfied ? palette.blueText : palette.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}
