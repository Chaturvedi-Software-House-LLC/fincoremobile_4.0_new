import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';

/// Exercises the real AdaptiveNavLabel widget (used by AppBottomNav's nav
/// tiles) directly - not a parallel re-implementation of its measurement
/// logic. An earlier version of this test mirrored a TextPainter-based
/// prediction that looked correct in isolation but still let a label like
/// "Parties" wrap with a single orphan character on a real device,
/// because the parallel measurement could disagree with the actual
/// render (font-loading timing, text-scale settings, subpixel rounding).
/// The widget was rewritten to inspect the real RenderParagraph after
/// each frame instead of predicting ahead of time, so this test pumps
/// that exact widget and inspects the same RenderParagraph a test would
/// need to in order to catch a regression of the original bug.
void main() {
  // Mirrors AppBottomNav's own tile chrome so the width this test gives
  // each label matches what the real widget lays out on-device:
  // Container margin fromLTRB(14,0,14,12) + padding symmetric(horizontal:8),
  // divided across 6 tiles, each further reduced by the InkWell's own
  // margin(2)/padding(6) on both sides.
  double tileTextWidth(double screenWidth) {
    const double outerMargin = 14 * 2;
    const double outerPadding = 8 * 2;
    const double perTileChrome = (2 * 2) + (6 * 2);
    final double barWidth = screenWidth - outerMargin - outerPadding;
    final double tileWidth = barWidth / 6;
    return tileWidth - perTileChrome;
  }

  const labels = [
    'Dashboard',
    'Items',
    'Parties',
    'Transactions',
    'Entries',
    'More',
  ];

  const screenWidths = <String, double>{
    'Extreme edge case - narrower than any real phone': 280,
    'iPhone 4/4S (smallest ever shipped)': 320,
    'iPhone 5/5S/SE 1st gen': 320,
    'Very small/budget Android (320dp)': 320,
    'Small Android (360dp)': 360,
    'iPhone SE (smallest common)': 375,
    'iPhone 13/14/15/16': 390,
    'iPhone 16 Pro': 393,
    'iPhone 16 Plus': 430,
  };

  // The exact real-device case this bug came from: "Parties" wrapping to
  // "Partie" / "s" on an iPhone 16 (393pt) even though an offline
  // TextPainter measurement predicted it would fit on one line.
  testWidgets(
    'Parties does not wrap with an orphan character on iPhone 16 width',
    (tester) async {
      final double maxWidth = tileTextWidth(393);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: maxWidth,
              child: const AdaptiveNavLabel(
                label: 'Parties',
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
          ),
        ),
      );
      // Let the widget's own post-frame shrink-check loop converge.
      await tester.pumpAndSettle();

      expect(
        _lastCharacterIsOrphaned('Parties', tester),
        isFalse,
        reason: '"Parties" still wraps with a single orphan character '
            'after AdaptiveNavLabel\'s shrink loop settled',
      );
    },
  );

  testWidgets(
    'no nav label wraps with a single orphan character at any tested width',
    (tester) async {
      for (final entry in screenWidths.entries) {
        final double maxWidth = tileTextWidth(entry.value);

        for (final label in labels) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: maxWidth,
                  child: AdaptiveNavLabel(
                    label: label,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(
            _lastCharacterIsOrphaned(label, tester),
            isFalse,
            reason: '"$label" at ${entry.key} (${entry.value}pt screen, '
                '${maxWidth.toStringAsFixed(1)}pt tile width) wraps with '
                'a single orphan character',
          );
        }
      }
    },
  );
}

/// True if the real rendered paragraph currently on screen has its very
/// last character alone on a line by itself (i.e. the second-to-last
/// character landed on a different, earlier line).
bool _lastCharacterIsOrphaned(String label, WidgetTester tester) {
  if (label.length < 2) return false;

  final renderObject = tester.renderObject(find.text(label));
  if (renderObject is! RenderParagraph) return false;

  final lastCharBoxes = renderObject.getBoxesForSelection(
    TextSelection(baseOffset: label.length - 1, extentOffset: label.length),
  );
  final secondLastCharBoxes = renderObject.getBoxesForSelection(
    TextSelection(
      baseOffset: label.length - 2,
      extentOffset: label.length - 1,
    ),
  );
  if (lastCharBoxes.isEmpty || secondLastCharBoxes.isEmpty) return false;

  return lastCharBoxes.first.top > secondLastCharBoxes.first.top;
}
