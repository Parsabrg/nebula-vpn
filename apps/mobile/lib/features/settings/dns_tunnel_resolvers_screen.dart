import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dns_tunnel_resolvers.dart';
import '../../core/network/dns_tunnel_sync.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/look.dart';
import '../../core/widgets/nebula/nebula_controls.dart';
import '../../core/widgets/nebula/nebula_data.dart';
import '../../core/widgets/nebula/nebula_feedback.dart';
import '../../core/widgets/nebula/nebula_page.dart';
import '../../core/widgets/nebula/nebula_rows.dart';
import '../../l10n/app_localizations.dart';

/// "Wi-Fi", "mobile data (43211)" or "this network", for a network key.
String dnsTunnelNetworkName(AppText text, String? network) {
  if (network == 'wifi') {
    return text.dnsTunnelResolversWifi;
  }
  if (network != null && network.startsWith('mobile')) {
    final String carrier = network.replaceFirst(RegExp('^mobile-?'), '');
    return text.dnsTunnelResolversMobile(carrier.isEmpty ? '?' : carrier);
  }
  return text.dnsTunnelResolversOther;
}

/// The DNS tunnel's resolvers (Android): saved sets, one in use, each
/// tested from the network the phone is on, one working list per network.
class DnsTunnelResolversScreen extends ConsumerStatefulWidget {
  const DnsTunnelResolversScreen({super.key});

  @override
  ConsumerState<DnsTunnelResolversScreen> createState() =>
      _DnsTunnelResolversScreenState();
}

class _DnsTunnelResolversScreenState
    extends ConsumerState<DnsTunnelResolversScreen> {
  final TextEditingController _field = TextEditingController();
  String? _message;
  bool _messageIsError = false;

  DnsTunnelResolvers get _resolvers => ref.read(dnsTunnelResolversProvider);

  @override
  void initState() {
    super.initState();
    _showActive();
    _resolvers.currentNetwork().ignore();
  }

  /// The set in use in the field; the bundled list read-only.
  Future<void> _showActive() async {
    final String text = _resolvers.source ?? await _resolvers.builtInList();
    if (mounted) {
      setState(() => _field.text = text);
    }
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _say(String message, {bool error = false}) {
    if (mounted) {
      setState(() {
        _message = message;
        _messageIsError = error;
      });
    }
  }

  /// Saves the field into the set in use, then the tunnel's details; null,
  /// with the reason, if unusable.
  Future<DnsTunnelDetails?> _prepare(AppText text) async {
    // Built-in in use and the field changed: what was typed becomes a new
    // set, and the built-in list stays as it is.
    final bool edited =
        _resolvers.custom || _field.text != await _resolvers.builtInList();
    if (edited) {
      final List<String> resolvers = DnsTunnelResolvers.parse(_field.text);
      if (resolvers.isEmpty) {
        _say(text.dnsTunnelResolversInvalid, error: true);
        return null;
      }
      await _resolvers.saveSource(
        resolvers,
        newName: text.dnsTunnelResolversNewSetName,
      );
    }
    final DnsTunnelDetails? details = await ref
        .read(dnsTunnelStoreProvider)
        .read();
    if (details == null) {
      _say(text.dnsTunnelResolversUnavailable, error: true);
    }
    return details;
  }

  Future<void> _run(Future<int?> Function(DnsTunnelDetails) test) async {
    final AppText text = AppText.of(context);
    setState(() => _message = null);
    try {
      // Inside the try: a failure here is said, not swallowed.
      final DnsTunnelDetails? details = await _prepare(text);
      if (details == null) {
        return;
      }
      final int? working = await test(details);
      final int tested = _resolvers.progress?.tested ?? 0;
      if (working == null) {
        _say(text.dnsTunnelResolversFullScanWifiOnly, error: true);
      } else if (working > 0) {
        _say(text.dnsTunnelResolversResult(working, tested));
      } else {
        _say(text.dnsTunnelResolversNoneWork, error: true);
      }
    } catch (error) {
      _say(text.dnsTunnelResolversFailed('$error'), error: true);
    }
  }

  Future<void> _select(String? name) async {
    await _resolvers.select(name);
    setState(() => _message = null);
    await _showActive();
  }

  Future<void> _saveAs() async {
    final AppText text = AppText.of(context);
    final List<String> resolvers = DnsTunnelResolvers.parse(_field.text);
    if (resolvers.isEmpty) {
      _say(text.dnsTunnelResolversInvalid, error: true);
      return;
    }
    final TextEditingController name = TextEditingController(
      text: _resolvers.freeName(text.dnsTunnelResolversNewSetName),
    );
    final String? chosen = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(text.dnsTunnelResolversSaveAs),
        content: TextField(
          controller: name,
          autofocus: true,
          decoration: InputDecoration(
            labelText: text.dnsTunnelResolversSetName,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(text.dnsTunnelResolversCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(name.text.trim()),
            child: Text(text.dnsTunnelResolversSave),
          ),
        ],
      ),
    );
    name.dispose();
    if (chosen == null || chosen.isEmpty) {
      return;
    }
    await _resolvers.saveAs(chosen, resolvers);
    await _showActive();
  }

  Future<void> _delete() async {
    final String? name = _resolvers.active;
    if (name != null) {
      await _resolvers.deleteSet(name);
      await _showActive();
    }
  }

  @override
  Widget build(BuildContext context) {
    final NebulaPalette palette = context.palette;
    final AppText text = AppText.of(context);
    final DnsTunnelResolvers resolvers = ref.watch(dnsTunnelResolversProvider);

    final double inset = palette.look == NebulaLook.minimal ? 0 : 4;
    TextStyle body(Color color) =>
        TextStyle(fontSize: 15, height: 22 / 15, color: color);
    final TextStyle small = TextStyle(
      fontSize: 13,
      height: 19 / 13,
      color: palette.textMuted,
    );

    return NebulaPage(
      title: text.dnsTunnelResolvers,
      children: <Widget>[
        ListenableBuilder(
          listenable: resolvers,
          builder: (BuildContext context, _) {
            final String? network = resolvers.network;
            final String networkName = dnsTunnelNetworkName(text, network);
            final List<String> working = network == null
                ? const <String>[]
                : resolvers.workingOn(network);
            final DnsTunnelScanKind? scanning = resolvers.scanning;
            final DnsTunnelScanProgress? progress = resolvers.progress;
            final bool busy = scanning != null;
            final String? active = resolvers.active;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: EdgeInsets.fromLTRB(inset, 12, inset, 0),
                  child: Text(
                    text.dnsTunnelResolversIntro,
                    style: body(palette.textMuted),
                  ),
                ),
                const SizedBox(height: 20),
                NebulaRowGroup(
                  children: <Widget>[
                    NebulaRow(
                      title: text.dnsTunnelResolversSet,
                      subtitle: active ?? text.dnsTunnelResolversBuiltIn,
                      trailing: NebulaRowTrailing.chevron(context),
                      onTap: busy
                          ? null
                          : () async {
                              // '' stands for the built-in set, so a
                              // cancelled dialog (null) can be told apart.
                              final String? picked =
                                  await showNebulaChoice<String>(
                                    context,
                                    title: text.dnsTunnelResolversSet,
                                    selected: active ?? '',
                                    options: <(String, String)>[
                                      ('', text.dnsTunnelResolversBuiltIn),
                                      for (final String name
                                          in resolvers.setNames)
                                        (name, name),
                                    ],
                                  );
                              if (picked != null) {
                                await _select(picked.isEmpty ? null : picked);
                              }
                            },
                    ),
                  ],
                ),
                Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(
                    palette.look == NebulaLook.minimal ? 0 : 8,
                    10,
                    0,
                    0,
                  ),
                  child: Text(
                    working.isEmpty
                        ? text.dnsTunnelResolversNoneHere(networkName)
                        : text.dnsTunnelResolversHere(
                            networkName,
                            working.length,
                            network == null
                                ? 0
                                : resolvers.iranCountOn(network),
                          ),
                    style: small,
                  ),
                ),
                const SizedBox(height: 16),
                NebulaLabeledField(
                  label: text.dnsTunnelResolversField,
                  child: TextField(
                    controller: _field,
                    enabled: !busy,
                    minLines: 3,
                    // Short: a long list scrolls inside it.
                    maxLines: 6,
                    keyboardType: TextInputType.multiline,
                    autocorrect: false,
                    enableSuggestions: false,
                    // Addresses read left to right in every language.
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontFamily: 'GeistMono',
                      fontSize: 14,
                      height: 20 / 14,
                    ),
                    decoration: const InputDecoration(
                      hintText: '1.2.3.4\n5.6.7.8:53\n[2001:db8::1]:53',
                    ),
                  ),
                ),
                if (_message != null) ...<Widget>[
                  const SizedBox(height: 16),
                  NebulaNotice(
                    text: _message!,
                    kind: _messageIsError
                        ? NebulaNoticeKind.warning
                        : NebulaNoticeKind.success,
                  ),
                ],
                if (busy && progress != null) ...<Widget>[
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          <String>[
                            if (scanning == DnsTunnelScanKind.growing)
                              text.dnsTunnelResolversGrowing,
                            text.dnsTunnelResolversProgress(
                              progress.tested,
                              progress.total,
                              progress.valid.length,
                            ),
                          ].join('\n'),
                          style: body(palette.textPrimary),
                        ),
                      ),
                      NebulaButton.rowAction(
                        label: text.dnsTunnelResolversStop,
                        onPressed: resolvers.stop,
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                NebulaButton(
                  label: text.dnsTunnelResolversTest,
                  onPressed: busy ? null : () => _run(resolvers.quickTest),
                ),
                const SizedBox(height: 10),
                NebulaButton.secondary(
                  label: text.dnsTunnelResolversFullScan,
                  onPressed: busy || !DnsTunnelResolvers.unmetered(network)
                      ? null
                      : () => _run(resolvers.fullScan),
                ),
                if (!DnsTunnelResolvers.unmetered(network))
                  Padding(
                    padding: EdgeInsets.fromLTRB(inset, 6, inset, 0),
                    child: Text(
                      text.dnsTunnelResolversFullScanWifiOnly,
                      style: small,
                    ),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    NebulaButton.text(
                      label: text.dnsTunnelResolversSaveAs,
                      onPressed: busy ? null : _saveAs,
                    ),
                    if (active != null)
                      NebulaButton.text(
                        label: text.dnsTunnelResolversDelete,
                        danger: true,
                        onPressed: busy ? null : _delete,
                      ),
                  ],
                ),
                if (working.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: BorderRadius.circular(palette.radiusSm + 2),
                      border: Border.all(color: palette.hairline),
                    ),
                    child: Text(
                      working.take(30).join('\n'),
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        fontFamily: 'GeistMono',
                        fontSize: 13,
                        height: 19 / 13,
                        color: palette.textMuted,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
