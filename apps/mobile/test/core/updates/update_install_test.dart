import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_mobile/core/updates/update_check.dart';
import 'package:nebula_mobile/core/updates/update_install.dart';

/// Serves the release files by name; a name it lacks is a 404.
class _Release implements HttpClientAdapter {
  _Release(this.files);

  final Map<String, List<int>> files;
  final List<String> asked = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final String name = options.uri.pathSegments.last;
    asked.add(name);
    final List<int>? body = files[name];
    if (body == null) {
      return ResponseBody.fromString('', 404);
    }
    return ResponseBody.fromBytes(
      body,
      200,
      headers: <String, List<String>>{
        Headers.contentLengthHeader: <String>['${body.length}'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

final AvailableUpdate _update = AvailableUpdate(
  version: '0.1.34',
  page: Uri.parse('https://github.com/Parsabrg/vpn/releases/tag/v0.1.34'),
);

Map<String, List<int>> _signedRelease() => <String, List<int>>{
  'SHA256SUMS.txt': File(
    'test/core/updates/fixtures/SHA256SUMS-0.1.34.txt',
  ).readAsBytesSync(),
  'SHA256SUMS.txt.sig': File(
    'test/core/updates/fixtures/SHA256SUMS-0.1.34.txt.sig',
  ).readAsBytesSync(),
};

Future<UpdateFailure?> _install(_Release release) async {
  final Dio dio = Dio()..httpClientAdapter = release;
  try {
    await UpdateInstaller(dio: dio).install(_update);
    return null;
  } on UpdateInstallException catch (error) {
    return error.failure;
  }
}

void main() {
  final String name = releaseFileName('0.1.34');

  test(
    'a download whose hash is not the signed one is not installed',
    () async {
      final _Release release = _Release(<String, List<int>>{
        ..._signedRelease(),
        name: <int>[1, 2, 3],
      });

      expect(await _install(release), UpdateFailure.notGenuine);
      expect(release.asked, contains(name));
      expect(File('${Directory.systemTemp.path}/$name').existsSync(), isFalse);
    },
  );

  test(
    'a checksum list without a valid signature stops before downloading',
    () async {
      final Map<String, List<int>> files = _signedRelease();
      files['SHA256SUMS.txt'] = List<int>.of(files['SHA256SUMS.txt']!)
        ..[0] ^= 1;
      final _Release release = _Release(<String, List<int>>{
        ...files,
        name: <int>[1],
      });

      expect(await _install(release), UpdateFailure.notGenuine);
      expect(release.asked, isNot(contains(name)));
    },
  );

  test('a release that cannot be fetched is a download failure', () async {
    expect(
      await _install(_Release(<String, List<int>>{})),
      UpdateFailure.download,
    );
  });

  test('the file is chosen for the processor', () {
    expect(releaseFileName('1.2.3'), contains('1.2.3'));
  });
}
