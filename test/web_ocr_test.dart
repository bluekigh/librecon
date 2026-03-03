import 'package:flutter_test/flutter_test.dart';
import 'package:librecon/web_ocr.dart' as ocr;

void main() {
  group('OCR helpers', () {
    test('confusion correction fixes O/I/l in numeric prefix', () {
      expect(ocr._correctConfusions('O12-가123'), '012-가123');
      expect(ocr._correctConfusions('1l3-나45'), '113-나45');
      expect(ocr._correctConfusions('A12-B34'), 'A12-B34'); // unaffected
    });

    test('filterKdc recognizes valid KDC numbers and rejects noise', () {
      final inputs = [
        '813.6-김24-가',
        '700.12-박3-v.2',
        'O13-이45', // O should become 0
        '123-가12-?',
      ];
      final result = ocr.filterKdc(inputs);
      expect(result, contains('813.6-김24-가'));
      expect(result, contains('700.12-박3-v.2'));
      // O13 becomes 013
      expect(result, contains('013-이45'));
      expect(result, isNot(contains('123-가12-?')));
    });

    test('ROI calculation matches expected proportions', () {
      // using a hypothetical image size of 1000x500
      final rect = ocr._calculateRoi(1000, 500);
      expect(rect.width, closeTo(1000 * 0.8, 0.001));
      expect(rect.height, equals(150.0));
      expect(rect.left, closeTo((1000 - 1000 * 0.8) / 2, 0.001));
      expect(rect.top, closeTo((500 - 150.0) / 2, 0.001));
    });

    test('preprocessing makes image grayscale and increases contrast', () {
      // create a simple 2x2 color image
      final img = ocr.img.Image(2, 2);
      img.setPixel(0, 0, ocr.img.getColor(100, 150, 200));
      img.setPixel(1, 0, ocr.img.getColor(50, 50, 50));
      img.setPixel(0, 1, ocr.img.getColor(200, 100, 50));
      img.setPixel(1, 1, ocr.img.getColor(25, 75, 125));
      final processed = ocr._preprocessImage(img.clone());
      // after grayscale, all channels equal
      for (int y = 0; y < 2; y++) {
        for (int x = 0; x < 2; x++) {
          final c = processed.getPixel(x, y);
          final r = ocr.img.getRed(c);
          final g = ocr.img.getGreen(c);
          final b = ocr.img.getBlue(c);
          expect(r, equals(g));
          expect(g, equals(b));
        }
      }
      // contrast increase means difference between min and max should grow
      final origVals = [100,50,200,25];
      final newVals = <int>[];
      for (int y=0;y<2;y++){
        for(int x=0;x<2;x++){
          newVals.add(ocr.img.getRed(processed.getPixel(x,y)));
        }
      }
      expect((newVals.reduce((a,b)=>a>b?a:b) - newVals.reduce((a,b)=>a<b?a:b)), greaterThan((origVals.reduce((a,b)=>a>b?a:b) - origVals.reduce((a,b)=>a<b?a:b))));
    });
  });
}
