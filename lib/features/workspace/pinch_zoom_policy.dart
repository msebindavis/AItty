/// Centralises the math for pinch-to-zoom font scaling.
///
/// Rule: snap the live scale to the nearest 0.05 step, then clamp to
/// [minScale, maxScale]. Snapping before clamping means the user never sees
/// a value they can't actually reach (e.g. 1.18 → 1.20, not 1.18 → 1.20 → 2.0
/// if the underlying scale happens to round up past max).
class PinchZoomPolicy {
  /// 0.75× is roughly the smallest readable terminal size on a phone; the
  /// terminal_theme.dart base size of 11px would become 8.25px.
  static const double minScale = 0.75;

  /// 2.0× turns 11px into 22px, which is large but still useful for demos.
  static const double maxScale = 2.0;

  /// 0.05-step grid: 1.00, 1.05, 1.10, …, 1.95, 2.00.
  static const double step = 0.05;

  /// Resolves a gesture's live scale to the font scale we should commit.
  static double resolve({
    required double baseScale,
    required double gestureScale,
  }) {
    final raw = baseScale * gestureScale;
    final snapped = (raw / step).round() * step;
    return snapped.clamp(minScale, maxScale);
  }
}