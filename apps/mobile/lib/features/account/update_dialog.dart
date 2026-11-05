import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/updates/update_check.dart';
import '../../core/updates/update_install.dart';
import '../../core/wireguard/native_tunnel_channel.dart';
import '../../l10n/app_localizations.dart';

/// Offers [update]: on Android and Windows it is downloaded, checked against
/// the signed release and installed; elsewhere the release page opens.
Future<void> offerUpdate(
  BuildContext context,
  WidgetRef ref,
  AvailableUpdate update,
) async {
  if (!installsUpdatesItself) {
    await const NativeTunnelChannel().openUrl(update.page);
    return;
  }
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => _UpdateDialog(
      update: update,
      installer: ref.read(updateInstallerProvider),
    ),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.update, required this.installer});

  final AvailableUpdate update;
  final UpdateInstaller installer;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _running = false;
  double? _progress;
  UpdateFailure? _failure;

  Future<void> _install() async {
    setState(() {
      _running = true;
      _failure = null;
      _progress = null;
    });
    try {
      await widget.installer.install(
        widget.update,
        onProgress: (double progress) {
          if (mounted) {
            setState(() => _progress = progress);
          }
        },
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on UpdateInstallException catch (error) {
      if (mounted) {
        setState(() {
          _running = false;
          _failure = error.failure;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppText text = AppText.of(context);
    final String body = switch (_failure) {
      UpdateFailure.notGenuine => text.updateNotGenuine,
      UpdateFailure.download => text.updateDownloadFailed,
      UpdateFailure.install => text.updateInstallFailed,
      null => _running ? text.updateDownloading : text.updateInstallBody,
    };
    return AlertDialog(
      title: Text(text.updateInstallTitle(widget.update.version)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(body),
          if (_running) ...<Widget>[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress),
          ],
        ],
      ),
      actions: <Widget>[
        if (!_running)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(text.cancel),
          ),
        if (!_running && _failure != null)
          TextButton(
            onPressed: () {
              const NativeTunnelChannel().openUrl(widget.update.page);
              Navigator.of(context).pop();
            },
            child: Text(text.updateOpenPage),
          ),
        if (!_running)
          TextButton(
            onPressed: _install,
            child: Text(
              _failure == null ? text.updateInstall : text.ctaTryAgain,
            ),
          ),
      ],
    );
  }
}
