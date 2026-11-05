import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_mobile/core/updates/release_signature.dart';

/// The real `SHA256SUMS.txt` of 0.1.34 and its signature, made with
/// `ssh-keygen -Y sign` by the release script.
List<int> _sums() =>
    File('test/core/updates/fixtures/SHA256SUMS-0.1.34.txt').readAsBytesSync();
String _signature() => File(
  'test/core/updates/fixtures/SHA256SUMS-0.1.34.txt.sig',
).readAsStringSync();

void main() {
  test('a release signed with the pinned key checks', () async {
    expect(
      await verifySshSignature(message: _sums(), armored: _signature()),
      isTrue,
    );
  });

  test('a changed checksum list does not', () async {
    final List<int> tampered = List<int>.of(_sums());
    tampered[0] = tampered[0] == 0x61 ? 0x62 : 0x61;
    expect(
      await verifySshSignature(message: tampered, armored: _signature()),
      isFalse,
    );
  });

  test('another namespace or another key does not', () async {
    expect(
      await verifySshSignature(
        message: _sums(),
        armored: _signature(),
        namespace: 'something-else',
      ),
      isFalse,
    );
    expect(
      await verifySshSignature(
        message: _sums(),
        armored: _signature(),
        publicKey:
            'AAAAC3NzaC1lZDI1NTE5AAAAIBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',
      ),
      isFalse,
    );
  });

  test('garbage is not a signature', () async {
    expect(
      await verifySshSignature(message: _sums(), armored: 'not a signature'),
      isFalse,
    );
  });

  test('the listed hash is found by file name', () {
    final String sums = utf8.decode(_sums());
    expect(
      listedSha256(sums, 'nebula-vpn-v0.1.34-android-arm64.apk'),
      '9a773ecdbbddf24cd3d2be4052631a347efe4f37456000e91c3c08bd7d5bec3d',
    );
    expect(listedSha256(sums, 'nebula-vpn-v0.1.34-android.apk'), isNull);
    expect(listedSha256('zz  a.apk', 'a.apk'), isNull);
  });
}
