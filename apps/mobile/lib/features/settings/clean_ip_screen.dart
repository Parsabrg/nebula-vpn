import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cdn/clean_ip.dart';
import '../../core/settings/advanced_settings_controller.dart';
import '../../core/storage/advanced_settings_store.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/look.dart';
import '../../core/widgets/nebula/nebula_controls.dart';
import '../../core/widgets/nebula/nebula_page.dart';
import '../../core/widgets/nebula/nebula_rows.dart';
import '../../core/xray/xray_config.dart';
import '../../l10n/app_localizations.dart';
import '../devices/devices_controller.dart';
import '../devices/devices_state.dart';

/// How many Cloudflare addresses one scan tries.
const int _scanSize = 100;

/// Finds a Cloudflare address that works from this network for the CDN
/// route, and uses it from the next connection (roadmap 11).
///
/// Scans only while disconnected: through the tunnel it would measure the
/// VPN server's network, not the person's. The route's name is learned
/// while connected through it, so a scan can follow a disconnect.
class CleanIpScreen extends ConsumerStatefulWidget {
  const CleanIpScreen({super.key});

  @override
  ConsumerState<CleanIpScreen> createState() => _CleanIpScreenState();
}

class _CleanIpScreenState extends ConsumerState<CleanIpScreen> {
  List<CleanIpResult>? _results;
  int? _done;
  bool _notCloudflare = false;

  @override
  void initState() {
    super.initState();
    final DevicesState devices = ref.read(devicesControllerProvider);
    final String? host = devices.xrayClient?.serverAddress;
    if (devices.tunnelEstablished &&
        host != null &&
        cdnTransports.contains(devices.xrayClient!.transport)) {
      Future<void>.microtask(
        () => ref
            .read(advancedSettingsControllerProvider.notifier)
            .rememberCdnHost(host),
      );
    }
  }

  Future<void> _scan(String host) async {
    setState(() {
      _done = 0;
      _results = null;
      _notCloudflare = false;
    });
    // Only a route through Cloudflare has edge addresses to choose from.
    bool onCloudflare = false;
    try {
      final List<InternetAddress> found = await InternetAddress.lookup(
        host,
        type: InternetAddressType.IPv4,
      );
      onCloudflare = found.any(
        (InternetAddress a) => isCloudflareAddress(a.address),
      );
    } on Object {
      onCloudflare = true; // Blocked lookups are exactly when a scan helps.
    }
    if (!onCloudflare) {
      if (mounted) {
        setState(() {
          _done = null;
          _notCloudflare = true;
        });
      }
      return;
    }
    final List<CleanIpResult> results = await scanCleanIps(
      host,
      sampleCloudflareAddresses(_scanSize),
      onProgress: (int done) {
        if (mounted) {
          setState(() => _done = done);
        }
      },
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _done = null;
      _results = results.take(5).toList();
    });
    if (results.isNotEmpty) {
      await ref
          .read(advancedSettingsControllerProvider.notifier)
          .setCleanIp(results.first.ip);
    }
  }

  @override
  Widget build(BuildContext context) {
    final NebulaPalette palette = context.palette;
    final AppText text = AppText.of(context);
    final AdvancedSettings settings = ref.watch(
      advancedSettingsControllerProvider,
    );
    final bool connected = ref.watch(
      devicesControllerProvider.select((DevicesState s) => s.tunnelEstablished),
    );
    // On Android this app is outside its own Xray tunnel, so the scan already
    // tests the network itself; only a WireGuard tunnel (which carries this
    // app too) or a desktop one would put the VPN in the way.
    final bool scanInsideTunnel =
        connected &&
        !(defaultTargetPlatform == TargetPlatform.android &&
            ref.watch(
                  devicesControllerProvider.select(
                    (DevicesState s) => s.activeProtocolCode,
                  ),
                ) !=
                wireguardProtocolCode);
    final String? host = settings.cleanIpHost;
    final List<CleanIpResult>? results = _results;
    final int? done = _done;

    final String? blocker = scanInsideTunnel
        ? text.cleanIpDisconnectFirst
        : host == null
        ? text.cleanIpConnectOnce
        : null;

    final AdvancedSettingsController controller = ref.read(
      advancedSettingsControllerProvider.notifier,
    );
    Widget radio({required bool on}) => Icon(
      on ? Icons.radio_button_checked : Icons.radio_button_unchecked,
      size: 24,
      color: on ? palette.blue : palette.textMuted,
    );

    return NebulaPage(
      title: text.cleanIp,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.only(
            top: 12,
            left: palette.look == NebulaLook.minimal ? 0 : 4,
            right: palette.look == NebulaLook.minimal ? 0 : 4,
          ),
          child: Text(
            text.cleanIpIntro,
            style: TextStyle(
              fontSize: 15,
              height: 22 / 15,
              color: palette.textMuted,
            ),
          ),
        ),
        for (final String warning in <String>[
          ?blocker,
          if (_notCloudflare) text.cleanIpNotCloudflare,
          if (results != null && results.isEmpty) text.cleanIpNoneFound,
        ]) ...<Widget>[
          const SizedBox(height: 16),
          NebulaNotice(text: warning, kind: NebulaNoticeKind.warning),
        ],
        const SizedBox(height: 20),
        NebulaRowGroup(
          children: <Widget>[
            if (results == null || results.isEmpty) ...<Widget>[
              NebulaRow(
                title: text.cleanIp,
                trailing: NebulaRowTrailing.value(
                  context,
                  settings.cleanIp ?? text.cleanIpAutomatic,
                  mono: settings.cleanIp != null,
                ),
              ),
              if (host != null)
                NebulaRow(
                  title: 'CDN',
                  trailing: NebulaRowTrailing.value(context, host),
                ),
            ] else ...<Widget>[
              NebulaRow(
                title: text.cleanIpAutomatic,
                trailing: radio(on: settings.cleanIp == null),
                onTap: () => controller.setCleanIp(null),
              ),
              for (final CleanIpResult r in results)
                NebulaRow(
                  title: r.ip,
                  subtitle: '${r.milliseconds} ms',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (r.ip == settings.cleanIp) ...<Widget>[
                        Flexible(
                          child: NebulaRowTrailing.badge(
                            context,
                            text.cleanIpInUse,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      radio(on: r.ip == settings.cleanIp),
                    ],
                  ),
                  onTap: () => controller.setCleanIp(r.ip),
                ),
            ],
          ],
        ),
        if (results != null && results.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(
              top: 10,
              left: palette.look == NebulaLook.minimal ? 0 : 8,
            ),
            child: Text(
              text.cleanIpAppliesNext,
              style: TextStyle(
                fontSize: 13,
                height: 19 / 13,
                color: palette.textMuted,
              ),
            ),
          ),
        const SizedBox(height: 16),
        NebulaButton(
          label: done != null
              ? text.cleanIpScanning(done, _scanSize)
              : text.cleanIpScan,
          icon: Icons.radar,
          busy: done != null,
          onPressed: blocker != null || done != null
              ? null
              : () => _scan(host!),
        ),
        if (settings.cleanIp != null) ...<Widget>[
          const SizedBox(height: 8),
          NebulaButton.text(
            label: text.cleanIpUseAutomatic,
            onPressed: () => controller.setCleanIp(null),
          ),
        ],
      ],
    );
  }
}
