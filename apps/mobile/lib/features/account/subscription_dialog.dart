import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/account/account_repository.dart';
import '../../core/network/error_copy.dart';
import '../../core/theme/color_tokens.dart';
import '../../l10n/app_localizations.dart';

/// A subscription link for apps such as Streisand, V2Box or Hiddify: how an
/// iPhone or iPad uses this account, as Nebula has no iOS app.
Future<void> showSubscriptionLink(BuildContext context, WidgetRef ref) =>
    showDialog<void>(
      context: context,
      builder: (BuildContext context) =>
          _SubscriptionDialog(repository: ref.read(accountRepositoryProvider)),
    );

class _SubscriptionDialog extends StatefulWidget {
  const _SubscriptionDialog({required this.repository});

  final AccountRepository repository;

  @override
  State<_SubscriptionDialog> createState() => _SubscriptionDialogState();
}

class _SubscriptionDialogState extends State<_SubscriptionDialog> {
  String? _link;
  String? _error;
  bool _busy = false;

  Future<void> _make() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final String link = await widget.repository.newSubscriptionLink();
      if (mounted) {
        setState(() => _link = link);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = userFacingErrorMessage(error, AppText.of(context)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppText text = AppText.of(context);
    final NebulaPalette palette = context.palette;
    final String? link = _link;
    return AlertDialog(
      title: Text(text.subscriptionTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            link == null ? text.subscriptionIntro : text.subscriptionReady,
            style: TextStyle(color: palette.textMuted, height: 1.5),
          ),
          if (link != null) ...<Widget>[
            const SizedBox(height: 12),
            SelectableText(link, style: TextStyle(color: palette.textPrimary)),
          ],
          if (_error case final String error) ...<Widget>[
            const SizedBox(height: 12),
            Text(error, style: TextStyle(color: palette.amberText)),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(text.close),
        ),
        if (link == null)
          FilledButton(
            onPressed: _busy ? null : _make,
            child: Text(text.subscriptionMake),
          )
        else
          FilledButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(text.subscriptionCopied)));
            },
            child: Text(text.subscriptionCopy),
          ),
      ],
    );
  }
}
