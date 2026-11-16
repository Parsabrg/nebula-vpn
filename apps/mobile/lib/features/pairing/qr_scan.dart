import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zxing2/qrcode.dart';

import '../../core/theme/color_tokens.dart';
import '../../core/theme/look.dart';
import '../../core/widgets/nebula/nebula_page.dart';
import '../../l10n/app_localizations.dart';

/// Opens a camera scanner and completes with the first QR code's text, or
/// `null` when the person closes it without scanning one.
typedef QrScan = Future<String?> Function(BuildContext context);

/// The scanner the pairing screen opens. A provider so tests can put a fake
/// in its place: there is no camera in a widget test.
final qrScanProvider = Provider<QrScan>((Ref ref) => _scanWithCamera);

/// Android only. Windows has no camera to point at a screen and pastes the
/// link, as before.
bool get qrScanAvailable =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

Future<String?> _scanWithCamera(BuildContext context) => Navigator.of(
  context,
).push<String>(MaterialPageRoute<String>(builder: (_) => const _QrScanPage()));

/// The text of a QR code in a camera frame's brightness (Y) plane, or null
/// when there is none to read.
///
/// ZXing, in Dart: the scanner this replaced bundled Google's closed ML Kit
/// -- with parts of Play Services and Firebase -- into an app licensed
/// under the GPL and built for privacy.
@visibleForTesting
String? decodeQr(Uint8List luma, int width, int height, int rowStride) {
  try {
    final BinaryBitmap bitmap = BinaryBitmap(
      HybridBinarizer(_Luma(luma, width, height, rowStride)),
    );
    return QRCodeReader().decode(bitmap).text;
  } on Exception {
    return null;
  }
}

/// A camera frame's Y plane as ZXing reads it: one byte of brightness per
/// pixel, rows [_stride] bytes apart (the camera may pad them).
class _Luma extends LuminanceSource {
  _Luma(this._y, int width, int height, this._stride) : super(width, height);

  final Uint8List _y;
  final int _stride;

  @override
  Int8List getRow(int y, Int8List? row) {
    final Int8List out = row != null && row.length >= width
        ? row
        : Int8List(width);
    final int start = y * _stride;
    for (int x = 0; x < width; x++) {
      out[x] = _y[start + x];
    }
    return out;
  }

  @override
  Int8List getMatrix() {
    final Int8List out = Int8List(width * height);
    for (int y = 0; y < height; y++) {
      final int start = y * _stride;
      for (int x = 0; x < width; x++) {
        out[y * width + x] = _y[start + x];
      }
    }
    return out;
  }
}

String? _decodeFrame(
  (Uint8List luma, int width, int height, int rowStride) frame,
) => decodeQr(frame.$1, frame.$2, frame.$3, frame.$4);

/// The camera, and nothing else. Android asks for the camera permission when
/// the scanner starts here, not before -- nobody pasting a link is asked.
class _QrScanPage extends StatefulWidget {
  const _QrScanPage();

  @override
  State<_QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<_QrScanPage> {
  CameraController? _controller;
  bool _failed = false;
  bool _done = false;
  bool _decoding = false;
  DateTime _lastTry = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final List<CameraDescription> cameras = await availableCameras();
      final CameraDescription camera = cameras.firstWhere(
        (CameraDescription c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final CameraController controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      await controller.startImageStream(_onFrame);
    } on Object {
      if (mounted) {
        setState(() => _failed = true);
      }
    }
  }

  /// A few frames a second are enough to read a code, and each is decoded
  /// away from the screen's thread so the preview stays smooth.
  Future<void> _onFrame(CameraImage image) async {
    final DateTime now = DateTime.now();
    if (_done ||
        _decoding ||
        now.difference(_lastTry) < const Duration(milliseconds: 250)) {
      return;
    }
    _decoding = true;
    _lastTry = now;
    try {
      final Plane y = image.planes.first;
      final String? text = await compute(_decodeFrame, (
        Uint8List.fromList(y.bytes),
        image.width,
        image.height,
        y.bytesPerRow,
      ));
      if (_done || !mounted || text == null || text.isEmpty) {
        return;
      }
      _done = true;
      Navigator.of(context).pop(text);
    } finally {
      _decoding = false;
    }
  }

  @override
  void dispose() {
    final CameraController? controller = _controller;
    _controller = null;
    if (controller != null) {
      if (controller.value.isStreamingImages) {
        controller.stopImageStream().catchError((Object _) {});
      }
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppText text = AppText.of(context);
    final CameraController? controller = _controller;
    final NebulaPalette p = context.palette;
    return NebulaPage(
      title: text.pairScanTitle,
      children: <Widget>[
        // The design's camera box: 300 high, the look's large radius.
        Container(
          height: 300,
          margin: const EdgeInsets.only(top: 16),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A0D),
            borderRadius: BorderRadius.circular(p.radiusLg),
          ),
          child: _failed
              ? null
              : controller == null
              ? const Center(child: CircularProgressIndicator())
              : FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: controller.value.previewSize?.height ?? 300,
                    height: controller.value.previewSize?.width ?? 300,
                    child: CameraPreview(controller),
                  ),
                ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            p.look == NebulaLook.minimal ? 0 : 8,
            10,
            0,
            0,
          ),
          child: Text(
            text.pairScanNoCamera,
            style: TextStyle(
              fontSize: 13,
              height: 19 / 13,
              color: _failed ? p.amberText : p.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}
