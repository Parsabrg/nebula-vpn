import 'package:material_ui/material_ui.dart';
import 'package:zxing2/qrcode.dart';

/// The modules of [data]'s QR code, `true` for dark, row by row; ZXing,
/// the library the app's scanner reads them with.
List<List<bool>> qrModules(String data) {
  final matrix = Encoder.encode(data, ErrorCorrectionLevel.m).matrix!;
  return <List<bool>>[
    for (int y = 0; y < matrix.height; y++)
      <bool>[for (int x = 0; x < matrix.width; x++) matrix.get(x, y) == 1],
  ];
}

/// [data] as a QR code, dark on white whatever the theme (scanners expect
/// it), with the four-module quiet zone around it that they need.
class QrCodeView extends StatelessWidget {
  const QrCodeView({required this.data, this.size = 200, super.key});

  final String data;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _QrPainter(qrModules(data))),
  );
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.modules);

  final List<List<bool>> modules;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFFFFFFF),
    );
    final double cell = size.width / (modules.length + 8);
    final Paint dark = Paint()..color = const Color(0xFF000000);
    for (int y = 0; y < modules.length; y++) {
      for (int x = 0; x < modules[y].length; x++) {
        if (modules[y][x]) {
          canvas.drawRect(
            Rect.fromLTWH((x + 4) * cell, (y + 4) * cell, cell, cell),
            dark,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.modules != modules;
}
