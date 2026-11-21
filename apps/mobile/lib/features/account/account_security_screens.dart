import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/account/account_repository.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/error_copy.dart';
import '../../core/settings/locale_controller.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/look.dart';
import '../../core/widgets/nebula/nebula_controls.dart';
import '../../core/widgets/nebula/nebula_page.dart';
import '../../core/widgets/panel/auth_scaffold.dart';
import '../../core/widgets/panel/panel_cta.dart';
import '../../core/widgets/password_field.dart';
import '../../l10n/app_localizations.dart';
import '../devices/devices_controller.dart';

/// What to show for a refused password change or deletion. The server
/// answers 403 for a wrong password -- not 401, which would sign out.
String _refusal(Object error, AppText text) =>
    error is NebulaApiException &&
        error.statusCode == 403 &&
        error.detail == 'password_not_accepted'
    ? text.passwordNotAccepted
    : userFacingErrorMessage(error, text);

/// The frame both screens share: a back arrow, a title, the fields, and the
/// action at the thumb.
class _Frame extends StatelessWidget {
  const _Frame({
    required this.title,
    required this.fields,
    required this.action,
  });

  final String title;
  final List<Widget> fields;
  final Widget action;

  @override
  Widget build(BuildContext context) =>
      NebulaPage(title: title, footer: action, children: fields);
}

/// The design's body text (15/22, muted) and small print (13/19).
Widget _text(BuildContext context, String value, {bool small = false}) {
  final NebulaPalette p = context.palette;
  return Padding(
    padding: EdgeInsets.only(
      top: small ? 10 : 12,
      left: p.look == NebulaLook.minimal ? 0 : (small ? 8 : 4),
      right: p.look == NebulaLook.minimal ? 0 : (small ? 8 : 4),
    ),
    child: Text(
      value,
      style: TextStyle(
        fontSize: small ? 13 : 15,
        height: small ? 19 / 13 : 22 / 15,
        color: p.textMuted,
      ),
    ),
  );
}

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _current = TextEditingController();
  final TextEditingController _next = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final AppText text = ref.read(appTextProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(accountRepositoryProvider)
          .changePassword(
            currentPassword: _current.text,
            newPassword: _next.text,
          );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(text.passwordChanged)));
      context.pop();
    } catch (error) {
      if (mounted) {
        setState(() => _error = _refusal(error, text));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppText text = AppText.of(context);
    return Form(
      key: _formKey,
      child: _Frame(
        title: text.changePasswordTitle,
        fields: <Widget>[
          _text(context, text.changePasswordIntro),
          const SizedBox(height: 16),
          PasswordField(
            controller: _current,
            labelText: text.fieldCurrentPassword,
            autofillHints: const <String>[AutofillHints.password],
            validator: (String? value) =>
                (value == null || value.isEmpty) ? text.validatePassword : null,
          ),
          const SizedBox(height: 16),
          PasswordField(
            controller: _next,
            labelText: text.fieldNewPassword,
            autofillHints: const <String>[AutofillHints.newPassword],
            onChanged: (_) => setState(() {}),
            validator: (String? value) => (value == null || value.length < 12)
                ? text.validateNewPassword
                : null,
          ),
          const SizedBox(height: 6),
          PasswordRequirementNote(
            satisfied: _next.text.length >= 12,
            text: text.passwordMinimum,
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 16),
            NebulaNotice(text: _error!, kind: NebulaNoticeKind.error),
          ],
        ],
        action: PanelCta(
          label: _busy ? text.changingPassword : text.changePasswordAction,
          onPressed: _busy ? null : _submit,
        ),
      ),
    );
  }
}

class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final AppText text = ref.read(appTextProvider);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Asked first: a mistyped password must not cost the tunnel.
      await ref.read(accountRepositoryProvider).deleteAccount(_password.text);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _refusal(error, text);
        });
      }
      return;
    }
    // Gone on the server, credentials included: stop the tunnel here without
    // asking it, forget the session, and the router shows sign-in.
    messenger.showSnackBar(SnackBar(content: Text(text.accountDeleted)));
    await ref.read(devicesControllerProvider.notifier).endAfterSessionLost();
    await ref.read(authNotifierProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    final AppText text = AppText.of(context);
    return Form(
      key: _formKey,
      child: _Frame(
        title: text.deleteAccountTitle,
        fields: <Widget>[
          const SizedBox(height: 16),
          NebulaNotice(
            text: text.deleteAccountIntro,
            kind: NebulaNoticeKind.error,
          ),
          _text(context, text.deleteAccountKept, small: true),
          const SizedBox(height: 16),
          PasswordField(
            controller: _password,
            labelText: text.fieldPassword,
            autofillHints: const <String>[AutofillHints.password],
            validator: (String? value) =>
                (value == null || value.isEmpty) ? text.validatePassword : null,
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 16),
            NebulaNotice(text: _error!, kind: NebulaNoticeKind.error),
          ],
        ],
        action: NebulaButton.danger(
          label: _busy ? text.deletingAccount : text.deleteAccountAction,
          onPressed: _busy ? null : _submit,
        ),
      ),
    );
  }
}
