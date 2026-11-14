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
import '../../core/format/dates.dart';
import '../../core/routing/route_paths.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/type_scale.dart';
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
      title: text.accountHeading,
      showBack: false,
      // Settings is not a tab -- this gear is the way in.
      trailing: IconButton(
        tooltip: text.rowSettings,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        icon: Icon(Icons.settings_outlined, color: context.palette.textMuted),
        onPressed: () => context.push(RoutePaths.homeSettings),
      ),
      footer: NebulaButton.secondary(
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
        const SizedBox(height: 16),
        _Profile(name: account.username, email: account.email),
        const SizedBox(height: 16),
        NebulaPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: healthy ? palette.ok : palette.amber,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_stateLabel(text, account.state)} · $until',
                      style: TextStyle(
                        fontSize: 13,
                        color: healthy ? palette.textMuted : palette.amberText,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _UsageBlock(account: account),
              const SizedBox(height: 16),
              Divider(height: 1, color: palette.hairline),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      text.tabDevices,
                      style: TextStyle(fontSize: 14, color: palette.textMuted),
                    ),
                  ),
                  Text(
                    text.devicesInUseOfLimit(
                      account.devicesInUse,
                      account.deviceLimit,
                    ),
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: palette.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
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
        NebulaSectionLabel(text.sectionDetails),
        NebulaRowGroup(
          children: <Widget>[
            NebulaRow(
              title: text.rowEmail,
              trailing: NebulaRowTrailing.value(
                context,
                account.email,
                mono: false,
              ),
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
          NebulaNotice(text: text.accessExpired, kind: NebulaNoticeKind.warning),
        ],
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
/// as the title, when there is no username).
class _Profile extends StatelessWidget {
  const _Profile({required this.name, required this.email});

  final String? name;
  final String email;

  @override
  Widget build(BuildContext context) {
    final NebulaPalette p = context.palette;
    final String title = name ?? email;
    return Row(
      children: <Widget>[
        ExcludeSemantics(
          child: Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: nebulaTint(p, p.blue, 18),
              shape: BoxShape.circle,
            ),
            child: Text(
              title.isEmpty ? '?' : title.characters.first.toUpperCase(),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: p.blueText,
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
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: p.textPrimary,
                ),
              ),
              if (name != null)
                Text(email, style: TextStyle(fontSize: 13, color: p.textMuted)),
            ],
          ),
        ),
      ],
    );
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

/// What this account has used, and what is left of its allowance.
///
/// Two shapes, because an unmetered account has no "left" to show. Rendering
/// a bar for it -- full or empty -- would state something untrue about a limit
/// that does not exist, so the metered case gets the figure and the bar and
/// the unmetered case gets the total on its own.
///
/// The total is everything the account has ever used, on every device. The
/// allowance figures are measured from where the allowance began, so a metered
/// account whose total is more than that says so on a line of its own.
class _UsageBlock extends StatelessWidget {
  const _UsageBlock({required this.account});

  final AccountSummary account;

  @override
  Widget build(BuildContext context) {
    final AppText text = AppText.of(context);
    final NebulaPalette palette = context.palette;
    final NebulaTypography type = context.type;

    if (!account.isMetered) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            formatBytes(account.lifetimeBytes),
            textDirection: TextDirection.ltr,
            style: type.quotaFigure.copyWith(color: palette.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            text.usedNoLimit,
            style: type.topBarMeta.copyWith(color: palette.textMuted),
          ),
        ],
      );
    }

    final int remaining = account.remainingBytes ?? 0;
    final double fraction = account.usedFraction ?? 0;
    // Amber once the allowance is gone. Nothing else on this screen changes:
    // running out of traffic is not an error, it is a state worth noticing.
    final bool exhausted = remaining == 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          formatBytes(remaining),
          // Drawn "KB 8.9" on the phone under Persian without this.
          textDirection: TextDirection.ltr,
          style: type.quotaFigure.copyWith(
            color: exhausted ? palette.amberText : palette.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          exhausted ? text.quotaNothingLeft : text.quotaLeft,
          style: type.topBarMeta.copyWith(
            color: exhausted ? palette.amberText : palette.textMuted,
          ),
        ),
        const SizedBox(height: 14),
        NebulaUsageMeter(
          fraction: fraction,
          color: exhausted ? palette.amber : palette.blue,
        ),
        const SizedBox(height: 10),
        Text(
          text.quotaUsed(
            embedLeftToRight(
              context,
              formatBytePair(account.usedBytes, account.quotaBytes!),
            ),
          ),
          style: type.listMeta.copyWith(color: palette.textMuted),
        ),
        // Only when it says something the line above does not: until an
        // allowance is granted on top of earlier use, the two are the same.
        if (account.lifetimeBytes > account.usedBytes) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            text.usedInTotal(
              embedLeftToRight(context, formatBytes(account.lifetimeBytes)),
            ),
            style: type.listMeta.copyWith(color: palette.textMuted),
          ),
        ],
      ],
    );
  }
}
