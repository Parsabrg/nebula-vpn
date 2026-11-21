import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../wireguard/native_tunnel_channel.dart';

/// How long a copied credential stays on the clipboard.
const Duration sensitiveClipboardLifetime = Duration(minutes: 1);

/// Copies a credential -- a subscription link, a client's ID -- so it is not
/// left lying about (review S-07): on Android 13 and later it is marked
/// sensitive, so the clipboard preview and keyboards do not show it, and on
/// every platform it is cleared after [sensitiveClipboardLifetime] if it is
/// still what was copied.
Future<void> copySensitive(String text) async {
  if (Platform.isAndroid) {
    try {
      await const NativeTunnelChannel().copySensitive(text);
    } on Object {
      await Clipboard.setData(ClipboardData(text: text));
    }
  } else {
    await Clipboard.setData(ClipboardData(text: text));
  }
  unawaited(
    Future<void>.delayed(sensitiveClipboardLifetime, () async {
      try {
        // Null on Android while another app is in front; then it stays,
        // marked sensitive, until something else is copied.
        final ClipboardData? now = await Clipboard.getData(
          Clipboard.kTextPlain,
        );
        if (now?.text == text) {
          await Clipboard.setData(const ClipboardData(text: ''));
        }
      } on Object {
        // Nothing to clear.
      }
    }),
  );
}
