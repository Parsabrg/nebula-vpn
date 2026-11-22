import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/settings/advanced_settings_controller.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/warp/warp_settings.dart';
import '../../core/widgets/nebula/nebula_controls.dart';
import '../../core/widgets/nebula/nebula_data.dart';
import '../../core/widgets/nebula/nebula_feedback.dart';
import '../../core/widgets/nebula/nebula_page.dart';
import '../../core/widgets/nebula/nebula_rows.dart';
import '../../l10n/app_localizations.dart';

/// Everything Cloudflare WARP (Aether) can be told, in the words of what it
/// changes. The defaults are what gets through most often in Iran: MASQUE
/// over HTTP/2 with Chrome's handshake.
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
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Text(
        line,
        style: TextStyle(color: palette.textMuted, fontSize: 12, height: 1.4),
      ),
    );

    Future<void> choose<T>(
      String title,
      List<(T, String)> options,
      T selected,
      void Function(T) onPicked,
    ) async {
      final T? picked = await showNebulaChoice<T>(
        context,
        title: title,
        options: options,
        selected: selected,
      );
      if (picked != null) {
        onPicked(picked);
      }
    }

    String label<T>(List<(T, String)> options, T value) =>
        options.firstWhere(((T, String) o) => o.$1 == value).$2;

    Widget pick(String title, String value, VoidCallback onTap) => NebulaRow(
      title: title,
      trailing: NebulaRowTrailing.valueChevron(context, value),
      onTap: onTap,
    );

    Widget toggle(
      String title,
      String subtitle,
      bool value,
      ValueChanged<bool> onChanged,
    ) => NebulaSwitchRow(
      title: title,
      subtitle: subtitle,
      value: value,
      onChanged: onChanged,
    );

    final List<(WarpProtocol, String)> protocols = <(WarpProtocol, String)>[
      (WarpProtocol.masque, 'MASQUE'),
      (WarpProtocol.wireguard, 'WireGuard'),
      (WarpProtocol.wgOverMasque, text.warpWgOverMasque),
      (WarpProtocol.warpInWarp, text.warpInWarp),
      (WarpProtocol.masqueInMasque, text.warpMasqueInMasque),
    ];
    final List<(WarpEngine, String)> engines = <(WarpEngine, String)>[
      (WarpEngine.aether, 'Aether'),
      (WarpEngine.xray, text.warpEngineXray),
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

    final WarpSettings defaults = WarpSettings.defaults.copyWith(
      identity: warp.identity,
    );

    return NebulaPage(
      title: text.warpTitle,
      trailing: warp != defaults
          ? NebulaButton.text(
              label: text.reset,
              onPressed: () => save(defaults),
            )
          : null,
      children: <Widget>[
        const SizedBox(height: 8),
        Text(
          text.warpIntro,
          style: TextStyle(color: palette.textMuted, fontSize: 14, height: 1.4),
        ),
        const SizedBox(height: 16),
        NebulaRowGroup(
          children: <Widget>[
            toggle(
              text.warpOutsideIranTitle,
              warp.leaveOutsideIran ? text.warpOutsideIranOn : text.off,
              warp.leaveOutsideIran,
              (bool on) => save(warp.copyWith(leaveOutsideIran: on)),
            ),
          ],
        ),
        explain(text.warpOutsideIranExplain),
        NebulaSectionLabel(text.warpSectionServers),
        NebulaRowGroup(
          children: <Widget>[
            toggle(
              text.warpThroughTitle,
              warp.throughWarp ? text.warpThroughOn : text.off,
              warp.throughWarp,
              (bool on) => save(warp.copyWith(throughWarp: on)),
            ),
          ],
        ),
        explain(text.warpThroughExplain),
        NebulaSectionLabel(text.warpSectionConnection),
        NebulaRowGroup(
          children: <Widget>[
            if (warpSupported)
              pick(
                text.warpEngine,
                label(engines, warp.engine),
                () => choose(
                  text.warpEngine,
                  engines,
                  warp.engine,
                  (WarpEngine v) => save(warp.copyWith(engine: v)),
                ),
              ),
            pick(
              text.warpProtocol,
              label(protocols, warp.protocol),
              () => choose(
                text.warpProtocol,
                protocols,
                warp.protocol,
                (WarpProtocol v) => save(warp.copyWith(protocol: v)),
              ),
            ),
            if (warp.protocol.overMasque)
              pick(
                text.warpTransport,
                label(transports, warp.transport),
                () => choose(
                  text.warpTransport,
                  transports,
                  warp.transport,
                  (WarpTransport v) => save(warp.copyWith(transport: v)),
                ),
              ),
            pick(
              text.warpScan,
              label(scans, warp.scan),
              () => choose(
                text.warpScan,
                scans,
                warp.scan,
                (WarpScan v) => save(warp.copyWith(scan: v)),
              ),
            ),
            pick(
              text.warpObfuscation,
              label(noises, warp.obfuscation),
              () => choose(
                text.warpObfuscation,
                noises,
                warp.obfuscation,
                (WarpObfuscation v) => save(warp.copyWith(obfuscation: v)),
              ),
            ),
            pick(
              text.warpFingerprint,
              label(fingerprints, warp.fingerprint),
              () => choose(
                text.warpFingerprint,
                fingerprints,
                warp.fingerprint,
                (WarpFingerprint v) => save(warp.copyWith(fingerprint: v)),
              ),
            ),
          ],
        ),
        if (warpSupported && warp.engine == WarpEngine.xray)
          explain(text.warpEngineXrayExplain),
        explain(text.warpConnectionExplain),
        NebulaSectionLabel(text.warpSectionMore),
        NebulaRowGroup(
          children: <Widget>[
            pick(
              text.warpEndpoint,
              warp.endpoint ?? text.warpAutomatic,
              () async {
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
              pick(text.warpSni, warp.masqueSni, () async {
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
              }),
            pick(
              text.warpIpVersion,
              label(ipVersions, warp.ipVersion),
              () => choose(
                text.warpIpVersion,
                ipVersions,
                warp.ipVersion,
                (WarpIpVersion v) => save(warp.copyWith(ipVersion: v)),
              ),
            ),
            toggle(
              text.warpFragment,
              warp.fragment ? text.on : text.off,
              warp.fragment,
              (bool on) => save(warp.copyWith(fragment: on)),
            ),
            toggle(
              text.warpEch,
              warp.ech ? text.on : text.off,
              warp.ech,
              (bool on) => save(warp.copyWith(ech: on)),
            ),
            toggle(
              text.warpQuickReconnect,
              warp.quickReconnect ? text.on : text.off,
              warp.quickReconnect,
              (bool on) => save(warp.copyWith(quickReconnect: on)),
            ),
          ],
        ),
        explain(text.warpMoreExplain),
        NebulaSectionLabel(text.warpSectionKeys),
        NebulaRowGroup(
          children: <Widget>[
            NebulaRow(
              icon: Icons.key_outlined,
              title: text.warpNewKeys,
              subtitle: text.warpNewKeysMeta,
              trailing: NebulaRowTrailing.chevron(context),
              onTap: () {
                save(warp.copyWith(identity: warp.identity + 1));
                showNebulaSnackbar(context, text.warpNewKeysDone);
              },
            ),
          ],
        ),
        explain(text.warpNewKeysExplain),
        const SizedBox(height: 8),
      ],
    );
  }

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
        builder: (BuildContext context, StateSetter setState) => NebulaDialog(
          title: title,
          content: NebulaField(
            label: title,
            labelVisible: false,
            controller: field,
            autofocus: true,
            mono: true,
            autocorrect: false,
            keyboardType: TextInputType.url,
            hint: hint,
            errorText: error,
          ),
          actions: <Widget>[
            NebulaButton.secondary(
              label: text.cancel,
              onPressed: () => Navigator.of(context).pop(),
            ),
            NebulaButton(
              label: text.save,
              onPressed: () {
                final String value = field.text.trim();
                if ((value.isEmpty && allowEmpty) || valid(value)) {
                  Navigator.of(context).pop(value);
                } else {
                  setState(() => error = invalid);
                }
              },
            ),
          ],
        ),
      ),
    ).whenComplete(field.dispose);
  }
}
