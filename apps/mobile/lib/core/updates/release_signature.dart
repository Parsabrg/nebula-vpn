import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// The key releases are signed with, as in `docs/release-signers` (an
/// `ssh-ed25519` public key). Pinned here: a download is installed only when
/// `SHA256SUMS.txt.sig` checks against it.
const String releaseSignerKey =
    'AAAAC3NzaC1lZDI1NTE5AAAAIO3oob4Ghi021R3V+1+yMWxEOfNT4OQ1HwsuRsbTKdv1';

/// The namespace `ssh-keygen -Y sign -n` was given.
const String releaseSignatureNamespace = 'nebula-release';

/// Whether [armored] (an `ssh-keygen -Y sign` signature) is [message] signed
/// by [publicKey] (base64 of an `ssh-ed25519` key) under [namespace].
///
/// The SSHSIG format (openssh PROTOCOL.sshsig): the signature covers
/// "SSHSIG", the namespace, a reserved string, the hash algorithm and the
/// message's hash under it -- never the message itself.
Future<bool> verifySshSignature({
  required List<int> message,
  required String armored,
  String publicKey = releaseSignerKey,
  String namespace = releaseSignatureNamespace,
}) async {
  try {
    final String body = armored
        .split('\n')
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty && !line.startsWith('-----'))
        .join();
    final _Reader blob = _Reader(base64.decode(body));
    if (utf8.decode(blob.bytes(6)) != 'SSHSIG' || blob.uint32() != 1) {
      return false;
    }
    final Uint8List signer = blob.string();
    final Uint8List pinned = base64.decode(publicKey);
    if (!_same(signer, pinned)) {
      return false;
    }
    final Uint8List signedNamespace = blob.string();
    final Uint8List reserved = blob.string();
    final Uint8List hashName = blob.string();
    final _Reader signature = _Reader(blob.string());
    if (utf8.decode(signedNamespace) != namespace ||
        utf8.decode(signature.string()) != 'ssh-ed25519') {
      return false;
    }
    final HashAlgorithm hash = switch (utf8.decode(hashName)) {
      'sha512' => Sha512(),
      'sha256' => Sha256(),
      _ => throw const FormatException('hash'),
    };
    final Uint8List digest = Uint8List.fromList(
      (await hash.hash(message)).bytes,
    );
    final BytesBuilder signed = BytesBuilder()
      ..add(utf8.encode('SSHSIG'))
      ..add(_string(signedNamespace))
      ..add(_string(reserved))
      ..add(_string(hashName))
      ..add(_string(digest));
    final _Reader key = _Reader(pinned);
    if (utf8.decode(key.string()) != 'ssh-ed25519') {
      return false;
    }
    return await Ed25519().verify(
      signed.toBytes(),
      signature: Signature(
        signature.string(),
        publicKey: SimplePublicKey(key.string(), type: KeyPairType.ed25519),
      ),
    );
  } on Object {
    return false;
  }
}

/// The SHA-256 `SHA256SUMS.txt` lists for [fileName], lower-case hex, or
/// null. Lines are `<hash>  <name>` as `sha256sum` writes them.
String? listedSha256(String sums, String fileName) {
  for (final String line in const LineSplitter().convert(sums)) {
    final List<String> parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length == 2) {
      final String name = parts[1].startsWith('*')
          ? parts[1].substring(1)
          : parts[1];
      if (name == fileName && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(parts[0])) {
        return parts[0].toLowerCase();
      }
    }
  }
  return null;
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

Uint8List _string(List<int> value) {
  final ByteData length = ByteData(4)..setUint32(0, value.length);
  return Uint8List.fromList(<int>[...length.buffer.asUint8List(), ...value]);
}

class _Reader {
  _Reader(this._data);

  final Uint8List _data;
  int _at = 0;

  Uint8List bytes(int count) {
    if (_at + count > _data.length) {
      throw const FormatException('short');
    }
    final Uint8List out = Uint8List.sublistView(_data, _at, _at + count);
    _at += count;
    return out;
  }

  int uint32() => ByteData.sublistView(bytes(4)).getUint32(0);

  Uint8List string() => bytes(uint32());
}
