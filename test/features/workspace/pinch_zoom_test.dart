import 'package:ai_tty/features/workspace/pinch_zoom_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PinchZoomPolicy (font-scale math)', () {
    test('identity at base=1, scale=1', () {
      expect(
        PinchZoomPolicy.resolve(baseScale: 1.0, gestureScale: 1.0),
        1.0,
      );
    });

    test('pinch out 2x → 2.0', () {
      expect(
        PinchZoomPolicy.resolve(baseScale: 1.0, gestureScale: 2.0),
        2.0,
      );
    });

    test('pinch in 0.5x → 0.5, clamped to 0.75', () {
      expect(
        PinchZoomPolicy.resolve(baseScale: 1.0, gestureScale: 0.5),
        0.75,
      );
    });

    test('pinch out 3x → 3.0, clamped to 2.0', () {
      expect(
        PinchZoomPolicy.resolve(baseScale: 1.0, gestureScale: 3.0),
        2.0,
      );
    });

    test('snaps to 0.05 steps — 1.137 → 1.15', () {
      expect(
        PinchZoomPolicy.resolve(baseScale: 1.0, gestureScale: 1.137),
        closeTo(1.15, 1e-9),
      );
    });

    test('snaps to 0.05 steps — 1.123 → 1.10', () {
      expect(
        PinchZoomPolicy.resolve(baseScale: 1.0, gestureScale: 1.123),
        closeTo(1.10, 1e-9),
      );
    });

    test('snaps before clamping — 3.7 → 2.0, not 3.7→3.70→clamp→3.70', () {
      // Either order is fine, but value must end at 2.0.
      expect(PinchZoomPolicy.resolve(baseScale: 1.0, gestureScale: 3.7), 2.0);
    });

    test('from non-1 base scale — 1.2 × 1.5 → snapped 1.80', () {
      expect(
        PinchZoomPolicy.resolve(baseScale: 1.2, gestureScale: 1.5),
        closeTo(1.80, 1e-9),
      );
    });

    test('clamps + snaps combined — 1.2 base × 3 gesture → snap 3.60 → clamp 2.0', () {
      expect(PinchZoomPolicy.resolve(baseScale: 1.2, gestureScale: 3.0), 2.0);
    });
  });
}