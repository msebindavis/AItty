import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_tty/features/workspace/terminal_keyboard/arrow_pad.dart';
import 'package:ai_tty/utils/terminal_input.dart';

void main() {
  group('ArrowPad', () {
    testWidgets('renders arrow keys + Enter when shown', (tester) async {
      final controller = OverlayPortalController();
      controller.show();

      final arrows = <TerminalArrowDirection>[];
      var enterTaps = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: OverlayPortal(
                controller: controller,
                overlayChildBuilder: (_) => ArrowPad(
                  controller: controller,
                  onArrow: arrows.add,
                  onEnter: () => enterTaps++,
                ),
                child: const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ArrowPad), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_left), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_right), findsOneWidget);
      // Enter button is rendered as a Text('↵') label.
      expect(find.text('↵'), findsOneWidget);
      // Sanity: the callbacks shouldn't have fired yet.
      expect(arrows, isEmpty);
      expect(enterTaps, 0);
    });

    testWidgets('taps route to onArrow / onEnter callbacks', (tester) async {
      final controller = OverlayPortalController();
      controller.show();

      final arrows = <TerminalArrowDirection>[];
      var enterTaps = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: OverlayPortal(
                controller: controller,
                overlayChildBuilder: (_) => ArrowPad(
                  controller: controller,
                  onArrow: arrows.add,
                  onEnter: () => enterTaps++,
                ),
                child: const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.keyboard_arrow_up));
      await tester.tap(find.byIcon(Icons.keyboard_arrow_left));
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
      await tester.tap(find.byIcon(Icons.keyboard_arrow_right));
      await tester.tap(find.text('↵'));
      await tester.pump();

      expect(arrows, [
        TerminalArrowDirection.up,
        TerminalArrowDirection.left,
        TerminalArrowDirection.down,
        TerminalArrowDirection.right,
      ]);
      expect(enterTaps, 1);
    });

    testWidgets('hides when the controller is hidden', (tester) async {
      final controller = OverlayPortalController();
      controller.show();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: OverlayPortal(
                controller: controller,
                overlayChildBuilder: (_) => ArrowPad(
                  controller: controller,
                  onArrow: (_) {},
                  onEnter: () {},
                ),
                child: const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ArrowPad), findsOneWidget);

      controller.hide();
      await tester.pumpAndSettle();
      expect(find.byType(ArrowPad), findsNothing);
    });
  });
}