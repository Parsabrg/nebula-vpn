import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/advanced_settings_controller.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/warp/warp_settings.dart';
import '../../core/widgets/panel/panel_atoms.dart';
import '../../core/widgets/panel/panel_controls.dart';
import '../../l10n/app_localizations.dart';

/// Everything Cloudflare WARP (Aether) can be told, in the words of what it
/// changes. The defaults are what worked on the owner's line: MASQUE over
/// HTTP/2 with Chrome's handshake.
class WarpSettingsScreen extends ConsumerWidget {
  const WarpSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final NebulaPalette palette = context.palette;
    final AppText text = AppText.of(context);
    final WarpSettings warp = ref
        .watch(advancedSettingsControllerProvider)
        .warp;
    final AdvancedSettingsController controller = ref.read(
      advancedSettingsControllerProvider.notifier,
    );
    void save(WarpSettings next) => controller.setWarp(next);

    Widget explain(String line) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        line,
        style: TextStyle(color: palette.textMuted, fontSize: 12),
      ),
    );

    Future<void> choose<T>(
      String title,
      List<(T, String)> options,
      T selected,
      void Function(T) onPicked,
    ) async {
      final (T,)? picked = await _pick<T>(context, title, options, selected);
      if (picked != null) {
        onPicked(picked.$1);
      }
    }

    String label<T>(List<(T, String)> options, T value) =>
        options.firstWhere(((T, String) o) => o.$1 == value).$2;

    final List<(WarpProtocol, String)> protocols = <(WarpProtocol, String)>[
      (WarpProtocol.masque, 'MASQUE'),
      (WarpProtocol.wireguard, 'WireGuard'),
      (WarpProtocol.wgOverMasque, text.warpWgOverMasque),
      (WarpProtocol.warpInWarp, text.warpInWarp),
      (WarpProtocol.masqueInMasque, text.warpMasqueInMasque),
    ];
    final List<(WarpTransport, String)> transports = <(WarpTransport, String)>[
      (WarpTransport.http2, 'HTTP/2 (TCP)'),
      (WarpTransport.http3, 'HTTP/3 (QUIC)'),
    ];
    final List<(WarpScan, String)> scans = <(WarpScan, String)>[
      (WarpScan.turbo, text.warpScanTurbo),
      (WarpScan.balanced, text.warpScanBalanced),
      (WarpScan.thorough, text.warpScanThorough),
      (WarpScan.verified, text.warpScanVerified),
      (WarpScan.ironclad, text.warpScanIronclad),
    ];
    final List<(WarpObfuscation, String)> noises = <(WarpObfuscation, String)>[
      (WarpObfuscation.auto, text.warpAutomatic),
      (WarpObfuscation.off, text.off),
      (WarpObfuscation.light, text.warpNoiseLight),
      (WarpObfuscation.firewall, text.warpNoiseFirewall),
      (WarpObfuscation.balanced, text.warpNoiseBalanced),
      (WarpObfuscation.gfw, 'GFW'),
      (WarpObfuscation.aggressive, text.warpNoiseAggressive),
    ];
    final List<(WarpFingerprint, String)> fingerprints =
        <(WarpFingerprint, String)>[
          (WarpFingerprint.chrome, 'Chrome'),
          (WarpFingerprint.chrome120, 'Chrome 120'),
          (WarpFingerprint.firefox, 'Firefox'),
          (WarpFingerprint.semiPython, text.warpFingerprintPython),
          (WarpFingerprint.go, 'Go'),
        ];
    final List<(WarpIpVersion, String)> ipVersions = <(WarpIpVersion, String)>[
      (WarpIpVersion.v4, 'IPv4'),
      (WarpIpVersion.v6, 'IPv6'),
      (WarpIpVersion.both, text.warpIpBoth),
    ];

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(text.warpTitle),
        actions: <Widget>[
          if (warp != WarpSettings.defaults.copyWith(identity: warp.identity))
            TextButton(
              onPressed: () =>
                  save(WarpSettings.defaults.copyWith(identity: warp.identity)),
              child: Text(text.reset),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          children: <Widget>[
            const SizedBox(height: 12),
            Text(
              text.warpIntro,
              style: TextStyle(color: palette.textMuted, fontSize: 13),
            ),

            const SizedBox(height: 24),
            SectionHeader(text.warpSectionServers),
            const SizedBox(height: 4),
            PanelToggleRow(
              title: text.warpThroughTitle,
              meta: warp.throughWarp ? text.warpThroughOn : text.off,
              value: warp.throughWarp,
              onChanged: (bool on) => save(warp.copyWith(throughWarp: on)),
              isLast: true,
            ),
            explain(text.warpThroughExplain),

            const SizedBox(height: 28),
            SectionHeader(text.warpSectionConnection),
            const SizedBox(height: 4),
            PanelExternalRow(
              title: text.warpProtocol,
              meta: label(protocols, warp.protocol),
              onTap: () => choose(
                text.warpProtocol,
                protocols,
                warp.protocol,
                (WarpProtocol v) => save(warp.copyWith(protocol: v)),
              ),
            ),
            if (warp.protocol.overMasque)
              PanelExternalRow(
                title: text.warpTransport,
                meta: label(transports, warp.transport),
                onTap: () => choose(
                  text.warpTransport,
                  transports,
                  warp.transport,
                  (WarpTransport v) => save(warp.copyWith(transport: v)),
                ),
              ),
            PanelExternalRow(
              title: text.warpScan,
              meta: label(scans, warp.scan),
              onTap: () => choose(
                text.warpScan,
                scans,
                warp.scan,
                (WarpScan v) => save(warp.copyWith(scan: v)),
              ),
            ),
            PanelExternalRow(
              title: text.warpObfuscation,
              meta: label(noises, warp.obfuscation),
              onTap: () => choose(
                text.warpObfuscation,
                noises,
                warp.obfuscation,
                (WarpObfuscation v) => save(warp.copyWith(obfuscation: v)),
              ),
            ),
            PanelExternalRow(
              title: text.warpFingerprint,
              meta: label(fingerprints, warp.fingerprint),
              isLast: true,
              onTap: () => choose(
                text.warpFingerprint,
                fingerprints,
                warp.fingerprint,
                (WarpFingerprint v) => save(warp.copyWith(fingerprint: v)),
              ),
            ),
            explain(text.warpConnectionExplain),

            const SizedBox(height: 28),
            SectionHeader(text.warpSectionMore),
            const SizedBox(height: 4),
            PanelExternalRow(
              title: text.warpEndpoint,
              meta: warp.endpoint ?? text.warpAutomatic,
              onTap: () async {
                final String? value = await _edit(
                  context,
                  title: text.warpEndpoint,
                  hint: '162.159.192.1:443',
                  initial: warp.endpoint ?? '',
                  invalid: text.warpEndpointInvalid,
                  allowEmpty: true,
                  valid: isValidWarpEndpoint,
                );
                if (value != null) {
                  save(
                    warp.copyWith(endpoint: () => value.isEmpty ? null : value),
                  );
                }
              },
            ),
            if (warp.protocol.overMasque)
              PanelExternalRow(
                title: text.warpSni,
                meta: warp.masqueSni,
                onTap: () async {
                  final String? value = await _edit(
                    context,
                    title: text.warpSni,
                    hint: defaultMasqueSni,
                    initial: warp.masqueSni,
                    invalid: text.warpSniInvalid,
                    allowEmpty: false,
                    valid: isValidMasqueSni,
                  );
                  if (value != null) {
                    save(warp.copyWith(masqueSni: value));
                  }
                },
              ),
            PanelExternalRow(
              title: text.warpIpVersion,
              meta: label(ipVersions, warp.ipVersion),
              onTap: () => choose(
                text.warpIpVersion,
                ipVersions,
                warp.ipVersion,
                (WarpIpVersion v) => save(warp.copyWith(ipVersion: v)),
              ),
            ),
            PanelToggleRow(
              title: text.warpFragment,
              meta: warp.fragment ? text.on : text.off,
              value: warp.fragment,
              onChanged: (bool on) => save(warp.copyWith(fragment: on)),
            ),
            PanelToggleRow(
              title: text.warpEch,
              meta: warp.ech ? text.on : text.off,
              value: warp.ech,
              onChanged: (bool on) => save(warp.copyWith(ech: on)),
            ),
            PanelToggleRow(
              title: text.warpQuickReconnect,
              meta: warp.quickReconnect ? text.on : text.off,
              value: warp.quickReconnect,
              onChanged: (bool on) => save(warp.copyWith(quickReconnect: on)),
              isLast: true,
            ),
            explain(text.warpMoreExplain),

            const SizedBox(height: 28),
            SectionHeader(text.warpSectionKeys),
            const SizedBox(height: 4),
            PanelExternalRow(
              title: text.warpNewKeys,
              meta: text.warpNewKeysMeta,
              isLast: true,
              onTap: () {
                save(warp.copyWith(identity: warp.identity + 1));
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(text.warpNewKeysDone)));
              },
            ),
            explain(text.warpNewKeysExplain),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// A one-field record, so dismissing the sheet (null) is not a choice.
  static Future<(T,)?> _pick<T>(
    BuildContext context,
    String title,
    List<(T, String)> options,
    T selected,
  ) => showModalBottomSheet<(T,)>(
    context: context,
    backgroundColor: context.palette.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
    ),
    builder: (BuildContext context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Text(
              title,
              style: TextStyle(color: context.palette.textMuted, fontSize: 13),
            ),
          ),
          for (final (T, String) option in options)
            ListTile(
              title: Text(option.$2),
              trailing: option.$1 == selected
                  ? Icon(Icons.check, color: context.palette.blueText)
                  : null,
              onTap: () => Navigator.of(context).pop((option.$1,)),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  /// The text entered, '' for cleared where [allowEmpty]; null when
  /// cancelled. Refused until [valid].
  static Future<String?> _edit(
    BuildContext context, {
    required String title,
    required String hint,
    required String initial,
    required String invalid,
    required bool allowEmpty,
    required bool Function(String) valid,
  }) {
    final TextEditingController field = TextEditingController(text: initial);
    final AppText text = AppText.of(context);
    String? error;
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: field,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(hintText: hint, errorText: error),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(text.cancel),
            ),
            TextButton(
              onPressed: () {
                final String value = field.text.trim();
                if ((value.isEmpty && allowEmpty) || valid(value)) {
                  Navigator.of(context).pop(value);
                } else {
                  setState(() => error = invalid);
                }
              },
              child: Text(text.save),
            ),
          ],
        ),
      ),
    ).whenComplete(field.dispose);
  }
}
