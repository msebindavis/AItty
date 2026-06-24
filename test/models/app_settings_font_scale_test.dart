import 'package:ai_tty/models/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppSettings fontScale persistence', () {
    test('default fontScale is 1.0', () {
      expect(const AppSettings().fontScale, 1.0);
    });

    test('copyWith updates fontScale', () {
      final s = const AppSettings().copyWith(fontScale: 1.25);
      expect(s.fontScale, 1.25);
    });

    test('round-trips through toJson/fromJson', () {
      const original = AppSettings(fontScale: 1.45);
      final restored = AppSettings.fromJson(original.toJson());
      expect(restored.fontScale, closeTo(1.45, 1e-9));
    });

    test('fromJson defaults fontScale to 1.0 when missing', () {
      final restored = AppSettings.fromJson(const AppSettings().toJson());
      expect(restored.fontScale, 1.0);
    });
  });
}