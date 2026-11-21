import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/platform/sensitive_clipboard.dart';
import '../../core/servers/server_repository.dart';
import '../../core/storage/storage_providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/widgets/nebula/nebula_controls.dart';
import '../../core/widgets/nebula/nebula_data.dart';
import '../../core/widgets/nebula/nebula_feedback.dart';
import '../../core/widgets/nebula/nebula_page.dart';
import '../../core/widgets/nebula/nebula_rows.dart';
import '../../core/widgets/nebula/nebula_surface.dart';
import '../../core/xray/xray_config.dart';
import '../../l10n/app_localizations.dart';
import '../devices/devices_controller.dart';
import '../devices/devices_state.dart';
import 'client_summary.dart';

/// What the server provisioned, for the peer-only state.
///
/// Reached from the "Configuration" row when a device is registered but has
/// no tunnel. Its job is to make an unusable state useful: the client exists
/// and is valid, so hand it over in a form that can be pasted into something
/// that *can* run it, rather than leaving the user with a dead screen.
class ConfigurationScreen extends ConsumerWidget {
  const ConfigurationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DevicesState state = ref.watch(devicesControllerProvider);
    final NebulaPalette palette = context.palette;
    // WARP's connection is Cloudflare's, with nothing of ours to copy or
    // release: it would list 127.0.0.1 : 0 and empty fields.
    final XrayClientResult? client =
        state.xrayClient?.transport == kWarpTransport ? null : state.xrayClient;

    final AppText text = AppText.of(context);
    NebulaRow info(String title, String value) => NebulaRow(
      title: title,
      trailing: NebulaRowTrailing.value(context, value),
    );

    return NebulaPage(
      title: text.configurationTitle,
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (client != null) ...<Widget>[
            NebulaButton(
              label: text.copy,
              icon: Icons.content_copy,
              onPressed: () => _copy(context, client),
            ),
            const SizedBox(height: 8),
          ],
          if (state.xrayClient?.transport != kWarpTransport)
            NebulaButton.text(
              label: text.releasePeer,
              danger: true,
              onPressed: () => _releasePeer(context, ref, state),
            ),
        ],
      ),
      children: <Widget>[
        const SizedBox(height: 16),
        // Only when it is true: the screen is also reached from Connection
        // details while the tunnel is up, where it said "not tunnelling"
        // about a working connection.
        if (!state.tunnelEstablished)
          NebulaNotice(
            text: text.peerOnlyNotice,
            kind: NebulaNoticeKind.warning,
          ),
        if (client == null)
          NebulaEmptyState(
            icon: Icons.description_outlined,
            title: text.noClientConfiguration,
          )
        else ...<Widget>[
          NebulaSectionLabel(text.xrayClient),
          NebulaRowGroup(
            children: <Widget>[
              info(text.rowAddress, '${client.serverAddress} : ${client.port}'),
              info('SNI', client.sni),
              info(
                text.rowTransport,
                '${client.transport} / ${client.transportSecurity}',
              ),
              if (client.path != null) info(text.rowPath, client.path!),
              info('UUID', truncateUuid(client.uuid)),
            ],
          ),
          const SizedBox(height: 16),
          // What Copy puts on the clipboard, so nothing is copied unseen.
          NebulaPanel(
            padding: const EdgeInsets.all(14),
            child: SelectableText(
              clientSummary(client),
              style: TextStyle(
                fontFamily: 'GeistMono',
                fontSize: 12,
                height: 18 / 12,
                color: palette.textPrimary,
              ),
            ),
          ),
        ],
      ],
    );
  }

  static Future<void> _copy(
    BuildContext context,
    XrayClientResult client,
  ) async {
    await copySensitive(clientSummary(client));
    if (!context.mounted) {
      return;
    }
    showNebulaSnackbar(context, AppText.of(context).configurationCopied);
  }

  /// Releasing is destructive and not obviously so from the button, so it
  /// confirms first. The device keeps working until the next refresh, which
  /// is exactly the kind of delay that makes an accidental tap hard to
  /// connect to its consequence later.
  static Future<void> _releasePeer(
    BuildContext context,
    WidgetRef ref,
    DevicesState state,
  ) async {
    final AppText text = AppText.of(context);
    final bool confirmed = await showNebulaConfirm(
      context,
      title: text.releasePeerQuestion,
      body: text.releasePeerBody,
      action: text.release,
      cancel: text.cancel,
      destructive: true,
    );

    if (!confirmed || !context.mounted) {
      return;
    }
    final String? deviceId = ref.read(deviceIdStoreProvider).read();
    if (deviceId == null) {
      return;
    }
    await ref.read(devicesControllerProvider.notifier).disconnect(deviceId);
    if (context.mounted) {
      Navigator.of(context).maybePop();
    }
  }
}
