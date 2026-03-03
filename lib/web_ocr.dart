// Web-specific OCR helpers interface.
// Uses conditional imports to load the correct implementation.

import 'web_ocr_stub.dart' if (dart.library.html) 'web_ocr_web.dart' as impl;

/// Finds the video element on the page, captures a frame, crops it,
/// and runs OCR on it. Returns empty list on non-web platforms.
Future<List<OcrResult>> recognizeWebVideo() => impl.recognizeWebVideo();

/// A minimal data class representing a single recognized text block along
/// with its approximate x/y position inside the source image.  Only the x
/// coordinate is currently used for sorting, but the full box is preserved
/// for possible future use.
class OcrResult {
  final String text;
  final double x;
  final double y;
  final double width;
  final double height;

  OcrResult(this.text, this.x, this.y, this.width, this.height);

  @override
  String toString() => 'OcrResult(text: "$text", x: $x)';
}

/// Normalizes common OCR confusion pairs within the numeric prefix of a call
/// number.  Only characters occurring before the first hyphen are adjusted.
String _correctConfusions(String s) {
  final m = RegExp(r'^([0-9OIl]+)').firstMatch(s);
  if (m != null) {
    final prefix = m.group(1)!;
    final corrected = prefix
        .replaceAll('O', '0')
        .replaceAll(RegExp(r'[Il]'), '1');
    return corrected + s.substring(prefix.length);
  }
  return s;
}

/// Filters OCR result lines using the KDC pattern and returns the subset
/// that matches.  (Could also return bounding boxes to feed into ordering.)
// KDC call number regex used by both web helpers and main logic.
// NOTE: OCR often injects spaces or weird characters between parts of the
// call number, so we normalize by removing whitespace and certain symbols
// before applying the regex.  We also keep the original line for debugging.
//
// KDC pattern: up to 3‑digit (or more) numeric classification with optional
// decimal, then a hyphen, a single Korean character, 2–3 digits, another
// hyphen, and a final Korean consonant or alphanumeric suffix.
final RegExp kdcRegex = RegExp(
  r"^\d{1,3}(?:\.\d+)?-[가-힣]\d{2,3}-[가-힣ㄱ-ㅎ\w\.]+",
);

/// Attempts to parse a line into a KDC call number by extracting
/// its numeric, Korean-author, and trailing components.  This is more
/// permissive than simple regex matching and tolerates noise characters.
String? _extractCallNumber(String line) {
  // apply character‑confusion corrections before we try to parse
  line = _correctConfusions(line);
  // numeric prefix (allow more than 3 digits if noise)
  final numMatch = RegExp(r"\d+(?:\.\d+)?").firstMatch(line);
  if (numMatch == null) return null;
  final num = numMatch.group(0)!;
  // korean author character + 2–3 digits
  final korMatch = RegExp(r"[가-힣]\s*\d{2,3}").firstMatch(line);
  if (korMatch == null) return null;
  final kor = korMatch.group(0)!.replaceAll(RegExp(r"\s+"), "");
  // trailing part (e.g., v.2, or letter code)
  // look after the korean match
  final after = line.substring(korMatch.end);
  final trailMatch = RegExp(r"[A-Za-z0-9\.]+?").firstMatch(after);
  final trail = trailMatch?.group(0) ?? '';
  final candidate = '$num-$kor${trail.isNotEmpty ? '-$trail' : ''}';
  // final normalize: remove whitespace
  return candidate.replaceAll(RegExp(r"\s+"), "");
}

/// Returns normalized call numbers extracted from [lines].
List<String> filterKdc(List<String> lines) {
  final List<String> results = [];
  for (final line in lines) {
    final parsed = _extractCallNumber(line);
    if (parsed != null && kdcRegex.hasMatch(parsed)) {
      results.add(parsed);
    }
  }
  return results;
}
