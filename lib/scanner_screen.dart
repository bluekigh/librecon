import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
    _initCamera();
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

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
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
            const CustomPaint(
              painter: ScanGuidePainter(),
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

// -----------------------------------------------------------------------------
// OCR & sorting helpers (web prototype stubs)
//
// In a web build we cannot use google_mlkit_text_recognition; instead we
// capture the video frame, crop to the guide box, and send it to a JS
// library such as tesseract.js via the helpers in web_ocr.dart.
// The `BoundingBox` for the crop can be computed from the size of the
// preview and the fixed proportions of the scan guide. Example:
//
//   final previewSize = Size(width, height);
//   final roi = BoundingBox(
//     (previewSize.width * 0.1),
//     (previewSize.height - 150) / 2,
//     previewSize.width * 0.8,
//     150,
//   );
//
// then call captureCroppedFrame(videoElement, roi) and feed the blob into
// recognizeText().

/// Example regular expression matching KDC call numbers such as
/// "813.6-김24-가" or "700.12-박3-v.2".  Adjust as needed.
final RegExp kdcRegex = RegExp(r"^\d{1,3}(?:\.\d+)?-[가-힣]\d+-[\w\.]+$");

/// Sorts a list of recognised call numbers paired with their x-coordinates
/// and returns `true` if the sequence is nondecreasing in call-number order.
bool checkOrdering(List<_TextWithPosition> items) {
  if (items.isEmpty) return true;
  // Sort by x coordinate first
  items.sort((a, b) => a.x.compareTo(b.x));

  // simple lexical comparison for now; replace with proper numeric/author logic
  for (var i = 0; i < items.length - 1; i++) {
    final current = items[i].text;
    final next = items[i + 1].text;
    if (_compareCallNumbers(current, next) > 0) {
      return false;
    }
  }
  return true;
}

/// Metadata holder
class _TextWithPosition {
  final String text;
  final double x;
  _TextWithPosition(this.text, this.x);
}

int _compareCallNumbers(String a, String b) {
  // placeholder: split at '-' and compare numeric prefixes then rest
  final pa = a.split('-');
  final pb = b.split('-');
  final na = double.tryParse(pa[0]) ?? 0.0;
  final nb = double.tryParse(pb[0]) ?? 0.0;
  final cmp = na.compareTo(nb);
  if (cmp != 0) return cmp;
  return a.compareTo(b);
}
