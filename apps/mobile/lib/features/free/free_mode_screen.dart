import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/free/free_mode.dart';
import '../../core/free/subscriptions.dart';
import '../../core/routing/route_paths.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/warp/warp_settings.dart';
import '../../core/widgets/nebula/nebula_controls.dart';
import '../../core/widgets/nebula/nebula_data.dart';
import '../../core/widgets/nebula/nebula_feedback.dart';
import '../../core/widgets/nebula/nebula_page.dart';
import '../../core/widgets/nebula/nebula_rows.dart';
import '../../l10n/app_localizations.dart';
import '../devices/devices_controller.dart';

/// The third tab with no server: the relays this app connects through, where
/// one's own is added, and the way back to a server.
class FreeModeScreen extends ConsumerStatefulWidget {
  const FreeModeScreen({super.key, this.ownLinks = false});

  /// Signed in to a server: the same links and subscriptions, kept beside
  /// that server's list, without what only free mode has -- its shared
  /// relays, its introduction, and the way back to the door.
  final bool ownLinks;

  @override
  ConsumerState<FreeModeScreen> createState() => _FreeModeScreenState();
}

class _FreeModeScreenState extends ConsumerState<FreeModeScreen> {
  final TextEditingController _field = TextEditingController();
  final TextEditingController _subscriptionField = TextEditingController();
  bool _invalid = false;
  bool _subscriptionInvalid = false;
  bool _refreshing = false;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // What is due, not everything: opening this screen often must not mean
    // asking every list's host each time. Quietly -- no spinner for a check
    // nobody asked for. Again whenever the app comes back to the front: the
    // screen stays built for days, and a list fetched once at build time was
    // never refreshed again, though the screen says "a few times a day".
    unawaited(_refreshDue());
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(_refreshDue()));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _field.dispose();
    _subscriptionField.dispose();
    super.dispose();
  }

  Future<void> _refreshDue() async {
    try {
      await ref.read(subscriptionsProvider.notifier).refresh();
      if (mounted) {
        await _reload();
      }
    } catch (_) {
      // A list that could not be refreshed keeps its last good copy.
    }
  }

  Future<void> _refreshSubscriptions({required bool force}) async {
    setState(() => _refreshing = true);
    try {
      await ref.read(subscriptionsProvider.notifier).refresh(force: force);
      await _reload();
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<void> _addSubscription() async {
    setState(() => _refreshing = true);
    try {
      final bool taken = await ref
          .read(subscriptionsProvider.notifier)
          .add(_subscriptionField.text);
      if (!mounted) {
        return;
      }
      setState(() => _subscriptionInvalid = !taken);
      if (taken) {
        _subscriptionField.clear();
        await _reload();
      }
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  /// Its name in Servers. Empty goes back to the address's host.
  Future<void> _renameSubscription(Subscription subscription) async {
    final AppText text = AppText.of(context);
    final TextEditingController field = TextEditingController(
      text: subscription.label ?? '',
    );
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => NebulaDialog(
        title: text.subscriptionRename,
        content: NebulaField(
          label: text.subscriptionRename,
          labelVisible: false,
          controller: field,
          autofocus: true,
          hint: Uri.tryParse(subscription.url)?.host,
          inputFormatters: <TextInputFormatter>[
            LengthLimitingTextInputFormatter(40),
          ],
          onSubmitted: (String value) => Navigator.of(context).pop(value),
        ),
        actions: <Widget>[
          NebulaButton.secondary(
            label: text.cancel,
            onPressed: () => Navigator.of(context).pop(),
          ),
          NebulaButton(
            label: text.save,
            onPressed: () => Navigator.of(context).pop(field.text),
          ),
        ],
      ),
    );
    field.dispose();
    if (name == null) {
      return;
    }
    await ref
        .read(subscriptionsProvider.notifier)
        .rename(subscription.url, name);
    await _reload();
  }

  Future<void> _removeSubscription(Subscription subscription) async {
    await ref.read(subscriptionsProvider.notifier).remove(subscription.url);
    await _reload();
  }

  String _subscriptionStatus(AppText text, Subscription s) {
    final String? failure = switch (s.failure) {
      null => null,
      SubscriptionError.unreachable => text.freeSubscriptionUnreachable,
      SubscriptionError.refused => text.freeSubscriptionRefused,
      SubscriptionError.tooLarge => text.freeSubscriptionTooLarge,
      SubscriptionError.empty => text.freeSubscriptionEmpty,
    };
    final MaterialLocalizations local = MaterialLocalizations.of(context);
    final DateTime? at = s.checkedAt?.toLocal();
    final List<String> parts = <String>[
      if (s.links.isNotEmpty || failure == null)
        text.freeSubscriptionCount(s.links.length),
      if (at != null)
        text.freeSubscriptionUpdated(
          '${local.formatShortDate(at)} '
          '${local.formatTimeOfDay(TimeOfDay.fromDateTime(at))}',
        ),
      ?failure,
      if (s.skipped.isNotEmpty)
        text.freeSubscriptionSkipped(
          s.skipped.values.fold<int>(0, (int sum, int n) => sum + n),
        ),
    ];
    return s.checkedAt == null && failure == null
        ? text.freeSubscriptionNotYet
        : parts.join(' · ');
  }

  /// The connect screen's list is the controller's; it is read again so a
  /// relay added here is there to choose.
  Future<void> _reload() => ref.read(devicesControllerProvider.notifier).load();

  Future<void> _add() async {
    final bool taken = await ref
        .read(freeProfilesProvider.notifier)
        .add(_field.text);
    if (!mounted) {
      return;
    }
    setState(() => _invalid = !taken);
    if (taken) {
      _field.clear();
      await _reload();
    }
  }

  Future<void> _remove(FreeProfile profile) async {
    await ref.read(freeProfilesProvider.notifier).remove(profile.link);
    await _reload();
  }

  Future<void> _leave() async {
    await ref
        .read(devicesControllerProvider.notifier)
        .disconnectBeforeSignOut();
    await ref.read(freeModeProvider.notifier).leave();
  }

  @override
  Widget build(BuildContext context) {
    final NebulaPalette palette = context.palette;
    final AppText text = AppText.of(context);
    // A subscription's connections are summed up in its own row below; the
    // list here is the person's own.
    final List<FreeProfile> profiles =
        (ref.watch(freeProfilesProvider).value ?? const <FreeProfile>[])
            .where((FreeProfile p) => p.sources.isEmpty)
            .toList();
    final List<Subscription> subscriptions =
        ref.watch(subscriptionsProvider).value ?? const <Subscription>[];

    TextStyle intro() =>
        TextStyle(fontSize: 14, height: 20 / 14, color: palette.textMuted);

    return NebulaPage(
      title: widget.ownLinks ? text.ownLinksTitle : text.freeTab,
      showBack: widget.ownLinks,
      footer: widget.ownLinks
          ? null
          : NebulaButton.secondary(label: text.freeLeave, onPressed: _leave),
      children: <Widget>[
        const SizedBox(height: 8),
        Text(
          widget.ownLinks ? text.ownLinksIntro : text.freeIntro,
          style: intro(),
        ),
        if (!widget.ownLinks && warpSupported) ...<Widget>[
          NebulaSectionLabel(text.freeBuiltIn),
          NebulaRowGroup(
            children: <Widget>[
              NebulaRow(
                icon: Icons.cloud_outlined,
                title: text.warpTitle,
                subtitle: text.warpRowMeta,
                trailing: NebulaRowTrailing.chevron(context),
                onTap: () => context.push(RoutePaths.homeWarp),
              ),
            ],
          ),
        ],
        NebulaSectionLabel(text.ownLinksTitle),
        if (!widget.ownLinks && profiles.isEmpty && subscriptions.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              text.freeNoRelays,
              style: intro().copyWith(color: palette.amberText),
            ),
          ),
        if (profiles.isNotEmpty) ...<Widget>[
          NebulaRowGroup(
            children: <Widget>[
              for (final FreeProfile profile in profiles)
                NebulaRow(
                  title: profile.name,
                  subtitle: text.freeRelayYours,
                  trailing: _IconAction(
                    icon: Icons.close,
                    tooltip: text.freeRemove,
                    onPressed: () => _remove(profile),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        Text(text.freeAddIntro, style: intro()),
        const SizedBox(height: 12),
        NebulaField(
          label: text.freeLinkLabel,
          controller: _field,
          hint: 'vless:// trojan:// ss:// hysteria2://',
          keyboardType: TextInputType.url,
          autocorrect: false,
          mono: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _add(),
          errorText: _invalid ? text.freeAddInvalid : null,
          addLabel: text.freeAdd,
          onAdd: _add,
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(child: NebulaSectionLabel(text.freeSubscriptions)),
            if (subscriptions.isNotEmpty)
              NebulaButton.text(
                label: text.freeSubscriptionsRefresh,
                busy: _refreshing,
                onPressed: () => _refreshSubscriptions(force: true),
              ),
          ],
        ),
        Text(text.freeSubscriptionsIntro, style: intro()),
        const SizedBox(height: 12),
        if (subscriptions.isNotEmpty) ...<Widget>[
          NebulaRowGroup(
            children: <Widget>[
              for (final Subscription subscription in subscriptions)
                NebulaRow(
                  title: subscription.name,
                  subtitle: _subscriptionStatus(text, subscription),
                  subtitleColor: subscription.failure == null
                      ? null
                      : palette.amberText,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _IconAction(
                        icon: Icons.edit_outlined,
                        tooltip: text.subscriptionRename,
                        onPressed: () => _renameSubscription(subscription),
                      ),
                      _IconAction(
                        icon: Icons.close,
                        tooltip: text.freeRemove,
                        onPressed: () => _removeSubscription(subscription),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        NebulaField(
          label: text.freeSubscriptionAddress,
          controller: _subscriptionField,
          hint: 'https://',
          keyboardType: TextInputType.url,
          autocorrect: false,
          mono: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _addSubscription(),
          errorText: _subscriptionInvalid ? text.freeSubscriptionInvalid : null,
          addLabel: text.freeAdd,
          onAdd: _refreshing ? null : _addSubscription,
        ),
        if (!widget.ownLinks) ...<Widget>[
          const SizedBox(height: 24),
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
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

/// A 44 px icon button in a row, named for screen readers.
class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    icon: Icon(icon, size: 20, color: context.palette.textMuted),
    onPressed: onPressed,
  );
}
