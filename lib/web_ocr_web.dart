import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:js_util' as js_util;
import 'dart:typed_data';
import 'web_ocr.dart';

/// Represents a bounding box within the video element in pixel coordinates.
class BoundingBox {
  final double left, top, width, height;
  BoundingBox(this.left, this.top, this.width, this.height);
}

/// Finds the video element, calculates ROI, captures frame, and runs OCR.
Future<List<OcrResult>> recognizeWebVideo() async {
  try {
    final list = html.document.getElementsByTagName('video');
    if (list.isEmpty) return [];
    final video = list.first as html.VideoElement;

    final width = video.videoWidth.toDouble();
    final height = video.videoHeight.toDouble();
    if (width == 0 || height == 0) return [];

    // ROI 계산 (same as painter proportions)
    final boxWidth = width * 0.8;
    final boxHeight = 150.0;
    final left = (width - boxWidth) / 2;
    final top = (height - boxHeight) / 2;

    final blob = await _captureCroppedFrame(
      video,
      BoundingBox(left, top, boxWidth, boxHeight),
    );

    // split into several vertical pieces and obtain positions
    return await _recognizeTextSegments(blob, 3);
  } catch (e) {
    return [];
  }
}

/// Captures the current frame from [videoElement], crops to [box], and
/// returns the raw image data as a `Blob`.
Future<html.Blob> _captureCroppedFrame(
  html.VideoElement videoElement,
  BoundingBox box,
) async {
  final canvas = html.CanvasElement(
    width: box.width.toInt(),
    height: box.height.toInt(),
  );
  final ctx = canvas.context2D;
  ctx.drawImageScaledFromSource(
    videoElement,
    box.left,
    box.top,
    box.width,
    box.height,
    0,
    0,
    box.width,
    box.height,
  );

  // perform grayscale, threshold and sharpening on the pixel data
  _preprocessCanvas(canvas, ctx);

  final blob = await canvas.toBlob('image/png');
  return blob;
}

/// Apply a series of filters to [canvas] to make text more distinct.
void _preprocessCanvas(
  html.CanvasElement canvas,
  html.CanvasRenderingContext2D ctx,
) {
  final int width = canvas.width ?? 0;
  final int height = canvas.height ?? 0;
  final imgData = ctx.getImageData(0, 0, width, height);
  final Uint8ClampedList data = imgData.data;

  // grayscale
  for (int i = 0; i < data.length; i += 4) {
    final r = data[i];
    final g = data[i + 1];
    final b = data[i + 2];
    final lum = (0.299 * r + 0.587 * g + 0.114 * b).round();
    data[i] = data[i + 1] = data[i + 2] = lum;
  }

  // thresholding
  const threshold = 128;
  for (int i = 0; i < data.length; i += 4) {
    final v = data[i] < threshold ? 0 : 255;
    data[i] = data[i + 1] = data[i + 2] = v;
  }

  // sharpening
  final copy = Uint8ClampedList.fromList(data);
  const int kernelSize = 3;
  const List<double> kernel = [0, -1, 0, -1, 5, -1, 0, -1, 0]; // Sharpen
  final int halfKernelSize = kernelSize ~/ 2;

  for (int y = halfKernelSize; y < height - halfKernelSize; y++) {
    for (int x = halfKernelSize; x < width - halfKernelSize; x++) {
      double sumR = 0, sumG = 0, sumB = 0;
      for (int ky = -halfKernelSize; ky <= halfKernelSize; ky++) {
        for (int kx = -halfKernelSize; kx <= halfKernelSize; kx++) {
          final int pixelY = y + ky;
          final int pixelX = x + kx;
          final int kernelIndex = (ky + halfKernelSize) * kernelSize + (kx + halfKernelSize);
          final double kernelValue = kernel[kernelIndex];
          
          final int pixelIndex = (pixelY * width + pixelX) * 4;
          sumR += copy[pixelIndex] * kernelValue;
          sumG += copy[pixelIndex + 1] * kernelValue;
          sumB += copy[pixelIndex + 2] * kernelValue;
        }
      }
      final int newIndex = (y * width + x) * 4;
      data[newIndex] = sumR.clamp(0, 255).toInt();
      data[newIndex + 1] = sumG.clamp(0, 255).toInt();
      data[newIndex + 2] = sumB.clamp(0, 255).toInt();
    }
  }

  ctx.putImageData(imgData, 0, 0);
}

/// Recognizes the image in `parts` vertical slices via JS.
Future<List<OcrResult>> _recognizeTextSegments(
  html.Blob imageBlob,
  int parts,
) async {
  try {
    final promise = js_util.callMethod(
      js_util.globalThis,
      'recognizeImageSegments',
      [imageBlob, parts],
    );
    final List<dynamic> raw = await js_util.promiseToFuture<List<dynamic>>(
      promise,
    );
    final results = <OcrResult>[];
    for (final item in raw) {
      if (item is Map) {
        results.add(
          OcrResult(
            item['text']?.toString() ?? '',
            (item['x'] as num?)?.toDouble() ?? 0.0,
            (item['y'] as num?)?.toDouble() ?? 0.0,
            (item['width'] as num?)?.toDouble() ?? 0.0,
            (item['height'] as num?)?.toDouble() ?? 0.0,
          ),
        );
      }
    }
    results.sort((a, b) => a.x.compareTo(b.x));
    return results;
  } catch (_) {
    return [];
  }
}
