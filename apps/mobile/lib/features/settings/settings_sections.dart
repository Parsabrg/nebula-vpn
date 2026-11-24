import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/app_info.dart';
import '../../core/network/dns_tunnel_resolvers.dart';
import '../../core/routing/route_paths.dart';
import '../../core/settings/advanced_settings_controller.dart';
import '../../core/settings/locale_controller.dart';
import '../../core/settings/protection_controller.dart';
import '../../core/split_tunnel/split_tunnel_controller.dart';
import '../../core/storage/advanced_settings_store.dart';
import '../../core/storage/protection_preference_store.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/warp/warp_settings.dart';
import '../../core/widgets/nebula/nebula_controls.dart';
import '../../core/widgets/nebula/nebula_data.dart';
import '../../core/widgets/nebula/nebula_feedback.dart';
import '../../core/widgets/nebula/nebula_page.dart';
import '../../core/widgets/nebula/nebula_rows.dart';
import '../../core/window/login_item.dart';
import '../../core/wireguard/native_tunnel_channel.dart';
import '../../l10n/app_localizations.dart';

bool get _android => defaultTargetPlatform == TargetPlatform.android;

/// Settings, Startup: connect on launch; on Android reconnecting after a
/// restart, on Windows and Linux starting at sign-in (the system holds that
/// setting); speed in the notification.
class StartupSettingsScreen extends ConsumerWidget {
  const StartupSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppText text = AppText.of(context);
    final ProtectionPreferences protection = ref.watch(
      protectionControllerProvider,
    );
    final ProtectionController controller = ref.read(
      protectionControllerProvider.notifier,
    );
    return NebulaPage(
      title: text.sectionStartup,
      children: <Widget>[
        const SizedBox(height: 16),
        NebulaRowGroup(
          children: <Widget>[
            NebulaSwitchRow(
              title: text.connectOnLaunch,
              subtitle: text.connectOnLaunchMeta,
              value: protection.connectOnLaunch,
              onChanged: (bool on) =>
                  controller.setConnectOnLaunch(enabled: on),
            ),
            if (_android)
              NebulaSwitchRow(
                title: text.reconnectAfterRestart,
                subtitle: text.reconnectAfterRestartMeta,
                value: protection.reconnectAfterRestart,
                onChanged: (bool on) =>
                    controller.setReconnectAfterRestart(enabled: on),
              )
            else
              NebulaSwitchRow(
                title: text.startAtLogin,
                subtitle: text.startAtLoginMeta,
                value: ref.watch(loginItemEnabledProvider).value ?? false,
                onChanged: (bool on) async {
                  await ref.read(loginItemProvider).set(enabled: on);
                  ref.invalidate(loginItemEnabledProvider);
                },
              ),
            NebulaSwitchRow(
              title: text.notificationSpeed,
              subtitle: text.notificationSpeedMeta,
              value: protection.notificationSpeed,
              onChanged: (bool on) =>
                  controller.setNotificationSpeed(enabled: on),
            ),
          ],
        ),
      ],
    );
  }
}

/// Settings, Protection: the kill switch (Android's own, explained and
/// opened; on the desktop the app's), then Allow local network.
class ProtectionSettingsScreen extends ConsumerWidget {
  const ProtectionSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppText text = AppText.of(context);
    final ProtectionPreferences protection = ref.watch(
      protectionControllerProvider,
    );
    final ProtectionController controller = ref.read(
      protectionControllerProvider.notifier,
    );
    return NebulaPage(
      title: text.sectionProtection,
      children: <Widget>[
        const SizedBox(height: 16),
        NebulaRowGroup(
          children: <Widget>[
            if (_android)
              AndroidKillSwitchRow(onTap: () => openKillSwitch(context))
            else
              // Windows and Linux: the app's own, through the elevated
              // helper. Takes effect from the next connection.
              NebulaSwitchRow(
                title: text.killSwitch,
                subtitle: text.killSwitchDesktopMeta,
                value: protection.blockWhenVpnDrops,
                onChanged: (bool on) =>
                    controller.setBlockWhenVpnDrops(enabled: on),
              ),
            NebulaSwitchRow(
              title: text.allowLocalNetwork,
              subtitle: text.allowLocalNetworkMeta,
              value: protection.bypassLocalNetwork,
              onChanged: (bool on) =>
                  controller.setBypassLocalNetwork(enabled: on),
            ),
          ],
        ),
        // Where the kill switch is not used, said here rather than left to
        // be found out. Windows only: on Linux the kill
        // switch stays on over WARP, Aether's traffic being marked.
        if (defaultTargetPlatform == TargetPlatform.windows &&
            protection.blockWhenVpnDrops) ...<Widget>[
          const SizedBox(height: 12),
          NebulaNotice(
            text: text.killSwitchWarpLimit,
            kind: NebulaNoticeKind.info,
          ),
        ],
      ],
    );
  }
}

/// Settings, Routing: what goes through the VPN (everything, or sanctioned
/// services only -- one choice where two switches overlapped), then the
/// exceptions.
class RoutingSettingsScreen extends ConsumerWidget {
  const RoutingSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppText text = AppText.of(context);
    final NebulaPalette p = context.palette;
    final AdvancedSettings advanced = ref.watch(
      advancedSettingsControllerProvider,
    );
    final AdvancedSettingsController controller = ref.read(
      advancedSettingsControllerProvider.notifier,
    );
    Widget choice(RoutingMode mode, String title, String? subtitle) =>
        NebulaRow(
          title: title,
          subtitle: subtitle,
          selected: advanced.routingMode == mode,
          onTap: () => controller.setRoutingMode(mode),
          trailing: Radio<RoutingMode>(value: mode, activeColor: p.blue),
        );
    return NebulaPage(
      title: text.sectionRouting,
      children: <Widget>[
        NebulaSectionLabel(text.routingWhatGoesThrough),
        RadioGroup<RoutingMode>(
          groupValue: advanced.routingMode,
          onChanged: (RoutingMode? mode) {
            if (mode != null) {
              controller.setRoutingMode(mode);
            }
          },
          child: NebulaRowGroup(
            children: <Widget>[
              choice(RoutingMode.everything, text.routingEverything, null),
              choice(
                RoutingMode.sanctionedOnly,
                text.routingSanctionsOnly,
                text.routingSanctionsOnlyMeta,
              ),
            ],
          ),
        ),
        NebulaSectionLabel(text.routingExceptions),
        NebulaRowGroup(
          children: <Widget>[
            NebulaSwitchRow(
              title: text.iranDirect,
              subtitle: text.iranDirectMeta,
              value: advanced.iranDirect,
              onChanged: (bool on) => controller.setIranDirect(enabled: on),
            ),
            NebulaSwitchRow(
              title: text.blockAds,
              subtitle: text.blockAdsMeta,
              value: advanced.blockAds,
              onChanged: (bool on) => controller.setBlockAds(enabled: on),
            ),
            NebulaRow(
              title: text.splitTunneling,
              subtitle: splitTunnelMeta(
                text,
                ref.watch(splitTunnelControllerProvider),
              ),
              trailing: NebulaRowTrailing.chevron(context),
              onTap: () => context.push(RoutePaths.homeSplitTunnel),
            ),
            NebulaRow(
              title: text.bypassDomains,
              subtitle: bypassDomainsMeta(text, advanced.bypassDomains),
              trailing: NebulaRowTrailing.chevron(context),
              onTap: () => context.push(RoutePaths.homeBypassDomains),
            ),
          ],
        ),
      ],
    );
  }
}

/// Settings, Advanced: Cloudflare WARP, tunnel options, Cloudflare address,
/// DNS tunnel resolvers, and the local proxy with its port.
class AdvancedGroupScreen extends ConsumerWidget {
  const AdvancedGroupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppText text = AppText.of(context);
    final AdvancedSettings advanced = ref.watch(
      advancedSettingsControllerProvider,
    );
    final bool proxy = advanced.connectionMode == ConnectionMode.localProxy;
    return NebulaPage(
      title: text.sectionAdvanced,
      children: <Widget>[
        const SizedBox(height: 16),
        NebulaRowGroup(
          children: <Widget>[
            if (warpSupported)
              NebulaRow(
                icon: Icons.cloud_outlined,
                title: text.warpTitle,
                subtitle: switch (advanced.warp) {
                  WarpSettings(throughWarp: true) => text.warpThroughOn,
                  WarpSettings(leaveOutsideIran: true) =>
                    text.warpOutsideIranOn,
                  _ => text.warpRowMeta,
                },
                trailing: NebulaRowTrailing.chevron(context),
                onTap: () => context.push(RoutePaths.homeWarp),
              ),
            NebulaRow(
              icon: Icons.tune,
              title: text.tunnelOptions,
              subtitle: advanced.isDefault
                  ? text.tunnelOptionsDefault
                  : text.tunnelOptionsCustomised,
              trailing: NebulaRowTrailing.chevron(context),
              onTap: () => context.push(RoutePaths.homeAdvanced),
            ),
            NebulaRow(
              icon: Icons.speed,
              title: text.cleanIp,
              subtitle: advanced.cleanIp ?? text.cleanIpAutomatic,
              trailing: NebulaRowTrailing.chevron(context),
              onTap: () => context.push(RoutePaths.homeCleanIp),
            ),
            if (dnsTunnelSupported)
              ListenableBuilder(
                listenable: ref.watch(dnsTunnelResolversProvider),
                builder: (BuildContext context, _) {
                  final DnsTunnelResolvers resolvers = ref.read(
                    dnsTunnelResolversProvider,
                  );
                  final String? network = resolvers.network;
                  return NebulaRow(
                    icon: Icons.dns_outlined,
                    title: text.dnsTunnelResolvers,
                    subtitle: text.dnsTunnelResolversSetMeta(
                      resolvers.active ?? text.dnsTunnelResolversBuiltIn,
                      network == null ? 0 : resolvers.workingOn(network).length,
                    ),
                    trailing: NebulaRowTrailing.chevron(context),
                    onTap: () =>
                        context.push(RoutePaths.homeDnsTunnelResolvers),
                  );
                },
              ),
          ],
        ),
        NebulaSectionLabel(text.localProxyMode),
        NebulaRowGroup(
          children: <Widget>[
            NebulaSwitchRow(
              title: text.localProxyMode,
              subtitle: text.localProxyModeMeta,
              value: proxy,
              onChanged: (bool on) => ref
                  .read(advancedSettingsControllerProvider.notifier)
                  .setConnectionMode(
                    on ? ConnectionMode.localProxy : ConnectionMode.vpn,
                  ),
            ),
            if (proxy) const LocalProxyPortRow(),
          ],
        ),
      ],
    );
  }
}

/// Android's always-on and block-without-VPN switches for this app, read
/// from Android each time the row is built or the app comes back to the
/// front (from Android's VPN settings, typically).
final androidKillSwitchProvider =
    FutureProvider.autoDispose<({bool alwaysOn, bool lockdown})?>(
      (Ref ref) => const NativeTunnelChannel().killSwitch(),
    );

/// What Android has switched on, never assumed: it used to say "off" while
/// both switches were on.
String androidKillSwitchMeta(
  AppText text,
  ({bool alwaysOn, bool lockdown})? state,
) => switch (state) {
  (alwaysOn: true, lockdown: true) => text.killSwitchMetaOn,
  (alwaysOn: true, lockdown: false) => text.killSwitchMetaAlwaysOn,
  (alwaysOn: false, lockdown: _) => text.killSwitchMeta,
  null => text.killSwitchMetaUnknown,
};

/// The Android kill switch: a row that explains and opens Android's own
/// screen, in amber until Android blocks traffic without the VPN -- the one
/// protection the app cannot switch on itself.
class AndroidKillSwitchRow extends ConsumerStatefulWidget {
  const AndroidKillSwitchRow({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  ConsumerState<AndroidKillSwitchRow> createState() =>
      _AndroidKillSwitchRowState();
}

class _AndroidKillSwitchRowState extends ConsumerState<AndroidKillSwitchRow> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(androidKillSwitchProvider),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppText text = AppText.of(context);
    final ({bool alwaysOn, bool lockdown})? state = ref
        .watch(androidKillSwitchProvider)
        .value;
    return NebulaRow(
      title: text.killSwitch,
      subtitle: androidKillSwitchMeta(text, state),
      tone: state?.lockdown == true ? NebulaTone.normal : NebulaTone.warn,
      trailing: NebulaRowTrailing.external(context),
      onTap: widget.onTap,
    );
  }
}

/// Explains first, then opens Android's own screen: Android's always-on and
/// block-without-VPN switches are the only real kill switch, and no app can
/// turn them on for itself.
Future<void> openKillSwitch(BuildContext context) async {
  final AppText text = AppText.of(context);
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final bool? proceed = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => NebulaDialog(
      title: text.killSwitch,
      body: text.killSwitchBody,
      actions: <Widget>[
        NebulaButton.secondary(
          label: text.killSwitchNotNow,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        NebulaButton(
          label: text.killSwitchOpen,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  if (proceed != true) {
    return;
  }
  final bool opened = await const NativeTunnelChannel().openVpnSettings();
  if (!opened) {
    messenger.showSnackBar(
      SnackBar(content: Text(text.killSwitchCouldNotOpen)),
    );
  }
}

/// `off` rather than a blank when nothing is excluded: an empty line reads
/// as "not implemented yet", and this setting has a real state.
String bypassDomainsMeta(AppText text, List<String> domains) => domains.isEmpty
    ? text.bypassDomainsNone
    : text.bypassDomainsCount(domains.length);

String splitTunnelMeta(AppText text, Set<String> excluded) => excluded.isEmpty
    ? text.splitTunnelingOff
    // Pluralised by the localisation: the rule differs between languages.
    : text.splitTunnelingCount(excluded.length);

/// Choosing the language. Each is named in its own words -- English, فارسی
/// -- so somebody in a language they cannot read can still find the way out.
class LanguageRow extends ConsumerWidget {
  const LanguageRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppText text = AppText.of(context);
    final AppLanguage? chosen = ref.watch(localeControllerProvider);
    return NebulaRow(
      icon: Icons.translate,
      title: text.language,
      subtitle: chosen?.endonym ?? text.languageFollowsDevice,
      trailing: NebulaRowTrailing.chevron(context),
      onTap: () => chooseLanguage(context, ref),
    );
  }
}

/// The language dialog: the device's language, then each one.
Future<void> chooseLanguage(BuildContext context, WidgetRef ref) async {
  final AppText text = AppText.of(context);
  final AppLanguage? chosen = ref.read(localeControllerProvider);
  // Names, not null: "follow the device" must differ from dismissing the
  // dialog, which used to reset the language quietly.
  const String device = '';
  final String? picked = await showNebulaChoice<String>(
    context,
    title: text.language,
    selected: chosen?.name ?? device,
    options: <(String, String)>[
      (device, text.languageSystem),
      for (final AppLanguage language in AppLanguage.values)
        (language.name, language.endonym),
    ],
  );
  if (picked == null || !context.mounted) {
    return;
  }
  await ref
      .read(localeControllerProvider.notifier)
      .choose(
        picked == device
            ? null
            : AppLanguage.values.firstWhere(
                (AppLanguage l) => l.name == picked,
              ),
      );
}

/// The local proxy's port, chosen by hand: apps are set up with this number.
/// Checked before it is kept: a port no app can use would only show up later
/// as a proxy that never starts.
class LocalProxyPortRow extends ConsumerWidget {
  const LocalProxyPortRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int port = ref
        .watch(advancedSettingsControllerProvider)
        .localProxyPort;
    return NebulaRow(
      title: AppText.of(context).localProxyPort,
      trailing: NebulaRowTrailing.value(context, '127.0.0.1:$port'),
      onTap: () => _edit(context, ref, port),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, int current) async {
    final TextEditingController field = TextEditingController(text: '$current');
    String? error;
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        final AppText text = AppText.of(context);
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            Future<void> save() async {
              final int? port = int.tryParse(field.text.trim());
              final bool taken =
                  port != null &&
                  await ref
                      .read(advancedSettingsControllerProvider.notifier)
                      .setLocalProxyPort(port);
              if (!context.mounted) {
                return;
              }
              if (taken) {
                Navigator.of(context).pop();
              } else {
                setState(() => error = text.localProxyPortInvalid);
              }
            }

            return NebulaDialog(
              title: text.localProxyPort,
              body: text.localProxyPortHelp,
              content: NebulaField(
                label: text.localProxyPort,
                labelVisible: false,
                controller: field,
                mono: true,
                keyboardType: TextInputType.number,
                errorText: error,
                onSubmitted: (_) => save(),
              ),
              actions: <Widget>[
                NebulaButton.secondary(
                  label: text.cancel,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                NebulaButton(label: text.save, onPressed: save),
              ],
            );
          },
        );
      },
    );
    field.dispose();
  }
}

/// The app's version, read from the build: a written-down one is wrong
/// within a release.
class VersionRow extends StatelessWidget {
  const VersionRow({super.key});

  @override
  Widget build(BuildContext context) => NebulaRow(
    icon: Icons.info_outline,
    title: AppText.of(context).version,
    trailing: NebulaRowTrailing.value(context, kClientVersion),
  );
}
