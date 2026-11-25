import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/free/free_mode.dart';
import '../../core/servers/server_latency.dart';
import '../../core/servers/server_repository.dart';
import '../../core/storage/storage_providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/widgets/nebula/nebula_controls.dart';
import '../../core/widgets/nebula/nebula_feedback.dart';
import '../../core/widgets/nebula/nebula_page.dart';
import '../../core/widgets/nebula/nebula_rows.dart';
import '../../l10n/app_localizations.dart';
import '../devices/devices_controller.dart';
import '../devices/devices_state.dart';
import '../devices/profile_order.dart';

/// Pick a server, then a protocol on that server.
///
/// Both choices live on one screen because they are not independent: the
/// protocol list is a property of the selected server, and splitting them
/// across two screens would let a user pick a protocol the next server does
/// not offer.
///
/// Selection is local until the CTA is pressed. Writing straight through to
/// the controller on each tap would mean backing out of this screen silently
/// changed what the connect screen is pointed at.
class ServersScreen extends ConsumerStatefulWidget {
  const ServersScreen({super.key});

  @override
  ConsumerState<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends ConsumerState<ServersScreen> {
  String? _serverCode;
  String? _profileCode;
  bool _refreshing = false;

  /// Fetches every subscription again, now, and reloads the list -- here,
  /// where their servers are picked, not only under Your links.
  Future<void> _refreshSubscriptions() async {
    setState(() => _refreshing = true);
    try {
      await ref.read(subscriptionsProvider.notifier).refresh(force: true);
      await ref.read(devicesControllerProvider.notifier).load();
    } catch (_) {
      // A list that could not be refreshed keeps its last good copy.
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  void _pickServer(String code) => setState(() {
    _serverCode = code;
    // A protocol chosen on the previous server may not exist on this one;
    // the app chooses until the person does.
    _profileCode = automaticProfileCode;
  });

  @override
  Widget build(BuildContext context) {
    final AppText text = AppText.of(context);
    final DevicesState state = ref.watch(devicesControllerProvider);
    final ServerLatencyState latency = ref.watch(serverLatencyProvider);
    final NebulaPalette palette = context.palette;
    final bool freeMode = ref.watch(freeModeProvider);

    // Measured from this device to the server, so it only means anything
    // while the tunnel is down. With the tunnel up the app's own sockets go
    // through it, and the number would quietly be the round trip to the
    // server the user is already on -- the same figure for every row.
    final bool canMeasure = !state.tunnelEstablished;
    final List<AvailableServer> servers = sortByLatency(state.servers, latency);

    final String? serverCode = _serverCode ?? state.selectedServerCode;
    final AvailableServer? server = _serverIn(state, serverCode);
    final String? profileCode = _profileCode ?? state.selectedProfileCode;

    final bool pinging =
        server != null &&
        state.pinging &&
        state.protocolDelaysServer == server.code;

    return NebulaPage(
      title: text.serversTitle,
      trailing:
          (ref.watch(subscriptionsProvider).value ?? const <Object>[])
              .isNotEmpty
          ? IconButton(
              tooltip: text.serversRefreshSubscriptions,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              onPressed: _refreshing ? null : _refreshSubscriptions,
              icon: _refreshing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.refresh, color: palette.textMuted),
            )
          : null,
      footer: NebulaButton(
        label: server == null
            ? text.useServer
            : text.useNamedServer(server.displayName),
        onPressed: server == null
            ? null
            : () {
                ref
                    .read(devicesControllerProvider.notifier)
                    .choose(server.code, profileCode);
                Navigator.of(context).maybePop();
              },
      ),
      children: <Widget>[
        _SectionWithTest(
          // What the account may use: links added on this device are listed
          // too but are no one's permission -- 123 "permitted" was one server
          // and 122 links. Nothing is "permitted" without an account: the
          // relays and lists there are simply available.
          title: freeMode
              ? text.serversAvailable(
                  state.servers.fold<int>(
                    0,
                    (int n, AvailableServer s) => n + s.profiles.length,
                  ),
                )
              : text.serversPermitted(
                  state.servers
                      .where((AvailableServer s) => !isOwnLinkCode(s.code))
                      .length,
                ),
          busy: latency.isMeasuring,
          tested: latency.hasResults,
          canMeasure: canMeasure,
          onTest: () =>
              ref.read(serverLatencyProvider.notifier).measure(state.servers),
        ),
        RadioGroup<String>(
          groupValue: serverCode,
          onChanged: (String? code) {
            if (code != null) {
              _pickServer(code);
            }
          },
          child: NebulaRowGroup(
            children: <Widget>[
              for (final AvailableServer candidate in servers)
                _serverRow(text, palette, candidate, latency, serverCode),
            ],
          ),
        ),
        if (server != null) ...<Widget>[
          // Every protocol is listed, working from here or not: one blocked
          // on this network can work on another, or on another server. The
          // test beside the heading says which answer right now, by sending
          // a real request through each -- v2ray's "real delay".
          _SectionWithTest(
            title: text.protocolForServer(server.displayName),
            busy: pinging,
            tested: state.delaysFor(server.code).isNotEmpty,
            canMeasure: canMeasure,
            onTest: () => ref
                .read(devicesControllerProvider.notifier)
                .pingProtocols(
                  ref.read(deviceIdStoreProvider).read() ?? '',
                  server: server,
                ),
          ),
          RadioGroup<String>(
            groupValue: profileCode,
            onChanged: (String? code) {
              if (code != null) {
                setState(() => _profileCode = code);
              }
            },
            child: NebulaRowGroup(
              children: <Widget>[
                // First and the default: the app tries the protocols below
                // in this order until one works.
                _ProtocolRow(
                  code: automaticProfileCode,
                  title: text.protocolAutomatic,
                  selected: profileCode == automaticProfileCode,
                  onTap: () =>
                      setState(() => _profileCode = automaticProfileCode),
                ),
                for (final AvailableProfile profile in orderedProfiles(
                  server.profiles,
                  state.delaysFor(server.code),
                  pinging: pinging,
                ))
                  _ProtocolRow(
                    code: profile.code,
                    title: state.profileLabel(profile.code),
                    subtitle: _delayLabel(
                      text,
                      state.delaysFor(server.code)[profile.code],
                    ),
                    selected: profile.code == profileCode,
                    onTap: () => setState(() => _profileCode = profile.code),
                  ),
              ],
            ),
          ),
          if (server.code == LocalServerRepository.importedCode && !pinging)
            _RemoveFailed(
              failed: <String>{
                for (final MapEntry<String, ProtocolDelay> entry
                    in state.delaysFor(server.code).entries)
                  if (entry.value.outcome == DelayOutcome.failed) entry.key,
              },
            ),
        ],
      ],
    );
  }

  Widget _serverRow(
    AppText text,
    NebulaPalette palette,
    AvailableServer candidate,
    ServerLatencyState latency,
    String? serverCode,
  ) {
    final ServerLatency? reading = latency.forServer(candidate.code);
    // Absent until something has actually been measured. A placeholder here
    // would read as a reading.
    final String? figure = reading?.label(text);
    return NebulaRow(
      title: candidate.displayName,
      subtitle: _serverMeta(text, candidate),
      // Under maintenance: listed, amber, and not to be picked.
      subtitleColor: candidate.maintenance
          ? palette.amberText
          : _latencyColor(reading, palette),
      selected: candidate.code == serverCode,
      onTap: candidate.maintenance ? null : () => _pickServer(candidate.code),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (figure != null)
            Text(
              figure,
              style: TextStyle(
                fontFamily: 'GeistMono',
                fontSize: 13,
                color: _latencyColor(reading, palette) ?? palette.textPrimary,
              ),
            ),
          Radio<String>(
            value: candidate.code,
            enabled: !candidate.maintenance,
            activeColor: palette.blue,
          ),
        ],
      ),
    );
  }

  static AvailableServer? _serverIn(DevicesState state, String? code) {
    if (code == null) {
      return null;
    }
    for (final AvailableServer server in state.servers) {
      if (server.code == code) {
        return server;
      }
    }
    return null;
  }

  /// Unreachable servers are dimmed rather than hidden. The user is still
  /// entitled to them, and dropping one from the list would look like the
  /// account had lost access rather than like a port being blocked today.
  static Color? _latencyColor(ServerLatency? latency, NebulaPalette palette) {
    if (latency == null || latency.status == LatencyStatus.reachable) {
      return null;
    }
    return palette.textMuted;
  }

  /// `de-fra-1 · 3 protocols`, pluralised, because "1 protocols" is the kind
  /// of thing that makes a careful design look careless.
  static String _serverMeta(AppText text, AvailableServer server) {
    if (server.maintenance) {
      return '${server.code} · ${text.serverUnderMaintenance}';
    }
    // A group of this device's own links: how many, not an internal code.
    if (isOwnLinkCode(server.code) && server.publicHost.isEmpty) {
      return text.freeSubscriptionCount(server.profiles.length);
    }
    return '${server.code} · ${text.protocolCount(server.profiles.length)}';
  }
}

/// A protocol's last test result, as v2ray shows it: the delay in
/// milliseconds, or -1 ms when no answer came back. Null before a test.
String? _delayLabel(AppText text, ProtocolDelay? delay) {
  if (delay == null || delay.outcome == DelayOutcome.testing) {
    return null;
  }
  final String latency = text.latencyMilliseconds(delay.milliseconds ?? -1);
  final double? megabits = delay.megabits;
  if (megabits == null) {
    return latency;
  }
  // Nothing arrived: 0, the figure that says why the route does not work.
  final double shown = megabits < 0 ? 0 : megabits;
  return '$latency · ${text.speedMegabits(shown < 10 ? shown.toStringAsFixed(1) : shown.round().toString())}';
}

/// One protocol in the radio list.
class _ProtocolRow extends StatelessWidget {
  const _ProtocolRow({
    required this.code,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final String code;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return NebulaRow(
      title: title,
      subtitle: subtitle,
      selected: selected,
      onTap: onTap,
      trailing: Radio<String>(value: code, activeColor: context.palette.blue),
    );
  }
}

/// A section label doubling as the control that tests what is listed under
/// it. Beside the list rather than in the app bar: testing is something a
/// person does while comparing these rows.
class _SectionWithTest extends StatelessWidget {
  const _SectionWithTest({
    required this.title,
    required this.busy,
    required this.tested,
    required this.canMeasure,
    required this.onTest,
  });

  final String title;
  final bool busy;
  final bool tested;
  final bool canMeasure;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    final AppText text = AppText.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(child: NebulaSectionLabel(title)),
        if (busy)
          const Padding(
            padding: EdgeInsets.all(15),
            child: SizedBox(
              height: 14,
              width: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          // Disabled rather than hidden while connected, so the control does
          // not appear and vanish as the tunnel comes up: with the tunnel up,
          // a request could go through it and report on the wrong path.
          NebulaButton.text(
            label: canMeasure
                ? (tested ? text.latencyTestAgain : text.latencyTest)
                : text.latencyDisconnectToTest,
            onPressed: canMeasure ? onTest : null,
          ),
      ],
    );
  }
}

/// After a test of the links added by hand: removes those that failed it,
/// once confirmed. Subscriptions' links come back with their next refresh, so
/// only these.
class _RemoveFailed extends ConsumerWidget {
  const _RemoveFailed({required this.failed});

  final Set<String> failed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (failed.isEmpty) {
      return const SizedBox.shrink();
    }
    final AppText text = AppText.of(context);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: NebulaButton.text(
        label: text.removeFailed(failed.length),
        danger: true,
        onPressed: () async {
          final bool sure = await showNebulaConfirm(
            context,
            title: text.removeFailedTitle(failed.length),
            body: text.removeFailedBody,
            action: text.freeRemove,
            cancel: text.cancel,
            destructive: true,
          );
          if (!sure) {
            return;
          }
          await ref.read(freeProfilesProvider.notifier).removeCodes(failed);
          await ref.read(devicesControllerProvider.notifier).load();
        },
      ),
    );
  }
}
