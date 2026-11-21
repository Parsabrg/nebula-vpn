import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/app_info.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/auth/auth_state.dart';
import '../../core/free/free_mode.dart';
import '../../core/network/error_copy.dart';
import '../../core/pairing/pairing.dart';
import '../../core/pairing/pairing_providers.dart';
import '../../core/routing/route_paths.dart';
import '../../core/settings/locale_controller.dart';
import '../../core/widgets/nebula/nebula_controls.dart';
import '../../core/widgets/nebula/nebula_data.dart';
import '../../core/widgets/nebula/nebula_rows.dart';
import '../../core/widgets/panel/auth_scaffold.dart';
import '../../core/widgets/panel/panel_cta.dart';
import '../../core/widgets/password_field.dart';
import '../../l10n/app_localizations.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(authNotifierProvider.notifier)
          .login(
            identifier: _identifierController.text.trim(),
            password: _passwordController.text,
            deviceName: await readDeviceName(),
            platform: currentDevicePlatform,
            clientVersion: kClientVersion,
          );
      // Tells the password manager the sign-in worked: it offers to save the
      // password, or to update a saved one that differs. Without this it was
      // never asked, and saved once only by chance.
      TextInput.finishAutofillContext();
    } catch (error) {
      if (mounted) {
        setState(
          () => _errorMessage = userFacingErrorMessage(
            error,
            ref.read(appTextProvider),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppText text = AppText.of(context);
    final AuthState authState = ref.watch(authNotifierProvider);
    final bool sessionExpired = authState is AuthSessionExpired;
    final Pairing? pairing = ref.watch(pairingProvider);

    // One form for the password manager, so it pairs the username with the
    // password. Leaving the screen any other way saves nothing: a wrong
    // password must never replace a saved one.
    return AutofillGroup(
      onDisposeAction: AutofillContextAction.cancel,
      child: Form(
        key: _formKey,
        child: AuthScaffold(
          title: text.signInTitle,
          notice: sessionExpired
              ? NebulaNotice(text: text.signInSessionEnded)
              : null,
          subline: text.signInSubline,
          errorMessage: _errorMessage,
          fields: <Widget>[
            NebulaLabeledField(
              label: text.fieldEmailOrUsername,
              child: TextFormField(
                controller: _identifierController,
                autofillHints: const <String>[
                  AutofillHints.username,
                  AutofillHints.email,
                ],
                decoration: const InputDecoration(),
                validator: (String? value) =>
                    (value == null || value.trim().isEmpty)
                    ? text.validateEmailOrUsername
                    : null,
              ),
            ),
            PasswordField(
              controller: _passwordController,
              labelText: text.fieldPassword,
              autofillHints: const <String>[AutofillHints.password],
              validator: (String? value) => (value == null || value.isEmpty)
                  ? text.validatePassword
                  : null,
            ),
          ],
          aboveAction: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: () => context.push(RoutePaths.passwordReset),
              child: Text(text.forgotPassword),
            ),
          ),
          action: PanelCta(
            label: _submitting ? text.signingIn : text.continueAction,
            onPressed: _submitting ? null : _submit,
          ),
          // The ways in for someone who cannot sign in yet, as rows under
          // the action rather than more buttons as wide as it.
          footer: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              NebulaSectionLabel(text.signInNoAccountYet),
              NebulaRowGroup(
                children: <Widget>[
                  NebulaRow(
                    icon: Icons.person_add_alt,
                    title: text.requestAccess,
                    subtitle: text.requestAccessSubline,
                    trailing: NebulaRowTrailing.chevron(context),
                    onTap: () => context.push(RoutePaths.accountRequest),
                  ),
                  // Without this the activation screen is unreachable: the
                  // route exists and is registered, but nothing navigated to
                  // it, so an approved user holding an activation code had no
                  // way to spend it and was left at a sign-in form asking for
                  // a password they had never been able to set.
                  NebulaRow(
                    icon: Icons.key_outlined,
                    title: text.haveACode,
                    subtitle: text.codeFromEmail,
                    trailing: NebulaRowTrailing.chevron(context),
                    onTap: () => context.push(RoutePaths.activate),
                  ),
                ],
              ),
              if (pairing?.deploymentName != null) ...<Widget>[
                const SizedBox(height: 16),
                // Which deployment this is, checked against what the person
                // expects before they type a password into it.
                NebulaRowGroup(
                  children: <Widget>[
                    NebulaRow(
                      icon: Icons.dns_outlined,
                      title: text.rowServer,
                      subtitle: pairing!.deploymentName,
                      trailing: NebulaButton.rowAction(
                        label: text.changeServer,
                        onPressed: () =>
                            ref.read(pairingProvider.notifier).forget(),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              NebulaButton.text(
                label: text.freeEnter,
                onPressed: () => ref.read(freeModeProvider.notifier).enter(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
