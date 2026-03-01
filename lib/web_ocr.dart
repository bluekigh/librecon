// Web-specific OCR helpers.  Since ML Kit text recognition does not
// currently support Flutter Web, the easiest cross-browser path is to
// leverage a JavaScript library such as tesseract.js via `dart:js` or the
// `js` package.  Another option is to write a small JS snippet that calls
// the modern `OCR` Web API when it lands, but that is not widely available
// yet.
//
// The code below is only a skeleton; it shows how you might take a video
// frame, draw it into a canvas, crop to the ROI defined by our scan guide,
// and hand the resulting image data off to tesseract.js.  You would need to
// add `web/index.html` script tags to import tesseract.js and use
// `@JS()` extern declarations to call it.

import 'dart:html' as html;
import 'dart:ui' as ui;

/// Represents a bounding box within the video element in pixel coordinates.
class BoundingBox {
  final double left, top, width, height;
  BoundingBox(this.left, this.top, this.width, this.height);
}

/// Captures the current frame from [videoElement], crops to [box], and
/// returns the raw image data as a `Blob` (or `Uint8List`).
Future<html.Blob> captureCroppedFrame(html.VideoElement videoElement, BoundingBox box) async {
  final canvas = html.CanvasElement(width: box.width.toInt(), height: box.height.toInt());
  final ctx = canvas.context2D;
  ctx.drawImageScaledFromSource(videoElement, box.left, box.top, box.width, box.height, 0, 0, box.width, box.height);
  final blob = await canvas.toBlob('image/png');
  if (blob == null) throw StateError('Unable to capture frame');
  return blob;
}

/// Example stub showing how you might call a JS function provided by
/// tesseract.js (assumes `window.recognizeImage` is defined in your HTML).
Future<String> recognizeText(html.Blob imageBlob) async {
  // Use package:js or dart:js to interop with tesseract.js.  For instance:
  //
  // @JS('recognizeImage')
  // external Promise<String> _jsRecognize(ImageData data);
  //
  // final text = await promiseToFuture<String>(_jsRecognize(...));
  //
  // Here we simply return an empty string for the prototype.
  return Future.value('');
}

/// Filters OCR result lines using the KDC pattern and returns the subset
/// that matches.  (Could also return bounding boxes to feed into ordering.)
List<String> filterKdc(List<String> lines) {
  return lines.where((l) => kdcRegex.hasMatch(l)).toList();
}
