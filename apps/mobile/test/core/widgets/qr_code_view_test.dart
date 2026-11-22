import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_mobile/core/widgets/qr_code_view.dart';
import 'package:nebula_mobile/features/pairing/qr_scan.dart';

void main() {
  test("the app's own scanner reads the code back", () {
    const String link =
        'https://cdn.example.org/v1/sub/Zk3q9-2bQx7RmV0aLwN4sYtE8uPcJ1hDgF6oKiU5nBy';
    final List<List<bool>> modules = qrModules(link);
    const int scale = 4;
    final int side = (modules.length + 8) * scale;
    final Uint8List luma = Uint8List(side * side)
      ..fillRange(0, side * side, 255);
    for (int y = 0; y < modules.length; y++) {
      for (int x = 0; x < modules.length; x++) {
        if (!modules[y][x]) continue;
        for (int dy = 0; dy < scale; dy++) {
          final int row = ((y + 4) * scale + dy) * side;
          luma.fillRange(row + (x + 4) * scale, row + (x + 5) * scale, 0);
        }
      }
    }
    expect(decodeQr(luma, side, side, side), link);
  });
}
