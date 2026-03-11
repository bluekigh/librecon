import 'package:flutter_test/flutter_test.dart';
import 'package:librecon/web_ocr.dart' as ocr;

void main() {
  group('OCR helpers', () {
    test('recognizeWebVideo returns an empty list on non-web platforms', () async {
      final result = await ocr.recognizeWebVideo();
      expect(result, isEmpty);
    });
  });
}
