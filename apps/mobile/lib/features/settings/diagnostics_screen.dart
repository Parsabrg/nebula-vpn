import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_info.dart';
import '../../core/diagnostics/diagnostics_report.dart';
import '../../core/diagnostics/leak_test.dart';
import '../../core/diagnostics/packet_loss.dart';
import '../../core/diagnostics/speed_test.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/look.dart';
import '../../core/widgets/nebula/nebula_controls.dart';
import '../../core/widgets/nebula/nebula_page.dart';
import '../../core/widgets/nebula/nebula_rows.dart';
import '../../core/wireguard/tunnel_controller.dart';
import '../../core/xray/local_proxy.dart';
import '../../l10n/app_localizations.dart';
import '../devices/devices_controller.dart';
import '../devices/devices_state.dart';

/// Where the tests go to measure the tunnel; null where this app's own
/// traffic already takes its path. See DevicesController.measurementRoute.
final measurementRouteProvider =
    Provider<({LocalProxy proxy, InternetAddress? resolver})?>((Ref ref) {
      ref.watch(devicesControllerProvider);
      return ref.read(devicesControllerProvider.notifier).measurementRoute;
    });

final leakTestProvider = Provider<LeakTest>((Ref ref) {
  final route = ref.watch(measurementRouteProvider);
  if (route == null) {
    return LeakTest();
  }
  final InternetAddress? resolver = route.resolver;
  return LeakTest(
    fetch: (Uri url) async {
      final ({int status, String body})? answer = await httpsThroughSocks(
        route.proxy,
        host: url.host,
        path: url.path,
      );
      return answer?.status == 200 ? answer!.body : null;
    },
    // The tunnel's own resolver, asked the way apps ask it: from here, a
    // lookup goes to the ISP's, which forges blocked names.
    lookup: resolver == null
        ? null
        : (String host) => lookupThroughSocks(route.proxy, resolver, host),
  );
});
final speedTestProvider = Provider<SpeedTest>((Ref ref) {
  final route = ref.watch(measurementRouteProvider);
  return SpeedTest(
    proxy: route == null ? null : httpProxyDirective(route.proxy),
  );
});
final packetLossTestProvider = Provider<PacketLossTest>(
  (Ref ref) =>
      PacketLossTest(through: ref.watch(measurementRouteProvider)?.proxy),
);

/// The connection as it is right now, the leak test, the speed test, and a
/// report to copy when asking for help (roadmap 77 and 78).
///
/// The tests run only when asked: a leak test makes a few requests to
/// Cloudflare and Akamai, which see the exit address -- the same address
/// every site does -- and a speed test moves up to 28 MB through Cloudflare.
class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
  LeakReport? _report;
  bool _running = false;
  SpeedReport? _speed;
  bool _measuringSpeed = false;
  LossReport? _loss;
  bool _measuringLoss = false;
  Duration? _handshakeAge;

  @override
  void initState() {
    super.initState();
    _readHandshake();
  }

  /// WireGuard's handshake, which only the tunnel can tell.
  Future<void> _readHandshake() async {
    final DevicesState state = ref.read(devicesControllerProvider);
    if (!state.tunnelEstablished ||
        state.activeProtocolCode != wireguardProtocolCode) {
      return;
    }
    final DateTime? latest = await ref
        .read(tunnelControllerProvider)
        .latestHandshake();
    if (mounted && latest != null && latest.millisecondsSinceEpoch > 0) {
      setState(() => _handshakeAge = DateTime.now().difference(latest));
    }
  }

  Future<void> _runLeakTest() async {
    setState(() => _running = true);
    await _readHandshake();
    final LeakReport report = await ref.read(leakTestProvider).run();
    if (mounted) {
      setState(() {
        _report = report;
        _running = false;
      });
    }
  }

  Future<void> _runSpeedTest() async {
    setState(() => _measuringSpeed = true);
    final SpeedReport speed = await ref.read(speedTestProvider).run();
    if (mounted) {
      setState(() {
        _speed = speed;
        _measuringSpeed = false;
      });
    }
  }

  Future<void> _runLossTest() async {
    setState(() => _measuringLoss = true);
    final LossReport loss = await ref.read(packetLossTestProvider).run();
    if (mounted) {
      setState(() {
        _loss = loss;
        _measuringLoss = false;
      });
    }
  }

  int? _lastTestMs(DevicesState state) {
    final String? profile = state.activeProfileCode;
    return profile == null
        ? null
        : state.delaysFor(state.connectedServerCode)[profile]?.milliseconds;
  }

  Future<void> _copyReport(DevicesState state) async {
    final AppText text = AppText.of(context);
    await Clipboard.setData(
      ClipboardData(
        text: diagnosticsReport(
          appVersion: kClientVersion,
          platform:
              '${Platform.operatingSystem} '
              '${Platform.operatingSystemVersion.split(' ').first}',
          connected: state.tunnelEstablished,
          localProxy: state.localProxy != null,
          server: state.tunnelEstablished
              ? state.selectedServer?.displayName
              : null,
          protocol: state.tunnelEstablished
              ? state.activeProfileCode ?? state.activeProtocolCode
              : null,
          lastTestMs: state.tunnelEstablished ? _lastTestMs(state) : null,
          handshakeAge: _handshakeAge,
          leaks: _report,
          speed: _speed,
          loss: _loss,
        ),
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(text.diagnosticsReportCopied)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final NebulaPalette palette = context.palette;
    final AppText text = AppText.of(context);
    final DevicesState state = ref.watch(devicesControllerProvider);
    final bool connected = state.tunnelEstablished;
    final LeakReport? report = _report;
    final SpeedReport? speed = _speed;
    final LossReport? loss = _loss;
    final int? lastTestMs = _lastTestMs(state);

    Widget runButton(String label, {required bool busy, VoidCallback? run}) =>
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: NebulaButton.secondary(
            label: label,
            busy: busy,
            onPressed: busy ? null : run,
          ),
        );

    return NebulaPage(
      title: text.sectionDiagnostics,
      children: <Widget>[
        const SizedBox(height: 12),
        NebulaButton.secondary(
          label: text.diagnosticsCopyReport,
          icon: Icons.content_copy,
          onPressed: () => _copyReport(state),
        ),
        NebulaSectionLabel(text.diagnosticsConnection),
        NebulaRowGroup(
          children: <Widget>[
            _Row(
              label: text.rowStatus,
              value: connected ? text.statusConnected : text.statusDisconnected,
              color: connected ? palette.blueText : palette.amberText,
            ),
            if (connected) ...<Widget>[
              _Row(
                label: text.rowServer,
                value: state.selectedServer?.displayName ?? '—',
              ),
              _Row(
                label: text.rowProtocol,
                value:
                    state.activeProfileCode ?? state.activeProtocolCode ?? '—',
              ),
              if (lastTestMs != null)
                _Row(label: text.diagnosticsLastTest, value: '$lastTestMs ms'),
              if (_handshakeAge != null)
                _Row(
                  label: text.statusHandshake,
                  value: text.diagnosticsSecondsAgo(_handshakeAge!.inSeconds),
                  color: _handshakeAge! > const Duration(minutes: 3)
                      ? palette.amberText
                      : null,
                ),
            ],
          ],
        ),
        NebulaSectionLabel(text.leakTest),
        _Small(text.leakTestIntro),
        if (!connected) ...<Widget>[
          const SizedBox(height: 16),
          NebulaNotice(
            text: text.leakTestNotConnected,
            kind: NebulaNoticeKind.warning,
          ),
        ],
        if (report != null) ...<Widget>[
          const SizedBox(height: 20),
          NebulaRowGroup(
            children: <Widget>[
              _Row(
                label: text.leakTestExit,
                value: report.exitCountry == null
                    ? text.leakTestUnreachable
                    : '${report.exitCountry} · ${report.exitAddress}',
                color: report.exitCountry == null ? palette.amberText : null,
              ),
              _Row(
                label: text.leakTestDns,
                value: switch (report.dns) {
                  DnsVerdict.clean => text.leakTestDnsClean,
                  DnsVerdict.forged => text.leakTestDnsForged,
                  DnsVerdict.failed => text.leakTestDnsFailed,
                },
                color: switch (report.dns) {
                  DnsVerdict.clean => palette.blueText,
                  DnsVerdict.forged => palette.redText,
                  DnsVerdict.failed => palette.amberText,
                },
              ),
              if (report.resolverNetwork != null)
                _Row(
                  label: text.leakTestResolver,
                  value: report.resolverNetwork!,
                ),
              _Row(
                label: text.leakTestIpv6,
                value: switch (report.ipv6) {
                  Ipv6Verdict.unavailable => text.leakTestIpv6Unavailable,
                  Ipv6Verdict.sameExit => text.leakTestIpv6Same,
                  Ipv6Verdict.leaking => text.leakTestIpv6Leaking(
                    report.ipv6Country ?? '?',
                  ),
                },
                color: report.ipv6 == Ipv6Verdict.leaking
                    ? palette.redText
                    : palette.blueText,
              ),
            ],
          ),
        ],
        runButton(text.leakTestRun, busy: _running, run: _runLeakTest),
        NebulaSectionLabel(text.speedTest),
        _Small(text.speedTestIntro),
        if (speed != null) ...<Widget>[
          const SizedBox(height: 20),
          NebulaRowGroup(
            children: <Widget>[
              for (final (String label, double? mbps) in <(String, double?)>[
                (text.speedTestDownload, speed.downloadMbps),
                (text.speedTestUpload, speed.uploadMbps),
              ])
                _Row(
                  label: label,
                  value: mbps == null
                      ? text.speedTestFailed
                      : text.speedTestMbps(formatMbps(mbps)),
                  color: mbps == null ? palette.amberText : null,
                ),
            ],
          ),
        ],
        runButton(text.speedTestRun, busy: _measuringSpeed, run: _runSpeedTest),
        NebulaSectionLabel(text.packetLoss),
        _Small(text.packetLossIntro),
        if (loss != null) ...<Widget>[
          const SizedBox(height: 20),
          NebulaRowGroup(
            children: <Widget>[
              _Row(
                label: text.packetLossLost,
                value: lossPercent(loss) == null
                    ? text.packetLossNotSent
                    : text.packetLossLostValue(
                        loss.sent - loss.received,
                        loss.sent,
                        lossPercent(loss)!,
                      ),
                color: (lossPercent(loss) ?? 100) > 2
                    ? palette.amberText
                    : null,
              ),
              if (loss.median != null)
                _Row(
                  label: text.packetLossDelay,
                  value: text.packetLossDelayValue(
                    loss.median!.inMilliseconds,
                    loss.jitter?.inMilliseconds ?? 0,
                  ),
                ),
            ],
          ),
        ],
        runButton(text.packetLossRun, busy: _measuringLoss, run: _runLossTest),
      ],
    );
  }
}

/// The design's small print under a section: 13/19, muted.
class _Small extends StatelessWidget {
  const _Small(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final NebulaPalette p = context.palette;
    final double side = p.look == NebulaLook.minimal ? 0 : 8;
    return Padding(
      padding: EdgeInsets.fromLTRB(side, 10, side, 0),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, height: 19 / 13, color: p.textMuted),
      ),
    );
  }
}

/// A result: the label, and the value at the row's end.
class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final NebulaPalette p = context.palette;
    return NebulaRow(
      title: label,
      // Plain text so it centres on the row; Copy report copies it all.
      trailing: Text(
        value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.end,
        style: TextStyle(
          fontSize: 14,
          height: 20 / 14,
          color: color ?? p.textMuted,
        ),
      ),
    );
  }
}
