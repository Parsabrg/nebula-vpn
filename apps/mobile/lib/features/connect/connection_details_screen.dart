import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/bytes.dart';
import '../../core/tunnel/tunnel_traffic.dart';
import '../../core/widgets/nebula/nebula_data.dart';
import '../../core/widgets/nebula/nebula_feedback.dart';
import '../../core/widgets/nebula/nebula_page.dart';
import '../../core/widgets/nebula/nebula_rows.dart';
import '../../core/xray/local_proxy.dart';
import '../../l10n/app_localizations.dart';
import '../devices/devices_controller.dart';
import '../devices/devices_state.dart';
import 'configuration_screen.dart';
import 'connect_screen.dart';
import 'tunnel_traffic_provider.dart';

/// Connection details (DESIGN_SPEC §4, new): what used to fill the Connect
/// screen -- address, session, resolvers, configuration -- one tap away.
class ConnectionDetailsScreen extends ConsumerWidget {
  const ConnectionDetailsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DevicesState state = ref.watch(devicesControllerProvider);
    return NebulaPage(
      title: AppText.of(context).connectionDetails,
      children: <Widget>[
        ConnectionDetailsBody(
          state: state,
          traffic: ref.watch(tunnelTrafficProvider).value,
          dnsResolvers: activeDnsResolvers(ref, state),
        ),
      ],
    );
  }
}

/// The details as a pure function of the state, for tests.
class ConnectionDetailsBody extends StatelessWidget {
  const ConnectionDetailsBody({
    required this.state,
    super.key,
    this.traffic,
    this.dnsResolvers,
  });

  final DevicesState state;
  final TunnelTraffic? traffic;

  /// Over the DNS tunnel: the resolvers it uses now. Null otherwise.
  final List<String>? dnsResolvers;

  @override
  Widget build(BuildContext context) {
    final AppText text = AppText.of(context);
    final bool up = state.tunnelEstablished;
    final List<String>? resolvers = dnsResolvers;
    // Null is "no reading" and drawn as a dash; zero is a reading.
    String bytes(int? value) => !up || value == null ? '—' : formatBytes(value);
    final List<(String, String)> stats = <(String, String)>[
      (text.rowDownloaded, bytes(traffic?.rxBytes)),
      (text.rowUploaded, bytes(traffic?.txBytes)),
      (
        text.rowAddress,
        up
            ? state.xrayClient?.serverAddress ??
                  state.selectedServer?.publicHost ??
                  '—'
            : '—',
      ),
      // WireGuard counts bytes, not time, and a tunnel this process did not
      // start has no known start: a dash, never a clock at zero.
      (
        text.rowSession,
        up && traffic?.elapsed != null
            ? formatTunnelDuration(traffic!.elapsed!)
            : '—',
      ),
      if (resolvers != null)
        (
          text.rowDnsResolvers,
          resolvers.isEmpty
              ? '—'
              : text.dnsResolversInUse(
                  resolvers.length,
                  resolvers.take(2).join(', '),
                ),
        ),
    ];
    final String protocol = state.activeProfileCode != null
        ? state.profileLabel(state.activeProfileCode!)
        : state.activeProtocolCode ??
              (state.selectedProfileCode == null
                  ? '—'
                  : state.profileLabel(state.selectedProfileCode!));
    final LocalProxy? proxy = state.localProxy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 16),
        NebulaStatsGrid(stats: stats),
        const SizedBox(height: 16),
        NebulaRowGroup(
          children: <Widget>[
            NebulaRow(
              title: text.rowServer,
              trailing: NebulaRowTrailing.value(
                context,
                state.selectedServer?.displayName ??
                    state.connectedServerCode ??
                    '—',
                mono: false,
              ),
            ),
            NebulaRow(
              title: text.rowProtocol,
              trailing: NebulaRowTrailing.value(context, protocol, mono: false),
            ),
            if (resolvers != null && resolvers.isNotEmpty)
              NebulaRow(
                title: text.rowDnsResolvers,
                trailing: NebulaRowTrailing.valueChevron(
                  context,
                  '${resolvers.length}',
                ),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (BuildContext context) => NebulaDialog(
                    title: text.rowDnsResolvers,
                    content: SelectableText(
                      resolvers.join('\n'),
                      style: const TextStyle(
                        fontFamily: 'GeistMono',
                        fontSize: 14,
                        height: 1.6,
                      ),
                    ),
                  ),
                ),
              ),
            NebulaRow(
              icon: Icons.description_outlined,
              title: text.rowConfiguration,
              trailing: NebulaRowTrailing.valueChevron(context, text.view),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) =>
                      const ConfigurationScreen(),
                ),
              ),
            ),
          ],
        ),
        // What an app is set up with to use the local proxy, each
        // tap-to-copy. The password is shown: the screen exists to be copied
        // from, and it opens only this device's own loopback proxy.
        if (proxy != null) ...<Widget>[
          const SizedBox(height: 16),
          NebulaRowGroup(
            children: <Widget>[
              for (final (String label, String value) in <(String, String)>[
                (text.rowAddress, '127.0.0.1:${proxy.port}'),
                (text.rowUsername, proxy.username),
                (text.rowPassword, proxy.password),
              ])
                NebulaRow(
                  title: label,
                  trailing: NebulaRowTrailing.value(context, value),
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: value));
                    if (context.mounted) {
                      showNebulaSnackbar(context, text.copiedToClipboard);
                    }
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }
}
