import 'package:ai_tty/features/workspace/terminal_keyboard/terminal_gesture_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TerminalGestureLayer absorbTaps', () {
    Future<void> pumpAndTap(WidgetTester tester, Finder finder) async {
      await tester.tap(finder);
      // Flush the double-tap-detection timer (~300ms) and let any
      // onTap callbacks fire.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
    }

    testWidgets('absorbTaps=true invokes onClearSelection on tap',
        (tester) async {
      var selectionCleared = 0;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 200,
            child: TerminalGestureLayer(
              enabled: true,
              absorbTaps: true,
              fontScale: 1.0,
              onArrow: (_) {},
              onTab: () {},
              onFontScaleChanged: (_) {},
              onClearSelection: () => selectionCleared++,
              child: const Text('terminal'),
            ),
          ),
        ),
      ));

      await pumpAndTap(tester, find.text('terminal'));

      expect(selectionCleared, 1,
          reason: 'absorbTaps should clear selection on tap (mirrors xterm)');
    });

    testWidgets('absorbTaps=true sends TextInput.hide platform call',
        (tester) async {
      final sent = <MethodCall>[];
      final channel = SystemChannels.textInput;
      TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        sent.add(call);
        return null;
      });

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 200,
            child: TerminalGestureLayer(
              enabled: true,
              absorbTaps: true,
              fontScale: 1.0,
              onArrow: (_) {},
              onTab: () {},
              onFontScaleChanged: (_) {},
              child: const Text('terminal'),
            ),
          ),
        ),
      ));

      await pumpAndTap(tester, find.text('terminal'));

      expect(
        sent.any((c) => c.method == 'TextInput.hide'),
        isTrue,
        reason: 'absorbTaps must dismiss any IME that xterm just opened',
      );

      TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
  });
}