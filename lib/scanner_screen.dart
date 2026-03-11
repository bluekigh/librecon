import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
// web OCR helpers
import 'web_ocr.dart' as webocr;

// image package for cropping/decoding (add to pubspec.yaml dependencies)
import 'package:image/image.dart' as img;

/// A simple full‑screen camera preview with a semi‑transparent overlay
/// containing a horizontal scan guide box at the center. The area inside
/// the box will later be used as the region of interest (ROI) for OCR.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  AnimationController? _animationController;

  // Store parsed call numbers and validation status
  final List<webocr.CallNumber> _recognizedNumbers = [];
  bool? _isOrderCorrect; // null = indeterminate, true = correct, false = error

  // 원본 OCR 텍스트 (디버그)
  String _lastRawText = '';
  Timer? _ocrTimer;
  String _ocrStatus = '대기 중';
  bool _isProcessing = false; // OCR 처리 중복 방지 플래그
  static const String appVersion = "v0.03";

  @override
  void initState() {
    super.initState();
    // Note: Flutter web cannot force device orientation; users must rotate
    // their phones manually. The layout is already responsive, so camera
    // preview and overlays adapt automatically.

    _initCamera();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(() {
        setState(() {});
      });

    // 주기적으로 OCR 처리
    _ocrTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      if (mounted && !_isProcessing) {
        _animationController?.forward(from: 0);
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
  /// box.
  Future<Uint8List?> captureCroppedPreview() async {
    if (_controller == null || !_controller!.value.isInitialized) return null;
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

    cropped = _preprocessImage(cropped);
    return Uint8List.fromList(img.encodePng(cropped));
  }

  Rect _calculateRoi(double imageWidth, double imageHeight) {
    final boxWidth = imageWidth * 0.8;
    const boxHeight = 150.0;
    final left = (imageWidth - boxWidth) / 2;
    final top = (imageHeight - boxHeight) / 2;
    return Rect.fromLTWH(left, top, boxWidth, boxHeight);
  }

  img.Image _preprocessImage(img.Image source) {
    img.grayscale(source);
    final contrastedImage = img.contrast(source, 150);
    return contrastedImage ?? source;
  }

  @override
  void dispose() {
    _ocrTimer?.cancel();
    _controller?.dispose();
    _animationController?.dispose();
    super.dispose();
  }

  Future<void> _performOcr() async {
    if (_isProcessing) return;
    setState(() {
      _isProcessing = true;
      _ocrStatus = '인식 중...';
    });

    if (!kIsWeb) {
      // Non-web platform logic remains the same
      try {
        final cropped = await captureCroppedPreview();
        if (cropped == null) {
          setState(() => _ocrStatus = '크롭 실패');
          return;
        }

      } catch (e) {
        setState(() => _ocrStatus = '오류');
      } finally {
        if (mounted) {
          setState(() => _isProcessing = false);
        }
      }
      return;
    }

    try {
      final segments = await webocr.recognizeWebVideo();
      _lastRawText = segments.map((r) => r.text).join('\n');

      // Sort segments by their horizontal position (left-to-right)
      segments.sort((a, b) => a.x.compareTo(b.x));

      final numbers = segments
          .map((s) => webocr.CallNumber.fromString(s.text))
          .whereType<webocr.CallNumber>() // Filter out nulls (non-matches)
          .toList();

      bool? validationResult;
      if (numbers.length > 1) {
        validationResult = webocr.validateOrder(numbers);
      } else {
        validationResult = null; // Not enough books to validate order
      }

      setState(() {
        _recognizedNumbers
          ..clear()
          ..addAll(numbers);
        _isOrderCorrect = validationResult;
        
        if (numbers.isEmpty) {
          _ocrStatus = '청구기호를 인식하지 못했습니다.';
        } else {
           _ocrStatus = _isOrderCorrect == true ? '정렬 양호' : (_isOrderCorrect == false ? '정렬 오류!' : '인식 완료');
        }
      });
    } catch (e) {
      setState(() => _ocrStatus = '오류: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Color _getBorderColor() {
    if (_isOrderCorrect == null) {
      return Colors.white; // Default/indeterminate state
    } else if (_isOrderCorrect!) {
      return Colors.green; // Correct order
    } else {
      return Colors.red; // Incorrect order
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

            // overlay with transparent window, color-coded for validation
            CustomPaint(painter: ScanGuidePainter(borderColor: _getBorderColor())),
            // visual timer
            if (_animationController != null)
              Positioned(
                top: (MediaQuery.of(context).size.height - 150) / 2 - 8,
                left: MediaQuery.of(context).size.width * 0.1,
                width: MediaQuery.of(context).size.width * 0.8,
                child: LinearProgressIndicator(
                  value: _animationController!.value,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(_getBorderColor()),
                ),
              ),
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
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            // bottom panel with recognized text
            if (_recognizedNumbers.isNotEmpty)
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
                      // Validation status icon and text
                      if (_isOrderCorrect != null)
                        Row(
                          children: [
                            Icon(
                              _isOrderCorrect! ? Icons.check_circle : Icons.error,
                              color: _isOrderCorrect! ? Colors.green : Colors.red,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isOrderCorrect! ? '정렬 순서가 올바릅니다.' : '정렬 오류가 발견되었습니다!',
                              style: TextStyle(
                                color: _isOrderCorrect! ? Colors.green : Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      const Divider(color: Colors.white38),
                      // List of recognized numbers
                      ..._recognizedNumbers.map(
                        (number) => Text(
                          number.toString(), // Uses the overridden toString in CallNumber
                          style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
                        ),
                      ),
                      const Divider(color: Colors.white38),
                      Text(
                        'Raw OCR: $_lastRawText',
                        style: const TextStyle(color: Colors.white54, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),

            // build version badge
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                color: Colors.black45,
                padding: const EdgeInsets.all(4),
                child: const Text(
                  appVersion,
                  style: TextStyle(color: Colors.white70, fontSize: 10),
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
/// guide rectangle, now with a customizable border color.
class ScanGuidePainter extends CustomPainter {
  final Color borderColor;

  ScanGuidePainter({this.borderColor = Colors.white});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black54;
    canvas.drawRect(Offset.zero & size, paint);

    final boxWidth = size.width * 0.8;
    final boxHeight = 150.0;
    final left = (size.width - boxWidth) / 2;
    final top = (size.height - boxHeight) / 2;
    final rect = Rect.fromLTWH(left, top, boxWidth, boxHeight);

    // cut out the guide box
    final clearPaint = Paint()..blendMode = BlendMode.clear;
    canvas.drawRect(rect, clearPaint);

    // draw border with dynamic color
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = borderColor;
    canvas.drawRect(rect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant ScanGuidePainter oldDelegate) {
    return borderColor != oldDelegate.borderColor;
  }
}
