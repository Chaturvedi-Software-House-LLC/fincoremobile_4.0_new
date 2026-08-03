import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:FincoreGo/widgets/entry_widgets.dart';

/// Builds a solid-color PNG of the given size, matching what a rasterized
/// PDF page looks like from the printer code's point of view.
Uint8List _fakePng(int width, int height) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('fitToThermalPaperWidth', () {
    test('downscales a 76mm-wide render (608px) to 58mm (384px)', () {
      final source = _fakePng(608, 100);
      final result = fitToThermalPaperWidth(source, 384);

      final decoded = img.decodePng(result)!;
      expect(decoded.width, 384);
      // Aspect ratio preserved: height scales down by the same factor.
      expect(decoded.height, closeTo(100 * 384 / 608, 1));
    });

    test('downscales a 76mm-wide render (608px) to 80mm (576px)', () {
      final source = _fakePng(608, 100);
      final result = fitToThermalPaperWidth(source, 576);

      final decoded = img.decodePng(result)!;
      expect(decoded.width, 576);
    });

    test('leaves the image untouched when already narrower than target', () {
      final source = _fakePng(300, 100);
      final result = fitToThermalPaperWidth(source, 384);

      // Same bytes back - no resize was performed.
      expect(result, same(source));
    });

    test('leaves the image untouched when exactly the target width', () {
      final source = _fakePng(384, 100);
      final result = fitToThermalPaperWidth(source, 384);

      expect(result, same(source));
    });
  });

  group('detectThermalPrinterWidthPx', () {
    const channel = MethodChannel('sunmi_printer_plus');

    void mockGetPaper(TestWidgetsFlutterBinding binding, Object? response) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        MethodCall call,
      ) async {
        if (call.method == 'getPaper') {
          if (response is Exception) throw response;
          return response;
        }
        return null;
      });
    }

    final binding = TestWidgetsFlutterBinding.ensureInitialized();

    tearDown(() {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });

    test('"1" (58mm reported) resolves to 384px', () async {
      mockGetPaper(binding, '1');
      expect(await detectThermalPrinterWidthPx(), 384);
    });

    test('"0" (80mm reported) resolves to 576px', () async {
      mockGetPaper(binding, '0');
      expect(await detectThermalPrinterWidthPx(), 576);
    });

    test('null response defaults to 576px (80mm)', () async {
      mockGetPaper(binding, null);
      expect(await detectThermalPrinterWidthPx(), 576);
    });

    test('unexpected non-numeric response defaults to 576px (80mm)', () async {
      mockGetPaper(binding, 'unknown');
      expect(await detectThermalPrinterWidthPx(), 576);
    });

    test('a thrown platform error defaults to 576px (80mm)', () async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        MethodCall call,
      ) async {
        throw PlatformException(code: 'UNAVAILABLE');
      });
      expect(await detectThermalPrinterWidthPx(), 576);
    });
  });
}
