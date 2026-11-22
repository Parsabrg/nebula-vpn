import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/color_tokens.dart';
import '../../core/updates/update_check.dart';
import '../../core/updates/update_install.dart';
import '../../core/widgets/nebula/nebula_controls.dart';
import '../../core/widgets/nebula/nebula_feedback.dart';
import '../../core/wireguard/native_tunnel_channel.dart';
import '../../l10n/app_localizations.dart';

/// Offers [update]: "New version available" with its notes, Later and Update.
/// Update downloads it on a page of its own (Android and Windows: checked
/// against the signed release, then installed); elsewhere the release page
/// opens. Later keeps the pop-up from coming back for this version.
Future<void> offerUpdate(
  BuildContext context,
  WidgetRef ref,
  AvailableUpdate update,
) async {
  final AppText text = AppText.of(context);
  final NebulaPalette p = context.palette;
  final bool? accepted = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => NebulaDialog(
      title: text.updateAvailableTitle,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'v${update.version}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
              color: p.blueText,
            ),
          ),
          for (final String note in update.notes)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '•  $note',
                style: TextStyle(
                  fontSize: 15,
                  height: 22 / 15,
                  color: p.textMuted,
                ),
              ),
            ),
        ],
      ),
      actions: <Widget>[
        NebulaButton.secondary(
          label: text.updateLater,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        NebulaButton(
          label: text.updateNow,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  if (accepted != true) {
    await ref.read(dismissedUpdateProvider.notifier).dismiss(update.version);
    return;
  }
  if (!installsUpdatesItself) {
    await const NativeTunnelChannel().openUrl(update.page);
    return;
  }
  if (!context.mounted) {
    return;
  }
  await Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (BuildContext context) => UpdateDownloadPage(
        update: update,
        installer: ref.read(updateInstallerProvider),
      ),
    ),
  );
}

/// The download: a ring with the percentage and megabytes, then the check
/// and the installer. Close stops the download.
class UpdateDownloadPage extends StatefulWidget {
  const UpdateDownloadPage({
    required this.update,
    required this.installer,
    super.key,
  });

  final AvailableUpdate update;
  final UpdateInstaller installer;

  @override
  State<UpdateDownloadPage> createState() => _UpdateDownloadPageState();
}

class _UpdateDownloadPageState extends State<UpdateDownloadPage> {
  CancelToken _cancel = CancelToken();
  int _received = 0;
  int _total = 0;
  bool _running = false;
  UpdateFailure? _failure;

  @override
  void initState() {
    super.initState();
    _install();
  }

  @override
  void dispose() {
    _cancel.cancel();
    super.dispose();
  }

  Future<void> _install() async {
    _cancel = CancelToken();
    setState(() {
      _running = true;
      _failure = null;
      _received = 0;
      _total = 0;
    });
    try {
      await widget.installer.install(
        widget.update,
        cancel: _cancel,
        onProgress: (int received, int total) {
          if (mounted) {
            setState(() {
              _received = received;
              _total = total;
            });
          }
        },
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on UpdateInstallException catch (error) {
      if (mounted && !_cancel.isCancelled) {
        setState(() {
          _running = false;
          _failure = error.failure;
        });
      }
    }
  }

  static String _mb(int bytes) => (bytes / 1e6).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final AppText text = AppText.of(context);
    final NebulaPalette p = context.palette;
    final double? fraction = _total > 0 ? _received / _total : null;
    final bool checking = _running && fraction != null && fraction >= 1;
    final String? status = switch (_failure) {
      UpdateFailure.notGenuine => text.updateNotGenuine,
      UpdateFailure.download => text.updateDownloadFailed,
      UpdateFailure.install => text.updateInstallFailed,
      null => checking ? text.updateChecking : null,
    };
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                text.updateDownloadingTitle,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: p.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Nebula · v${widget.update.version}',
                style: TextStyle(fontSize: 15, color: p.textMuted),
              ),
              Expanded(
                child: Center(
                  child: SizedBox.square(
                    dimension: 220,
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        CircularProgressIndicator(
                          value: _failure != null ? 0 : fraction,
                          strokeWidth: 10,
                          strokeCap: StrokeCap.round,
                          color: p.blue,
                          backgroundColor: p.hairline,
                        ),
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                '${((fraction ?? 0) * 100).floor()} %',
                                style: TextStyle(
                                  fontSize: 44,
                                  fontWeight: FontWeight.w600,
                                  color: p.textPrimary,
                                ),
                              ),
                              if (_total > 0)
                                Text(
                                  text.updateSize(_mb(_received), _mb(_total)),
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: p.textMuted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (status != null) ...<Widget>[
                Text(
                  status,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 22 / 15,
                    color: _failure == null ? p.textMuted : p.redText,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (_failure != null) ...<Widget>[
                NebulaButton(label: text.ctaTryAgain, onPressed: _install),
                const SizedBox(height: 10),
                NebulaButton.secondary(
                  label: text.updateOpenPage,
                  onPressed: () {
                    const NativeTunnelChannel().openUrl(widget.update.page);
                    Navigator.of(context).pop();
                  },
                ),
                const SizedBox(height: 10),
              ],
              NebulaButton.secondary(
                label: text.close,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
