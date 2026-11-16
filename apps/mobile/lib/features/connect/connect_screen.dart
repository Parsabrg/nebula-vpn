import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_notifier.dart';
import '../../core/auth/auth_state.dart';
import '../../core/format/bytes.dart';
import '../../core/free/free_mode.dart';
import '../../core/network/dns_tunnel_engine.dart';
import '../../core/network/dns_tunnel_resolvers.dart';
import '../../core/storage/storage_providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/look.dart';
import '../../core/tunnel/tunnel_traffic.dart';
import '../../core/widgets/nebula/nebula_controls.dart';
import '../../core/widgets/nebula/nebula_data.dart';
import '../../core/widgets/nebula/nebula_nav.dart';
import '../../core/widgets/nebula/nebula_page.dart';
import '../../core/widgets/nebula/nebula_rows.dart';
import '../../core/widgets/panel/panel_atoms.dart';
import '../../core/xray/xray_config.dart';
import '../../l10n/app_localizations.dart';
import '../devices/devices_controller.dart';
import '../devices/devices_state.dart';
import '../free/free_mode_screen.dart';
import 'connect_view.dart';
import 'connection_details_screen.dart';
import 'servers_screen.dart';
import 'tunnel_traffic_provider.dart';

/// The first tab, and the whole point of the app (DESIGN_SPEC §4, Connect):
/// deliberately sparse. The status hero, a traffic line while connected,
/// space, one server row, the way to Connection details, and the action.
///
/// One screen with seven presentations: [connectViewOf] decides which, a
/// pure function the states are tested through.
class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

/// Below this height the Connect screen scrolls as one page.
const double _pinnedLayoutMinHeight = 560;

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final DevicesController controller = ref.read(
        devicesControllerProvider.notifier,
      );
      await controller.load();
      if (!mounted) {
        return;
      }
      await controller.connectOnLaunchIfWanted(
        ref.read(deviceIdStoreProvider).read(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final DevicesState state = ref.watch(devicesControllerProvider);
    final ConnectView view = connectViewOf(state);
    final NebulaPalette p = context.palette;
    final TunnelTraffic? traffic = ref.watch(tunnelTrafficProvider).value;
    final bool free = ref.watch(freeModeProvider);

    final Widget block = ConnectStateBlock(
      view: view,
      state: state,
      traffic: traffic,
      freeMode: free,
    );
    final Widget messages = ConnectMessages(
      state: state,
      view: view,
      serverUnreachable: ref.watch(authNotifierProvider) is AuthUnreachable,
    );
    final Widget bottom = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        messages,
        if (_hasServerRow(view)) ...<Widget>[
          ConnectServerRow(view: view, state: state),
          Center(
            child: NebulaLinkButton(
              label: AppText.of(context).connectionDetails,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) =>
                      const ConnectionDetailsScreen(),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        _Action(view: view, state: state),
        const SizedBox(height: 16),
      ],
    );

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Padding(
          padding: nebulaPagePadding(context),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints box) {
              // Short screens (a phone in landscape) scroll as one page:
              // pinned, the state was squeezed to nothing behind an error.
              if (box.maxHeight < _pinnedLayoutMinHeight) {
                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const _Header(),
                      block,
                      const SizedBox(height: 24),
                      bottom,
                    ],
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const _Header(),
                  Expanded(child: SingleChildScrollView(child: block)),
                  bottom,
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  static bool _hasServerRow(ConnectView view) =>
      view != ConnectView.loading &&
      view != ConnectView.unreachable &&
      view != ConnectView.noServers;
}

/// The brand on a phone, the "Connect" title on desktop, and "+" for Your
/// links. Free mode shows it too: a first install looked for the Add
/// buttons here (2026-10-17).
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final NebulaPalette p = context.palette;
    final AppText text = AppText.of(context);
    return NebulaTabHeader(
      title: nebulaDesktopLayout(context)
          ? Semantics(
              header: true,
              child: Text(
                text.tabConnect,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: nebulaTitleStyle(p),
              ),
            )
          : const NebulaBrand(),
      action: NebulaHeaderAction(
        icon: Icons.add,
        label: text.ownLinksTitle,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (BuildContext context) =>
                const FreeModeScreen(ownLinks: true),
          ),
        ),
      ),
    );
  }
}

/// The status hero and, while connected, the traffic line.
///
/// Public because it is the part worth testing on its own: a pure function
/// of a view and a state.
class ConnectStateBlock extends StatelessWidget {
  const ConnectStateBlock({
    required this.view,
    required this.state,
    super.key,
    this.traffic,
    this.freeMode = false,
  });

  final ConnectView view;
  final DevicesState state;

  /// No account and no server of one's own: the words for a signed-in
  /// failure ("Peer only", "Registered on") would say something untrue.
  final bool freeMode;

  /// The live reading; null (no reading yet) and zero are drawn apart.
  final TunnelTraffic? traffic;

  @override
  Widget build(BuildContext context) {
    final AppText text = AppText.of(context);
    final NebulaPalette p = context.palette;

    if (view == ConnectView.loading) {
      return const Padding(
        padding: EdgeInsets.only(top: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SkeletonBar(width: 120, height: 12),
            SizedBox(height: 16),
            SkeletonBar(width: 220, height: 40),
            SizedBox(height: 12),
            SkeletonBar(width: 160, height: 14),
          ],
        ),
      );
    }

    final String? server =
        state.selectedServer?.displayName ?? state.connectedServerCode;
    final String? error = view == ConnectView.protected
        ? null
        : state.actionErrorMessage;

    final (
      Color dot,
      String eyebrow,
      String title,
      Color? titleColor,
    ) = switch (view) {
      // Connected but not answering: said in amber, not "Protected", for
      // the minute it is given to recover (or while there is no network).
      ConnectView.protected when state.stall != null => (
        p.amber,
        server ?? text.statusConnected,
        state.stall == TunnelStall.noNetwork
            ? text.wordNoNetwork
            : text.wordReconnecting,
        p.amberText,
      ),
      ConnectView.protected => (
        p.ok,
        server ?? text.statusConnected,
        // Not "Protected" for a local proxy (only apps pointed at it go
        // through) or sanctioned-services-only (everything else leaves
        // directly): the largest word must not overstate it.
        state.localProxy != null
            ? text.wordProxyOn
            : state.sanctionsOnly
            ? text.wordOn
            : view.word(text)!,
        state.localProxy != null ? p.textPrimary : p.textMax,
      ),
      ConnectView.connecting => (
        p.blue,
        server ?? text.statusHandshake,
        view.word(text)!,
        null,
      ),
      ConnectView.notProtected => (
        p.amber,
        server ?? text.statusNoTunnel,
        view.word(text)!,
        p.amberText,
      ),
      ConnectView.off => (
        p.amber,
        server ?? text.statusDisconnected,
        view.word(text)!,
        null,
      ),
      ConnectView.unreachable => (
        p.red,
        text.statusNoConnection,
        view.word(text)!,
        null,
      ),
      ConnectView.noServers => (
        p.dotOff,
        text.statusNoServers,
        text.nothingToConnect,
        null,
      ),
      ConnectView.loading => throw StateError('handled above'),
    };

    final String subline =
        error ??
        switch (view) {
          ConnectView.protected when state.stall == TunnelStall.noNetwork =>
            text.statusWaitingForNetwork,
          ConnectView.protected when state.stall != null =>
            text.statusRecovering,
          ConnectView.protected when state.localProxy != null =>
            text.statusLocalProxy('127.0.0.1:${state.localProxy!.port}'),
          ConnectView.protected when state.sanctionsOnly =>
            text.statusSanctionsOnly(server ?? ''),
          ConnectView.protected =>
            // A clock only where this process saw the tunnel come up: one
            // started at zero for a tunnel it did not start would lie.
            traffic?.elapsed == null
                ? text.statusConnected
                : '${text.rowSession} · '
                      '${formatTunnelDuration(traffic!.elapsed!)}',
          ConnectView.connecting => text.statusHandshake,
          ConnectView.notProtected =>
            freeMode ? text.statusNoTunnel : text.statusPeerOnly,
          ConnectView.off => text.statusDisconnected,
          // The reason, not a guess at it: "check your network" over a
          // working network sent the owner looking in the wrong place.
          ConnectView.unreachable =>
            state.loadErrorMessage ?? text.checkYourNetwork,
          ConnectView.noServers => text.noServersPermitted,
          ConnectView.loading => '',
        };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        NebulaStatusHero(
          dotColor: dot,
          eyebrow: eyebrow,
          title: title,
          titleColor: titleColor,
          // The whole sentence: the copy ends in the one thing that fixes
          // it, and an ellipsis would drop exactly that half.
          subline: subline,
          sublineColor: error != null ? p.redText : null,
        ),
        if (view == ConnectView.protected) _TrafficLine(traffic: traffic),
      ],
    );
  }
}

/// ↓ Downloaded and ↑ Uploaded, spelled out: one line, wrapping on narrow
/// screens rather than cutting a figure off.
class _TrafficLine extends StatelessWidget {
  const _TrafficLine({required this.traffic});

  final TunnelTraffic? traffic;

  @override
  Widget build(BuildContext context) {
    final NebulaPalette p = context.palette;
    final AppText text = AppText.of(context);
    Widget item(IconData icon, String label, int? bytes) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 16, color: p.textMuted),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontSize: 13, height: 18 / 13, color: p.textMuted),
        ),
        const SizedBox(width: 6),
        Text(
          bytes == null ? '—' : formatBytes(bytes),
          style: TextStyle(
            fontFamily: 'GeistMono',
            fontSize: 15,
            height: 20 / 15,
            color: p.textPrimary,
          ),
        ),
      ],
    );
    return Padding(
      padding: EdgeInsets.only(
        top: 16,
        left: p.look == NebulaLook.minimal ? 0 : 4,
      ),
      child: Wrap(
        spacing: 20,
        runSpacing: 8,
        children: <Widget>[
          item(Icons.arrow_downward, text.rowDownloaded, traffic?.rxBytes),
          item(Icons.arrow_upward, text.rowUploaded, traffic?.txBytes),
        ],
      ),
    );
  }
}

/// The one server row: server, protocol, "Change". Not tappable while
/// connecting: changing the target mid-handshake would leave the request
/// and the screen disagreeing.
class ConnectServerRow extends StatelessWidget {
  const ConnectServerRow({super.key, required this.view, required this.state});

  final ConnectView view;
  final DevicesState state;

  @override
  Widget build(BuildContext context) {
    final AppText text = AppText.of(context);
    final NebulaPalette p = context.palette;
    final bool live =
        view == ConnectView.protected || view == ConnectView.connecting;
    final String? profile = live && state.activeProfileCode != null
        ? state.activeProfileCode
        : state.selectedProfileCode;
    final String protocol = profile == null
        ? text.choose
        : profile == automaticProfileCode
        ? text.protocolAutomatic
        : state.profileLabel(profile);
    final bool tappable = view != ConnectView.connecting;
    return NebulaRowGroup(
      children: <Widget>[
        NebulaRow(
          icon: Icons.public,
          title:
              state.selectedServer?.displayName ??
              state.connectedServerCode ??
              text.choose,
          // "Try another server" is what the error says when none of a
          // server's protocols got through: the row says where to do it.
          titleColor: view == ConnectView.notProtected ? p.amberText : null,
          // "VLESS Encryption · through WARP · Iranian sites direct": on a
          // working connection, the settings that change how it behaves --
          // only those that apply to it, so a setting this protocol skips
          // is simply not there.
          subtitle: <String>[
            protocol,
            if (live && state.stall == null) ...traitLabels(text, state.traits),
          ].join(' · '),
          trailing: tappable
              ? NebulaRowTrailing.valueChevron(context, text.change)
              : null,
          onTap: tappable
              ? () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) => const ServersScreen(),
                  ),
                )
              : null,
        ),
      ],
    );
  }
}

/// A failure while connected (the hero says it otherwise), and where the
/// screen's contents came from when that is not the server.
class ConnectMessages extends StatelessWidget {
  const ConnectMessages({
    required this.state,
    super.key,
    this.view = ConnectView.protected,
    this.serverUnreachable = false,
  });

  final DevicesState state;
  final ConnectView view;

  /// A session is stored but the server did not answer: what is on screen
  /// comes from this device rather than from the server.
  final bool serverUnreachable;

  @override
  Widget build(BuildContext context) {
    final AppText text = AppText.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // A disconnect can fail too; the hero is busy saying Protected.
        if (view == ConnectView.protected &&
            state.actionErrorMessage != null) ...<Widget>[
          NebulaNotice(
            text: state.actionErrorMessage!,
            kind: NebulaNoticeKind.error,
          ),
          const SizedBox(height: 12),
        ],
        // Only while that connection is up: after it ended, "Connected with
        // credentials saved on this device" sat under Off (2026-10-18).
        if (serverUnreachable ||
            (state.fromSavedCredential && state.tunnelEstablished)) ...<Widget>[
          NebulaNotice(
            text: state.fromSavedCredential && state.tunnelEstablished
                ? text.savedCredentialNotice
                : text.offlineNotice,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// Disconnect (secondary), Cancel while connecting, Connect, or Try again.
class _Action extends ConsumerWidget {
  const _Action({required this.view, required this.state});

  final ConnectView view;
  final DevicesState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (view == ConnectView.loading) {
      return const SizedBox(height: 52);
    }
    final String? deviceId = ref.watch(deviceIdStoreProvider).read();
    final DevicesController controller = ref.read(
      devicesControllerProvider.notifier,
    );
    final String label = view.ctaLabel(AppText.of(context))!;
    switch (view) {
      case ConnectView.off:
        // Disabled until there is something to connect to: the controller
        // ignores a connect with nothing selected.
        final bool ready =
            state.selectedServerCode != null &&
            state.selectedProfileCode != null;
        return NebulaButton(
          label: label,
          icon: Icons.power_settings_new,
          onPressed: deviceId == null || !ready
              ? null
              : () => controller.connect(deviceId),
        );
      case ConnectView.connecting:
        // Live while a connect is in flight; a disconnect finishing has
        // nothing to cancel.
        return NebulaButton.secondary(
          label: label,
          icon: Icons.power_settings_new,
          onPressed: controller.canCancelConnect
              ? controller.cancelConnect
              : null,
        );
      case ConnectView.protected:
        return NebulaButton.secondary(
          label: label,
          icon: Icons.power_settings_new,
          onPressed: deviceId == null
              ? null
              : () => controller.disconnect(deviceId),
        );
      case ConnectView.notProtected:
        return NebulaButton(
          label: label,
          icon: Icons.power_settings_new,
          onPressed: deviceId == null
              ? null
              : () => controller.connect(deviceId),
        );
      case ConnectView.unreachable:
        return NebulaButton(label: label, onPressed: controller.load);
      case ConnectView.noServers:
        return NebulaButton.secondary(label: label, onPressed: controller.load);
      case ConnectView.loading:
        throw StateError('handled above');
    }
  }
}

/// Over the DNS tunnel, the resolvers in use; null on any other protocol.
List<String>? activeDnsResolvers(WidgetRef ref, DevicesState state) =>
    state.activeProfileCode == kDnsTunnelProfileCode
    ? ref.watch(dnsTunnelActiveResolversProvider).value
    : null;

/// The settings that change how this connection behaves, in words: what
/// follows the protocol on Connect. Only what applies to it is recorded
/// (connectionTraits), so a setting this protocol skips is simply absent.
List<String> traitLabels(AppText text, ConnectionTraits traits) => <String>[
  if (traits.on.contains(ConnectionTrait.warp)) text.viaWarp,
  if (traits.on.contains(ConnectionTrait.sanctionsOnly))
    text.traitSanctionsOnly,
  if (traits.on.contains(ConnectionTrait.iranDirect)) text.traitIranDirect,
  if (traits.bypassSites > 0) text.traitSitesSkip(traits.bypassSites),
  if (traits.bypassApps > 0) text.splitTunnelingCount(traits.bypassApps),
  if (traits.on.contains(ConnectionTrait.fragment)) text.traitSplitHandshake,
  if (traits.on.contains(ConnectionTrait.mux)) text.traitMux,
  if (traits.on.contains(ConnectionTrait.adBlock)) text.traitAdBlock,
];
