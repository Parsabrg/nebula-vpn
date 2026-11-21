import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/color_tokens.dart';
import '../../core/widgets/nebula/nebula_controls.dart';
import '../../core/widgets/nebula/nebula_data.dart';
import '../../core/widgets/nebula/nebula_page.dart';
import '../../core/xray/xray_tunnel_controller.dart';
import '../../l10n/app_localizations.dart';

/// What the tunnel core has said about itself.
///
/// The one question this app could not answer was "it says connected but
/// nothing loads, why". Every other signal available to the user -- the
/// status text, the byte counters -- reports the tunnel as fine in exactly
/// that case, because from the app's side it is: the service is running and
/// the socket is open. What went wrong is in the core, and until now there
/// was no way to see it without a cable and adb.
///
/// The core runs at warning level, so this is faults, not a record of what
/// was visited. That is deliberate and worth keeping: raising it to info
/// would turn this screen into a list of every domain the person opened,
/// sitting on a device that may be inspected. Nothing here leaves the phone
/// on its own -- copying is a deliberate act, and there is no upload.
class ConnectionLogScreen extends ConsumerStatefulWidget {
  const ConnectionLogScreen({super.key});

  @override
  ConsumerState<ConnectionLogScreen> createState() =>
      _ConnectionLogScreenState();
}

class _ConnectionLogScreenState extends ConsumerState<ConnectionLogScreen> {
  List<String>? _lines;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final List<String> lines = await ref
          .read(xrayTunnelControllerProvider)
          .logs();
      if (mounted) {
        setState(() {
          _lines = lines;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error);
      }
    }
  }

  Future<void> _clear() async {
    await ref.read(xrayTunnelControllerProvider).clearLogs();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final NebulaPalette palette = context.palette;
    final AppText text = AppText.of(context);
    final List<String>? lines = _lines;
    final bool any = lines != null && lines.isNotEmpty;
    // "Nothing to report." and the reason under it, as the design's empty
    // state sets them: a title and its text.
    final List<String> empty = text.logEmpty.split('\n\n');

    return NebulaPage(
      title: text.connectionLog,
      trailing: IconButton(
        tooltip: text.ctaRefresh,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        icon: Icon(Icons.refresh, color: palette.textPrimary),
        onPressed: _load,
      ),
      children: <Widget>[
        if (_error != null)
          NebulaEmptyState(
            icon: Icons.receipt_long_outlined,
            title: text.logUnreadable,
          )
        else if (lines == null)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (lines.isEmpty)
          // An empty log is the healthy state, and saying so matters:
          // "nothing here" otherwise reads as the screen being broken.
          NebulaEmptyState(
            icon: Icons.receipt_long_outlined,
            title: empty.first,
            body: empty.length > 1 ? empty.sublist(1).join('\n\n') : null,
          )
        else
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(palette.radiusSm + 2),
              border: Border.all(color: palette.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final String line in lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: SelectableText(
                      line,
                      style: TextStyle(
                        fontFamily: 'GeistMono',
                        fontSize: 13,
                        height: 19 / 13,
                        color: _lineColor(line, palette),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        NebulaButton.secondary(
          label: text.copy,
          icon: Icons.content_copy,
          onPressed: any ? () => _copy(lines) : null,
        ),
        const SizedBox(height: 8),
        NebulaButton.text(label: text.clear, onPressed: any ? _clear : null),
      ],
    );
  }

  /// Errors carry the colour; everything else stays quiet.
  ///
  /// A log where every line is red is a log nobody reads, and the point of
  /// opening this screen is to find the one line that matters among the
  /// routine ones.
  static Color _lineColor(String line, NebulaPalette palette) {
    final String lowered = line.toLowerCase();
    if (lowered.contains('error') ||
        lowered.contains('failed') ||
        lowered.contains('refused')) {
      return palette.redText;
    }
    if (lowered.contains('warning')) {
      return palette.amberText;
    }
    return palette.textMuted;
  }

  Future<void> _copy(List<String> lines) async {
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(AppText.of(context).logCopied)));
    }
  }
}
