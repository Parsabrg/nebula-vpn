import 'dart:io';

import 'package:flutter/services.dart';

import 'auth/auth_repository.dart';

/// Kept in sync with `pubspec.yaml`'s `version:` field, which a test in
/// test/core/app_info_test.dart enforces -- this drifted four releases
/// behind while the comment claimed otherwise, and the app reported 0.1.0
/// to the API the whole time. No
/// `package_info_plus` dependency this phase -- see Phase 1.7a's plan doc
/// for the dependency-discipline rationale.
const String kClientVersion = '0.1.37';

/// `dart:io`'s `Platform.operatingSystem` is sufficient to answer this
/// API's `platform` enum without a plugin -- this app has no other target
/// platforms in Phase 1.
DevicePlatform get currentDevicePlatform =>
    Platform.isAndroid ? DevicePlatform.android : DevicePlatform.windows;

/// What this device is called in Devices: the phone's maker and model on
/// Android, the computer's name on Windows and Linux (Linux marked, as the
/// server files it under Windows). So two devices can be told apart; the
/// name is the person's to change there.
Future<String> readDeviceName() async {
  String? name;
  try {
    name = Platform.isAndroid
        ? await const MethodChannel(
            'org.nebulavpn/wireguard_tunnel',
          ).invokeMethod<String>('deviceModel')
        : Platform.isLinux
        ? '${Platform.localHostname} (Linux)'
        : Platform.localHostname;
  } on Object {
    name = null;
  }
  name = name?.trim();
  if (name == null || name.isEmpty) {
    return '${Platform.operatingSystem} device';
  }
  return name.length > 80 ? name.substring(0, 80) : name;
}

/// The name every device was given before [readDeviceName]: replaced by the
/// real one the next time the app sees it in Devices.
bool isPlaceholderDeviceName(String name) =>
    RegExp(r'^(android|windows|linux) device$').hasMatch(name);
