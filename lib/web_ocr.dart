// Web-specific OCR helpers interface.
// Uses conditional imports to load the correct implementation.

import 'web_ocr_stub.dart' if (dart.library.html) 'web_ocr_web.dart' as impl;

/// Finds the video element on the page, captures a frame, crops it,
/// and runs OCR on it. Returns empty list on non-web platforms.
Future<List<OcrResult>> recognizeWebVideo() => impl.recognizeWebVideo();

/// A minimal data class representing a single recognized text block along
/// with its approximate x/y position inside the source image.
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

/// Represents the parsed components of a library call number.
class CallNumber implements Comparable<CallNumber> {
  final String rawText;
  final String? roomSymbol; // 도서관 호실 기호 (e.g., '별', '어')
  final double classification; // 분류기호 (e.g., 813.6)
  final String authorChar; // 저자기호 (e.g., '김')
  final int authorNum; // 저자기호 숫자 (e.g., 123)
  final String bookTitleHint; // 도서명 초성 (e.g., '하')
  final int? volume; // 권호 (e.g., 2)
  final int? copy; // 복본 (e.g., 1)

  CallNumber({
    required this.rawText,
    this.roomSymbol,
    required this.classification,
    required this.authorChar,
    required this.authorNum,
    required this.bookTitleHint,
    this.volume,
    this.copy,
  });

  /// A more sophisticated parser for KDC call numbers based on RULES.md.
  ///
  /// The regex is structured to capture each part of the call number.
  /// - Group 1: Optional room symbol ([가-힣])
  /// - Group 2: Classification number (\d{3}(\.\d+)?)
  /// - Group 4: Author character ([가-힣])
  /// - Group 5: Author number (\d{3})
  /// - Group 6: Book title hint ([가-힣]+)
  /// - Group 7: Optional volume part ((v\.|v)?\d+)
  /// - Group 9: Optional copy part (c\.\d+|c\d+)
  static final RegExp _parserRegex = RegExp(
    r'^([가-힣])?\s*(\d{3}(?:\.\d+)?)\s*([가-힣])(\d{3})([가-힣]+)(?:\s*(v[.]?\s*(\d+)))?(?:\s*(c[.]?\s*(\d+)))?',
    multiLine: true,
  );

  /// Attempts to create a [CallNumber] from a raw OCR string.
  /// Returns null if the string doesn't match the expected format.
  static CallNumber? fromString(String text) {
    final cleanText =
        text.replaceAll(RegExp(r'\s+'), ' ').trim(); // Normalize whitespace
    final match = _parserRegex.firstMatch(cleanText);

    if (match == null) {
      return null;
    }

    try {
      final roomSymbol = match.group(1);
      final classification = double.parse(match.group(2)!);
      final authorChar = match.group(4)!;
      final authorNum = int.parse(match.group(5)!);
      final bookTitleHint = match.group(6)!;

      final volumeString = match.group(8);
      final volume = volumeString != null ? int.parse(volumeString) : null;

      final copyString = match.group(10);
      final copy = copyString != null ? int.parse(copyString) : null;

      return CallNumber(
        rawText: text,
        roomSymbol: roomSymbol,
        classification: classification,
        authorChar: authorChar,
        authorNum: authorNum,
        bookTitleHint: bookTitleHint,
        volume: volume,
        copy: copy,
      );
    } catch (e) {
      // Parsing failed for one of the groups
      return null;
    }
  }

  @override
  int compareTo(CallNumber other) {
    // 1. Classification Number (numeric)
    int result = classification.compareTo(other.classification);
    if (result != 0) return result;

    // 2. Author Character (alphabetic)
    result = authorChar.compareTo(other.authorChar);
    if (result != 0) return result;

    // 3. Author Number (numeric)
    result = authorNum.compareTo(other.authorNum);
    if (result != 0) return result;
    
    // 4. Book Title Hint (alphabetic)
    result = bookTitleHint.compareTo(other.bookTitleHint);
    if (result != 0) return result;

    // 5. Volume Number (numeric) - handle nulls
    if (volume != null && other.volume != null) {
      result = volume!.compareTo(other.volume!);
      if (result != 0) return result;
    } else if (volume != null) {
      return 1; // this has volume, other doesn't
    } else if (other.volume != null) {
      return -1; // other has volume, this doesn't
    }
    
    // Room symbol and copy number are not used for sorting comparison
    return 0;
  }

  @override
  String toString() {
    return '[$classification $authorChar$authorNum$bookTitleHint${volume != null ? ' v.$volume' : ''}]';
  }
}

/// Validates if a list of recognized call numbers is in the correct order.
///
/// Returns `true` if the list is sorted, `false` otherwise.
bool validateOrder(List<CallNumber> numbers) {
  for (int i = 0; i < numbers.length - 1; i++) {
    if (numbers[i].compareTo(numbers[i + 1]) > 0) {
      // Found a pair that is out of order
      return false;
    }
  }
  return true;
}


/// Extracts library call number patterns from a list of strings based on new rules.
List<String> extractLibraryCallNumbers(List<String> lines) {
  final Set<String> results = {};
  // Combine all lines into a single string to handle call numbers split across lines.
  // Use a unique separator that is unlikely to appear in OCR.
  final singleString = lines.join(' ||| ');

  // Regex to find potential call number blocks. It's intentionally loose.
  final blockRegex = RegExp(r'(\d{3}[\s\S]+?)(?=\d{3}|$)', multiLine: true);

  final matches = blockRegex.allMatches(singleString);
  for (final match in matches) {
    String block = match.group(1)!.replaceAll('|||', ' ').trim();
    
    // Attempt to parse the block using the strict CallNumber parser
    final callNumber = CallNumber.fromString(block);
    if (callNumber != null) {
      // If parsing is successful, use the parsed (and implicitly validated) string.
      // Reconstruct a clean string for display.
      String cleanRepresentation =
          '${callNumber.classification} ${callNumber.authorChar}${callNumber.authorNum}${callNumber.bookTitleHint}';
      if (callNumber.volume != null) {
        cleanRepresentation += ' v.${callNumber.volume}';
      }
      if (callNumber.copy != null) {
        cleanRepresentation += ' c.${callNumber.copy}';
      }
      results.add(cleanRepresentation);
    }
  }

  return results.toList();
}
