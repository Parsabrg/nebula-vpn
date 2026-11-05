import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../wireguard/native_tunnel_channel.dart';
import 'release_signature.dart';
import 'update_check.dart';

/// Why an update was not installed.
enum UpdateFailure {
  /// The signed checksum list did not check against the pinned key, or the
  /// download's hash is not the one it lists. Nothing was installed.
  notGenuine,

  /// It could not be downloaded (offline, GitHub blocked, interrupted).
  download,

  /// The system installer could not be opened.
  install,
}

class UpdateInstallException implements Exception {
  const UpdateInstallException(this.failure);

  final UpdateFailure failure;

  @override
  String toString() => 'UpdateInstallException($failure)';
}

/// Whether this platform installs updates itself: Android hands the APK to
/// the system installer, Windows runs the setup program. Elsewhere the
/// release page is opened as before.
bool get installsUpdatesItself => Platform.isAndroid || Platform.isWindows;

/// The release file for this device: the APK for its processor (the
/// universal one when that is unknown), or the Windows installer.
String releaseFileName(String version, {String? androidAbi}) {
  if (!Platform.isAndroid) {
    return 'nebula-vpn-v$version-windows-x64-setup.exe';
  }
  final String abi = switch (androidAbi) {
    'arm64-v8a' => 'arm64',
    'armeabi-v7a' => 'arm',
    'x86_64' => 'x64',
    _ => 'universal',
  };
  return 'nebula-vpn-v$version-android-$abi.apk';
}

/// Downloads an update, checks it, and starts its installer.
///
/// The files come from the release on GitHub (through the tunnel when it is
/// up: this app's own traffic goes through it). `SHA256SUMS.txt` must carry a
/// signature by the pinned release key, and the download the hash it lists;
/// otherwise the file is deleted and nothing is installed.
class UpdateInstaller {
  UpdateInstaller({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(minutes: 2),
            ),
          );

  /// Its own client, not the API's: nothing about the session goes to GitHub.
  final Dio _dio;
  final NativeTunnelChannel _channel = const NativeTunnelChannel();

  Future<void> install(
    AvailableUpdate update, {
    void Function(double progress)? onProgress,
  }) async {
    final String base =
        'https://github.com/$releasesRepository/releases/download/v${update.version}/';
    final String name = releaseFileName(
      update.version,
      androidAbi: Platform.isAndroid ? await _channel.primaryAbi() : null,
    );
    final String folder = Platform.isAndroid
        ? await _channel.updateDirectory()
        : Directory.systemTemp.path;
    final File file = File('$folder${Platform.pathSeparator}$name');

    final String sums;
    final String signature;
    try {
      sums = await _text('${base}SHA256SUMS.txt');
      signature = await _text('${base}SHA256SUMS.txt.sig');
    } on Object {
      throw const UpdateInstallException(UpdateFailure.download);
    }
    final String? expected = listedSha256(sums, name);
    if (expected == null ||
        !await verifySshSignature(
          message: utf8.encode(sums),
          armored: signature,
        )) {
      throw const UpdateInstallException(UpdateFailure.notGenuine);
    }

    try {
      await Directory(folder).create(recursive: true);
      if (Platform.isAndroid) {
        // The folder holds only updates: an earlier one is no longer needed.
        await for (final FileSystemEntity old in Directory(folder).list()) {
          await old.delete(recursive: true);
        }
      }
      await _dio.download(
        '$base$name',
        file.path,
        onReceiveProgress: (int received, int total) {
          if (total > 0) {
            onProgress?.call(received / total);
          }
        },
      );
    } on Object {
      await _delete(file);
      throw const UpdateInstallException(UpdateFailure.download);
    }
    if (await _sha256(file) != expected) {
      await _delete(file);
      throw const UpdateInstallException(UpdateFailure.notGenuine);
    }

    try {
      if (Platform.isAndroid) {
        await _channel.installApk(file.path);
      } else {
        // The installer closes the running app itself before replacing it.
        await Process.start(
          file.path,
          const <String>[],
          mode: ProcessStartMode.detached,
        );
      }
    } on Object {
      throw const UpdateInstallException(UpdateFailure.install);
    }
  }

  Future<String> _text(String url) async {
    final Response<String> response = await _dio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    return response.data ?? '';
  }

  static Future<String> _sha256(File file) async {
    final HashSink sink = Sha256().newHashSink();
    await for (final List<int> chunk in file.openRead()) {
      sink.add(chunk);
    }
    sink.close();
    final Hash hash = await sink.hash();
    return hash.bytes
        .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static Future<void> _delete(File file) async {
    try {
      await file.delete();
    } on Object {
      // Already gone.
    }
  }
}

final updateInstallerProvider = Provider<UpdateInstaller>(
  (Ref ref) => UpdateInstaller(),
);
