import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/account/account_repository.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/auth/auth_state.dart';
import '../../core/auth/user_principal.dart';
import '../../core/format/bidi.dart';
import '../../core/format/bytes.dart';
import '../../core/format/case.dart';
import '../../core/format/dates.dart';
import '../../core/routing/route_paths.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/look.dart';
import '../../core/updates/update_check.dart';
import '../../core/widgets/nebula/nebula_controls.dart';
import '../../core/widgets/nebula/nebula_data.dart';
import '../../core/widgets/nebula/nebula_feedback.dart';
import '../../core/widgets/nebula/nebula_page.dart';
import '../../core/widgets/nebula/nebula_rows.dart';
import '../../core/widgets/nebula/nebula_surface.dart';
import '../../core/widgets/panel/panel_atoms.dart';
import '../../core/widgets/refresh_while_visible.dart';
import '../../l10n/app_localizations.dart';
import '../devices/devices_controller.dart';
import 'account_controller.dart';
import 'subscription_dialog.dart';
import 'update_dialog.dart';

/// The account: who you are, what you have used, until when, and the way out.
///
/// The usage figures are measured on the server, every minute, and fetched
/// again while this screen is showing -- see _AccountScreenState.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen>
    with RefreshWhileVisible<AccountScreen> {
  @override
  Duration get refreshInterval => ref.read(accountRefreshIntervalProvider);

  @override
  void refresh() {
    unawaited(ref.read(accountControllerProvider.notifier).refresh());
  }

  @override
  Widget build(BuildContext context) {
    final AccountState state = ref.watch(accountControllerProvider);
    final AppText text = AppText.of(context);

    return NebulaPage(
      title: text.tabAccount,
      showBack: false,
      // Settings is not a tab -- this gear is the way in.
      trailing: NebulaHeaderAction(
        icon: Icons.settings_outlined,
        label: text.rowSettings,
        onTap: () => context.push(RoutePaths.homeSettings),
      ),
      children: _body(context, state),
    );
  }

  List<Widget> _body(BuildContext context, AccountState state) {
    final AppText text = AppText.of(context);

    switch (state.loadStatus) {
      case AccountLoadStatus.loading:
        return const <Widget>[
          SizedBox(height: 24),
          SkeletonBar(width: 180, height: 34),
          SizedBox(height: 32),
          _SkeletonRow(),
          _SkeletonRow(),
          _SkeletonRow(),
        ];

      case AccountLoadStatus.failed:
        return <Widget>[
          const SizedBox(height: 16),
          NebulaNotice(
            text: state.loadErrorMessage ?? text.couldNotLoadAccount,
            kind: NebulaNoticeKind.error,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: NebulaButton.text(
              label: text.ctaTryAgain,
              onPressed: () =>
                  ref.read(accountControllerProvider.notifier).load(),
            ),
          ),
          // Settings live on this device and need no server, so they stay
          // reachable when the account cannot load. They used to vanish with
          // it -- when the server is unreachable, which is exactly when
          // someone needs them (fragment, DNS, the local network). Seen on
          // a phone.
          const SizedBox(height: 12),
          NebulaRowGroup(
            children: <Widget>[
              NebulaRow(
                icon: Icons.tune,
                title: text.rowSettings,
                trailing: NebulaRowTrailing.chevron(context),
                onTap: () => context.push(RoutePaths.homeSettings),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _SignOutButton(),
        ];

      case AccountLoadStatus.loaded:
        return <Widget>[_Details(account: state.account!)];
    }
  }
}

class _Details extends ConsumerWidget {
  const _Details({required this.account});

  final AccountSummary account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppText text = AppText.of(context);
    final NebulaPalette palette = context.palette;

    final AuthState authState = ref.watch(authNotifierProvider);
    final UserPrincipal? me = authState is AuthAuthenticated
        ? authState.me
        : null;

    final bool expired = account.hasExpiredAt(DateTime.now());
    final AvailableUpdate? update = ref.watch(availableUpdateProvider).value;
    // Three different things, and they must not collapse into one
    // reassuring string: an expiry in the future, one that has passed, and
    // no expiry at all.
    final String until = account.expiresAt == null
        ? text.noExpiry
        : formatLongDate(context, account.expiresAt!);
    final bool healthy = account.state == 'active' && !expired;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Profile(name: account.username, email: account.email),
        _Plan(
          status: '${_stateLabel(text, account.state)} · $until',
          healthy: healthy,
          account: account,
        ),
        NebulaSectionLabel(text.sectionDetails),
        NebulaRowGroup(
          children: <Widget>[
            NebulaRow(
              title: text.rowEmail,
              // Mono, as the design sets an address.
              trailing: NebulaRowTrailing.value(context, account.email),
            ),
            NebulaRow(
              title: text.rowStatus,
              trailing: NebulaRowTrailing.value(
                context,
                _stateLabel(text, account.state),
                mono: false,
              ),
            ),
            NebulaRow(
              title: text.rowAccessUntil,
              trailing: Text(
                until,
                style: TextStyle(
                  fontSize: 14,
                  color: expired ? palette.amberText : palette.textMuted,
                ),
              ),
            ),
            if (me != null)
              NebulaRow(
                title: text.rowSessionId,
                trailing: NebulaRowTrailing.value(
                  context,
                  _truncate(me.sessionId),
                ),
              ),
          ],
        ),
        NebulaSectionLabel(text.sectionApp),
        NebulaRowGroup(
          children: <Widget>[
            if (update != null)
              NebulaRow(
                icon: Icons.system_update_outlined,
                title: text.rowUpdate,
                subtitle: text.updateAvailable(update.version),
                subtitleColor: palette.blueText,
                trailing: NebulaRowTrailing.chevron(context),
                onTap: () => offerUpdate(context, ref, update),
              ),
            NebulaRow(
              icon: Icons.phone_iphone,
              title: text.rowSubscriptionLink,
              subtitle: text.subscriptionTitle,
              trailing: NebulaRowTrailing.chevron(context),
              onTap: () => showSubscriptionLink(context, ref),
            ),
            NebulaRow(
              icon: Icons.password,
              title: text.rowPassword,
              trailing: NebulaRowTrailing.valueChevron(context, text.change),
              onTap: () => context.push(RoutePaths.homeChangePassword),
            ),
            NebulaRow(
              icon: Icons.tune,
              title: text.rowSettings,
              trailing: NebulaRowTrailing.chevron(context),
              onTap: () => context.push(RoutePaths.homeSettings),
            ),
          ],
        ),
        const SizedBox(height: 16),
        NebulaRowGroup(
          children: <Widget>[
            NebulaRow(
              icon: Icons.delete_outline,
              title: text.deleteAccountRow,
              tone: NebulaTone.danger,
              trailing: NebulaRowTrailing.chevron(context),
              onTap: () => context.push(RoutePaths.homeDeleteAccount),
            ),
          ],
        ),
        if (expired) ...<Widget>[
          const SizedBox(height: 16),
          NebulaNotice(
            text: text.accessExpired,
            kind: NebulaNoticeKind.warning,
          ),
        ],
        const SizedBox(height: 24),
        const _SignOutButton(),
        const SizedBox(height: 8),
      ],
    );
  }

  /// The account's state as a person would say it. The server sends a
  /// code; an unrecognised one is shown as sent rather than hidden, so a
  /// state added later still appears.
  static String _stateLabel(AppText text, String state) => switch (state) {
    'active' => text.accountStateActive,
    'pending_activation' => text.accountStatePendingActivation,
    'suspended' => text.accountStateSuspended,
    'disabled' => text.accountStateDisabled,
    _ => state,
  };

  /// Session ids are long and the whole value is never needed on screen.
  static String _truncate(String value) {
    if (value.length <= 13) {
      return value;
    }
    return '${value.substring(0, 8)}…${value.substring(value.length - 4)}';
  }
}

/// The avatar initial, the username, and the email under it (the email once,
/// as the title, when there is no username). The design's avatar: 52 px,
/// outlined on Minimal, filled with the accent elsewhere.
class _Profile extends StatelessWidget {
  const _Profile({required this.name, required this.email});

  final String? name;
  final String email;

  @override
  Widget build(BuildContext context) {
    final NebulaPalette p = context.palette;
    final bool minimal = p.look == NebulaLook.minimal;
    final String title = name ?? email;
    return Padding(
      padding: EdgeInsets.only(
        top: minimal ? 16 : 12,
        left: minimal ? 0 : 4,
        right: minimal ? 0 : 4,
      ),
      child: Row(
        children: <Widget>[
          ExcludeSemantics(
            child: Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: minimal ? null : p.blue,
                border: minimal ? Border.all(color: p.borderStrong) : null,
                borderRadius: BorderRadius.circular(
                  p.look == NebulaLook.expressive ? 18 : 26,
                ),
              ),
              child: Text(
                title.isEmpty ? '?' : title.characters.first.toUpperCase(),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: minimal ? p.textPrimary : p.onAccent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 20,
                    height: 26 / 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                    color: p.textPrimary,
                  ),
                ),
                if (name != null)
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 18 / 13,
                      color: p.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The design's plan block: the status, then Data and Devices side by side.
/// Between two hairlines on Minimal, a tinted card on Expressive, a panel
/// elsewhere.
class _Plan extends StatelessWidget {
  const _Plan({
    required this.status,
    required this.healthy,
    required this.account,
  });

  final String status;
  final bool healthy;
  final AccountSummary account;

  @override
  Widget build(BuildContext context) {
    final AppText text = AppText.of(context);
    final NebulaPalette p = context.palette;
    final TextStyle label = TextStyle(
      fontSize: 13,
      height: 18 / 13,
      color: p.textMuted,
    );
    final TextStyle big = TextStyle(
      fontFamily: 'GeistMono',
      fontSize: 24,
      height: 30 / 24,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.6,
      color: p.textPrimary,
    );
    final bool metered = account.isMetered;
    final String data = metered
        ? formatBytes(account.remainingBytes ?? 0)
        : formatBytes(account.lifetimeBytes);
    // Amber once the allowance is gone: a state worth noticing, not an error.
    final bool exhausted = metered && (account.remainingBytes ?? 0) == 0;
    final String dataSub = !metered
        ? text.usedNoLimit
        : exhausted
        ? text.quotaNothingLeft
        : text.quotaLeft;
    final Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // A sentence ("Active · no expiry"), capitalised as the design has
        // it; Minimal's eyebrow is in capitals anyway.
        NebulaEyebrow(
          text: status.isEmpty
              ? status
              : upperCaseFor(context, status.characters.first) +
                    status.characters.skip(1).string,
          dot: healthy ? p.ok : p.amber,
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(text.accountData, style: label),
                  const SizedBox(height: 4),
                  Text(
                    data,
                    // Drawn "KB 8.9" under Persian without this.
                    textDirection: TextDirection.ltr,
                    style: exhausted ? big.copyWith(color: p.amberText) : big,
                  ),
                  Text(
                    dataSub,
                    style: exhausted
                        ? label.copyWith(color: p.amberText)
                        : label,
                  ),
                  if (metered) ...<Widget>[
                    const SizedBox(height: 8),
                    NebulaUsageMeter(
                      fraction: account.usedFraction ?? 0,
                      color: exhausted ? p.amber : p.blue,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      text.quotaUsed(
                        embedLeftToRight(
                          context,
                          formatBytePair(
                            account.usedBytes,
                            account.quotaBytes!,
                          ),
                        ),
                      ),
                      style: label,
                    ),
                    // Only when it says something the line above does not.
                    if (account.lifetimeBytes > account.usedBytes)
                      Text(
                        text.usedInTotal(
                          embedLeftToRight(
                            context,
                            formatBytes(account.lifetimeBytes),
                          ),
                        ),
                        style: label,
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(text.tabDevices, style: label),
                  const SizedBox(height: 4),
                  Text(
                    '${account.devicesInUse} / ${account.deviceLimit}',
                    textDirection: TextDirection.ltr,
                    style: big,
                  ),
                  const SizedBox(height: 8),
                  NebulaUsageMeter(
                    fraction: account.deviceLimit <= 0
                        ? 0
                        : account.devicesInUse / account.deviceLimit,
                    semanticLabel: text.devicesOfLimit(
                      account.devicesInUse,
                      account.deviceLimit,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
    switch (p.look) {
      case NebulaLook.minimal:
        return Container(
          margin: const EdgeInsets.only(top: 24),
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: p.hairline),
              bottom: BorderSide(color: p.hairline),
            ),
          ),
          child: body,
        );
      case NebulaLook.expressive:
        return Container(
          margin: const EdgeInsets.only(top: 20),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: nebulaMix(p.blue, p.isDark ? 22 : 16, p.bg),
            borderRadius: BorderRadius.circular(p.radiusLg),
          ),
          child: body,
        );
      case NebulaLook.glass:
      case NebulaLook.soft:
        return Padding(
          padding: const EdgeInsets.only(top: 20),
          child: NebulaPanel(
            radius: p.radiusLg,
            padding: const EdgeInsets.all(20),
            child: body,
          ),
        );
    }
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.palette.hairline)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: const Row(
        children: <Widget>[
          SkeletonBar(width: 72, height: 12),
          Spacer(),
          SkeletonBar(width: 120, height: 12),
        ],
      ),
    );
  }
}

/// Sign out, in the page after Delete account as the design has it; also
/// under a failed load, so signing out never depends on the server.
class _SignOutButton extends ConsumerWidget {
  const _SignOutButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppText text = AppText.of(context);
    return NebulaButton.secondary(
      label: text.signOut,
      icon: Icons.logout,
      onPressed: () async {
        final bool ok = await showNebulaConfirm(
          context,
          title: text.signOutConfirmTitle,
          body: text.signOutConfirmBody,
          action: text.signOut,
          cancel: text.cancel,
          destructive: true,
        );
        if (!ok) {
          return;
        }
        // Disconnect while the session can still tell the server.
        await ref
            .read(devicesControllerProvider.notifier)
            .disconnectBeforeSignOut();
        await ref.read(authNotifierProvider.notifier).logout();
      },
    );
  }
}
