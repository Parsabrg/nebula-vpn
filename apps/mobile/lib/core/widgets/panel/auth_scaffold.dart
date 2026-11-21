import 'package:material_ui/material_ui.dart';

import '../../theme/color_tokens.dart';
import '../../theme/look.dart';
import '../nebula/nebula_controls.dart';
import '../nebula/nebula_data.dart';
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
    final EdgeInsets pad = nebulaPagePadding(context);
    final bool compact = nebulaCompact(context);
    final double inset = palette.look == NebulaLook.minimal ? 0 : 4;
    final bool helpNote = aboveAction is PasswordRequirementNote;

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // The design: 28 above a back button (16 on a compact phone),
            // or a 64 gap (32) where there is nothing to go back to.
            if (showBack && Navigator.of(context).canPop())
              Padding(
                padding: EdgeInsets.only(
                  left: pad.left,
                  top: nebulaCompact(context) ? 16 : 28,
                  bottom: 4,
                ),
                child: const Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: NebulaBackButton(),
                ),
              )
            else
              SizedBox(height: nebulaCompact(context) ? 32 : 64),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: pad.left),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (notice != null) ...<Widget>[
                      notice!,
                      const SizedBox(height: 20),
                    ],
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: inset),
                      child: Semantics(
                        header: true,
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: compact ? 34 : 40,
                            height: compact ? 40 / 34 : 46 / 40,
                            fontWeight:
                                palette.look == NebulaLook.glass ||
                                    palette.look == NebulaLook.soft
                                ? FontWeight.w600
                                : FontWeight.w500,
                            letterSpacing: -1.4,
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    if (subline != null) ...<Widget>[
                      const SizedBox(height: 10),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: inset),
                        child: NebulaEyebrow(text: subline!),
                      ),
                    ],
                    for (final Widget field in fields) ...<Widget>[
                      const SizedBox(height: 16),
                      field,
                    ],
                    // A field's help note sits 6 under it, the button 24
                    // below; a link ("Forgot password") 4 under, the button 8.
                    if (aboveAction != null) ...<Widget>[
                      SizedBox(height: helpNote ? 6 : 4),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: helpNote ? inset : 0,
                        ),
                        child: aboveAction,
                      ),
                    ],
                    if (errorMessage != null) ...<Widget>[
                      const SizedBox(height: 16),
                      NebulaNotice(
                        text: errorMessage!,
                        kind: NebulaNoticeKind.error,
                      ),
                    ],
                    SizedBox(height: aboveAction != null && !helpNote ? 8 : 24),
                    action,
                    ?footer,
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
            // The design's field help: 13/18, not mono.
            style: TextStyle(
              fontSize: 13,
              height: 18 / 13,
              color: satisfied ? palette.blueText : palette.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}
