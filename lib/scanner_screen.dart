import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
// web OCR helpers
import 'web_ocr.dart' as webocr;

// image package for cropping/decoding (add to pubspec.yaml dependencies)
import 'package:image/image.dart' as img;

/// A simple full‑screen camera preview with a semi‑transparent overlay
/// containing a horizontal scan guide box at the center.  The area inside
/// the box will later be used as the region of interest (ROI) for OCR.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({Key? key}) : super(key: key);

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;

  // 인식된 텍스트 라인들을 저장
  final List<String> _recognizedLines = [];
  // 원본 OCR 텍스트 (디버그)
  String _lastRawText = '';
  Timer? _ocrTimer;
  String _ocrStatus = '대기 중';
  // 빌드 버전 - dart define으로 주입됨
  static const String buildVersion = String.fromEnvironment(
    'BUILD_VERSION',
    defaultValue: '0',
  );

  @override
  void initState() {
    super.initState();
    // Note: Flutter web cannot force device orientation; users must rotate
    // their phones manually.  The layout is already responsive, so camera
    // preview and overlays adapt automatically.

    _initCamera();
    // 주기적으로 OCR 처리
    _ocrTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) {
        _performOcr();
      }
    });
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    // choose the back camera by default
    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    _controller = CameraController(
      back,
      ResolutionPreset.high,
      enableAudio: false,
    );
    _initializeControllerFuture = _controller!.initialize();
    if (mounted) setState(() {});
  }

  /// Returns a cropped image byte array representing only the central guide
  /// box.  This method takes a still picture from the camera controller,
  /// decodes it, and crops it according to the same proportions used for the
  /// on-screen scan guide.  The resulting PNG bytes are suitable for feeding
  /// directly into an OCR engine.
  Future<Uint8List?> captureCroppedPreview() async {
    if (_controller == null || !_controller!.value.isInitialized) return null;
    // takePicture is somewhat heavy but gives us a full-resolution frame that
    // we can crop.  Alternative implementations could use the image stream.
    final xfile = await _controller!.takePicture();
    final bytes = await xfile.readAsBytes();

    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final roi = _calculateRoi(
      decoded.width.toDouble(),
      decoded.height.toDouble(),
    );
    var cropped = img.copyCrop(
      decoded,
      roi.left.toInt(),
      roi.top.toInt(),
      roi.width.toInt(),
      roi.height.toInt(),
    );

    // apply preprocessing: grayscale + contrast boost
    cropped = _preprocessImage(cropped);

    return Uint8List.fromList(img.encodePng(cropped));
  }

  /// Compute the region of interest rectangle corresponding to the middle
  /// guide box used in the UI.  Dimensions are expressed in pixels of the
  /// underlying image.
  Rect _calculateRoi(double imageWidth, double imageHeight) {
    final boxWidth = imageWidth * 0.8;
    const boxHeight = 150.0;
    final left = (imageWidth - boxWidth) / 2;
    final top = (imageHeight - boxHeight) / 2;
    return Rect.fromLTWH(left, top, boxWidth, boxHeight);
  }

  /// Convert [img] to grayscale and increase contrast.
  img.Image _preprocessImage(img.Image source) {
    // Convert to grayscale (modifies the image in-place)
    img.grayscale(source);
    // Increase contrast. The contrast filter creates a new image.
    // A value of 100 is normal, > 100 increases contrast. We use 150 for a 50% boost.
    return img.contrast(source, contrast: 150);
  }

  @override
  void dispose() {
    _ocrTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  // placeholder for future OCR capture logic
  Future<void> _performOcr() async {
    setState(() {
      _ocrStatus = '인식 중...';
    });

    if (!kIsWeb) {
      // non-web platforms: use our cropping helper to get a PNG of the guide
      // box and then feed it into whatever OCR engine is appropriate (e.g.,
      // ML Kit).  For now we merely log the size of the cropped image.
      try {
        final cropped = await captureCroppedPreview();
        if (cropped == null) {
          setState(() => _ocrStatus = '크롭 실패');
          return;
        }
        // TODO: convert `cropped` to an InputImage and run ML Kit.
        // ignore: avoid_print
        print('cropped size: ${cropped.lengthInBytes} bytes');
      } catch (e) {
        setState(() => _ocrStatus = '오류');
      }
      return;
    }

    try {
      final segments = await webocr.recognizeWebVideo();

      // build a simple raw string for debugging
      _lastRawText = segments.map((r) => r.text).join('\n');
      final lines = segments
          .map((r) => r.text.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      // debug print all lines with coordinates
      // ignore: avoid_print
      print('ocr segments: $segments');
      final filtered = webocr.filterKdc(lines);
      setState(() {
        _recognizedLines
          ..clear()
          ..addAll(filtered);
        _ocrStatus = filtered.isEmpty ? '결과 없음' : '인식 완료';
      });
    } catch (e) {
      setState(() => _ocrStatus = '오류');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_initializeControllerFuture != null)
              FutureBuilder<void>(
                future: _initializeControllerFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.done) {
                    return CameraPreview(_controller!);
                  } else {
                    return const Center(child: CircularProgressIndicator());
                  }
                },
              )
            else
              const Center(child: CircularProgressIndicator()),

            // overlay with transparent window (using CustomPainter for flexibility)
            CustomPaint(painter: ScanGuidePainter()),
            // status line
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Container(
                color: Colors.black45,
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                child: Text(
                  _ocrStatus,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            // bottom panel with recognized text (shown only when lines present)
            if (_recognizedLines.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  color: Colors.black54,
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ..._recognizedLines.map(
                        (s) => Text(
                          s,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      const Divider(color: Colors.white),
                      Text(
                        'Raw: $_lastRawText',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // always show raw text in small overlay bottom-right (even empty)
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                color: Colors.black45,
                padding: const EdgeInsets.all(4),
                child: Text(
                  'Raw: $_lastRawText',
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                ),
              ),
            ),
            // build version badge
            Positioned(
              right: 8,
              top: 8,
              child: Container(
                color: Colors.black45,
                padding: const EdgeInsets.all(4),
                child: Text(
                  'v${buildVersion}',
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Painter that draws a translucent overlay with a clear horizontal
/// guide rectangle centered on the screen. This works identically on web
/// and mobile and keeps painting logic in one place.
class ScanGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black54;
    canvas.drawRect(Offset.zero & size, paint);

    final boxWidth = size.width * 0.8;
    final boxHeight = 150.0;
    final left = (size.width - boxWidth) / 2;
    final top = (size.height - boxHeight) / 2;
    final rect = Rect.fromLTWH(left, top, boxWidth, boxHeight);

    // cut out the guide box by painting it with a clear blend mode
    final clearPaint = Paint()..blendMode = BlendMode.clear;
    canvas.drawRect(rect, clearPaint);

    // draw border
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white;
    canvas.drawRect(rect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
