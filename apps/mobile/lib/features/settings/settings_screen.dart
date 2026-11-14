import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/dns_tunnel_resolvers.dart';
import '../../core/routing/route_paths.dart';
import '../../core/settings/advanced_settings_controller.dart';
import '../../core/settings/protection_controller.dart';
import '../../core/storage/advanced_settings_store.dart';
import '../../core/storage/protection_preference_store.dart';
import '../../core/theme/appearance_controller.dart';
import '../../core/theme/theme_mode_controller.dart';
import '../../core/updates/update_check.dart';
import '../../core/warp/warp_settings.dart';
import '../../core/widgets/nebula/nebula_data.dart';
import '../../core/widgets/nebula/nebula_page.dart';
import '../../core/widgets/nebula/nebula_rows.dart';
import '../../l10n/app_localizations.dart';
import 'appearance_screen.dart';
import 'legal_document_screen.dart';
import 'settings_sections.dart';

export 'settings_sections.dart' show androidKillSwitchProvider;

/// The Settings hub (DESIGN_SPEC §4): search at the top, then Appearance,
/// Connection (Startup, Protection, Routing), Diagnostics, Advanced and
/// About; each group opens its own screen.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

/// A setting search can find: its name, where it lives, and how to go there.
class _Entry {
  const _Entry(this.title, this.where, this.open);

  final String title;
  final String where;
  final VoidCallback open;
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppText text = AppText.of(context);
    final ThemeMode mode = ref.watch(themeModeProvider);
    final ProtectionPreferences protection = ref.watch(
      protectionControllerProvider,
    );
    final AdvancedSettings advanced = ref.watch(
      advancedSettingsControllerProvider,
    );
    final bool android = defaultTargetPlatform == TargetPlatform.android;
    final ({bool alwaysOn, bool lockdown})? killSwitch = android
        ? ref.watch(androidKillSwitchProvider).value
        : null;

    void go(String path) => context.push(path);
    final List<_Entry> entries = <_Entry>[
      _Entry(
        text.sectionAppearance,
        text.sectionAppearance,
        () => go(RoutePaths.homeAppearance),
      ),
      _Entry(
        text.language,
        text.sectionAppearance,
        () => chooseLanguage(context, ref),
      ),
      for (final String title in <String>[
        text.connectOnLaunch,
        if (android) text.reconnectAfterRestart else text.startAtLogin,
        text.notificationSpeed,
      ])
        _Entry(title, text.sectionStartup, () => go(RoutePaths.homeStartup)),
      for (final String title in <String>[
        text.killSwitch,
        text.allowLocalNetwork,
      ])
        _Entry(
          title,
          text.sectionProtection,
          () => go(RoutePaths.homeProtection),
        ),
      for (final String title in <String>[
        text.routingEverything,
        text.routingSanctionsOnly,
        text.iranDirect,
      ])
        _Entry(title, text.sectionRouting, () => go(RoutePaths.homeRouting)),
      _Entry(
        text.splitTunneling,
        text.sectionRouting,
        () => go(RoutePaths.homeSplitTunnel),
      ),
      _Entry(
        text.bypassDomains,
        text.sectionRouting,
        () => go(RoutePaths.homeBypassDomains),
      ),
      _Entry(
        text.sectionDiagnostics,
        text.sectionDiagnostics,
        () => go(RoutePaths.homeDiagnostics),
      ),
      _Entry(
        text.connectionLog,
        text.sectionDiagnostics,
        () => go(RoutePaths.homeConnectionLog),
      ),
      if (warpSupported)
        _Entry(
          text.warpTitle,
          text.sectionAdvanced,
          () => go(RoutePaths.homeWarp),
        ),
      _Entry(
        text.tunnelOptions,
        text.sectionAdvanced,
        () => go(RoutePaths.homeAdvanced),
      ),
      _Entry(
        text.cleanIp,
        text.sectionAdvanced,
        () => go(RoutePaths.homeCleanIp),
      ),
      if (dnsTunnelSupported)
        _Entry(
          text.dnsTunnelResolvers,
          text.sectionAdvanced,
          () => go(RoutePaths.homeDnsTunnelResolvers),
        ),
      _Entry(
        text.localProxyMode,
        text.sectionAdvanced,
        () => go(RoutePaths.homeAdvancedGroup),
      ),
      _Entry(
        text.openSourceLicenses,
        text.sectionAbout,
        () => _openLicenses(context),
      ),
      _Entry(
        text.privacyPolicy,
        text.sectionAbout,
        () => _openLegal(context, text.privacyPolicy, true),
      ),
      _Entry(
        text.termsOfUse,
        text.sectionAbout,
        () => _openLegal(context, text.termsOfUse, false),
      ),
    ];

    final String q = _query.trim().toLowerCase();
    final List<_Entry> matches = q.isEmpty
        ? const <_Entry>[]
        : entries
              .where(
                (_Entry e) =>
                    e.title.toLowerCase().contains(q) ||
                    e.where.toLowerCase().contains(q),
              )
              .toList();

    return NebulaPage(
      title: text.settingsTitle,
      children: <Widget>[
        const SizedBox(height: 16),
        NebulaField(
          label: text.searchSettings,
          controller: _search,
          prefixIcon: Icons.search,
          autocorrect: false,
          textInputAction: TextInputAction.search,
          onChanged: (String value) => setState(() => _query = value),
        ),
        if (q.isNotEmpty) ...<Widget>[
          NebulaSectionLabel(text.settingsResults),
          if (matches.isEmpty)
            NebulaEmptyState(
              icon: Icons.search_off,
              title: text.noSettingsMatch(_query.trim()),
            )
          else
            NebulaRowGroup(
              children: <Widget>[
                for (final _Entry e in matches)
                  NebulaRow(
                    title: e.title,
                    subtitle: e.where,
                    trailing: NebulaRowTrailing.chevron(context),
                    onTap: e.open,
                  ),
              ],
            ),
        ] else ...<Widget>[
          NebulaSectionLabel(text.sectionAppearance),
          NebulaRowGroup(
            children: <Widget>[
              NebulaRow(
                icon: Icons.palette_outlined,
                title: text.sectionAppearance,
                subtitle:
                    '${lookName(text, ref.watch(appearanceProvider).look)} · '
                    '${switch (mode) {
                      ThemeMode.light => text.themeLight,
                      ThemeMode.dark => text.themeDark,
                      ThemeMode.system => text.themeSystem,
                    }}',
                trailing: NebulaRowTrailing.chevron(context),
                onTap: () => go(RoutePaths.homeAppearance),
              ),
              const LanguageRow(),
            ],
          ),
          NebulaSectionLabel(text.sectionConnection),
          NebulaRowGroup(
            children: <Widget>[
              NebulaRow(
                icon: Icons.power_settings_new,
                title: text.sectionStartup,
                subtitle: protection.connectOnLaunch
                    ? text.connectOnLaunch
                    : text.off,
                trailing: NebulaRowTrailing.chevron(context),
                onTap: () => go(RoutePaths.homeStartup),
              ),
              NebulaRow(
                icon: Icons.shield_outlined,
                title: text.sectionProtection,
                subtitle: android
                    ? '${text.killSwitch}: '
                          '${androidKillSwitchMeta(text, killSwitch)}'
                    : '${text.killSwitch}: '
                          '${protection.blockWhenVpnDrops ? text.on : text.off}',
                // Amber until the kill switch really blocks.
                tone: android
                    ? (killSwitch?.lockdown == true
                          ? NebulaTone.normal
                          : NebulaTone.warn)
                    : (protection.blockWhenVpnDrops
                          ? NebulaTone.normal
                          : NebulaTone.warn),
                trailing: NebulaRowTrailing.chevron(context),
                onTap: () => go(RoutePaths.homeProtection),
              ),
              NebulaRow(
                icon: Icons.alt_route,
                title: text.sectionRouting,
                subtitle: advanced.routingMode == RoutingMode.sanctionedOnly
                    ? text.routingSanctionsOnly
                    : text.routingEverything,
                trailing: NebulaRowTrailing.chevron(context),
                onTap: () => go(RoutePaths.homeRouting),
              ),
            ],
          ),
          NebulaSectionLabel(text.sectionDiagnostics),
          NebulaRowGroup(
            children: <Widget>[
              NebulaRow(
                icon: Icons.monitor_heart_outlined,
                title: text.sectionDiagnostics,
                subtitle: text.diagnosticsMeta,
                trailing: NebulaRowTrailing.chevron(context),
                onTap: () => go(RoutePaths.homeDiagnostics),
              ),
              NebulaRow(
                icon: Icons.receipt_long_outlined,
                title: text.connectionLog,
                subtitle: text.connectionLogMeta,
                trailing: NebulaRowTrailing.chevron(context),
                onTap: () => go(RoutePaths.homeConnectionLog),
              ),
            ],
          ),
          NebulaSectionLabel(text.sectionAdvanced),
          NebulaRowGroup(
            children: <Widget>[
              NebulaRow(
                icon: Icons.tune,
                title: text.sectionAdvanced,
                subtitle: advanced.isDefault
                    ? text.tunnelOptionsDefault
                    : text.tunnelOptionsCustomised,
                trailing: NebulaRowTrailing.chevron(context),
                onTap: () => go(RoutePaths.homeAdvancedGroup),
              ),
            ],
          ),
          NebulaSectionLabel(text.sectionAbout),
          NebulaRowGroup(
            children: <Widget>[
              NebulaSwitchRow(
                icon: Icons.system_update_outlined,
                title: text.checkForUpdates,
                subtitle: text.checkForUpdatesMeta,
                value: ref.watch(updateChecksProvider),
                onChanged: (bool on) => ref
                    .read(updateChecksProvider.notifier)
                    .setEnabled(enabled: on),
              ),
              NebulaRow(
                icon: Icons.gavel_outlined,
                title: text.openSourceLicenses,
                subtitle: text.openSourceLicensesMeta,
                trailing: NebulaRowTrailing.chevron(context),
                onTap: () => _openLicenses(context),
              ),
              NebulaRow(
                icon: Icons.privacy_tip_outlined,
                title: text.privacyPolicy,
                subtitle: text.privacyPolicyMeta,
                trailing: NebulaRowTrailing.chevron(context),
                onTap: () => _openLegal(context, text.privacyPolicy, true),
              ),
              NebulaRow(
                icon: Icons.description_outlined,
                title: text.termsOfUse,
                subtitle: text.termsOfUseMeta,
                trailing: NebulaRowTrailing.chevron(context),
                onTap: () => _openLegal(context, text.termsOfUse, false),
              ),
              const VersionRow(),
            ],
          ),
        ],
      ],
    );
  }

  static void _openLicenses(BuildContext context) => showLicensePage(
    context: context,
    applicationName: 'Nebula VPN',
    applicationLegalese: 'GPL-3.0-or-later',
  );

  static void _openLegal(BuildContext context, String title, bool privacy) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => LegalDocumentScreen(
            title: title,
            asset: privacy
                ? LegalDocumentScreen.privacyAsset
                : LegalDocumentScreen.termsAsset,
          ),
        ),
      );
}
