import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_tty/features/workspace/terminal_keyboard/terminal_toolbar.dart';

void main() {
  group('TerminalToolbar', () {
    testWidgets('Esc, Tab, Ctrl render as text key-caps, not icons',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalToolbar(
              onToolbarAction: (_) {},
              keyboardShown: true,
              arrowPadOpen: false,
              onArrowPadToggleRequested: () {},
              onHistoryPicked: (_) {},
              recentCommands: const [],
              ctrlActive: false,
            ),
          ),
        ),
      );

      expect(find.text('ESC'), findsOneWidget);
      expect(find.text('TAB'), findsOneWidget);
      expect(find.text('CTRL'), findsOneWidget);
    });

    testWidgets('renders 9 icons in declared order', (tester) async {
      final emitted = <TerminalToolbarAction>[];
      var arrowToggles = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalToolbar(
              onToolbarAction: emitted.add,
              keyboardShown: true,
              arrowPadOpen: false,
              onArrowPadToggleRequested: () => arrowToggles++,
              onHistoryPicked: (_) {},
              recentCommands: const [],
              ctrlActive: false,
            ),
          ),
        ),
      );

      expect(emitted, isEmpty);
      expect(arrowToggles, 0);

      // Tap each toolbar button in left-to-right order and verify the
      // emitted TerminalToolbarAction (or arrow toggle) matches the
      // new contract:
      //   1. Esc → onToolbarAction(esc)
      //   2. Tab → onToolbarAction(tab)
      //   3. Toggle Ctrl → onToolbarAction(toggleCtrl)
      //   4. Arrow pad → onArrowPadToggleRequested (not the enum)
      //   5. Paste from clipboard → onToolbarAction(clipboard)
      //   6. History → onToolbarAction(history) (note: PopupMenuButton
      //      also opens a menu, but the tap itself fires nothing —
      //      the host sees history picks via onHistoryPicked).
      //   7. Toggle command bar → onToolbarAction(chat)
      //   8. Hide keyboard → onToolbarAction(keyboardHide)
      //   9. Toggle cboard → onToolbarAction(more)
      await tester.tap(find.byTooltip('Esc'));
      await tester.pump();
      await tester.tap(find.byTooltip('Tab'));
      await tester.pump();
      await tester.tap(find.byTooltip('Toggle Ctrl'));
      await tester.pump();
      await tester.tap(find.byTooltip('Arrow pad'));
      await tester.pump();
      await tester.tap(find.byTooltip('Paste from clipboard'));
      await tester.pump();
      await tester.tap(find.byTooltip('Toggle command bar'));
      await tester.pump();
      await tester.tap(find.byTooltip('Hide keyboard'));
      await tester.pump();
      await tester.tap(find.byTooltip('Toggle cboard'));
      await tester.pump();

      expect(emitted, [
        TerminalToolbarAction.esc,
        TerminalToolbarAction.tab,
        TerminalToolbarAction.toggleCtrl,
        // No arrows enum here — the arrows button fires
        // onArrowPadToggleRequested instead.
        TerminalToolbarAction.clipboard,
        TerminalToolbarAction.chat,
        TerminalToolbarAction.keyboardHide,
        TerminalToolbarAction.more,
      ]);
      expect(arrowToggles, 1);
    });

    testWidgets('keyboardShown flips the keyboard icon + tooltip', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalToolbar(
              onToolbarAction: (_) {},
              keyboardShown: true,
              arrowPadOpen: false,
              onArrowPadToggleRequested: () {},
              onHistoryPicked: (_) {},
              recentCommands: const [],
              ctrlActive: false,
            ),
          ),
        ),
      );
      expect(find.byTooltip('Hide keyboard'), findsOneWidget);
      expect(find.byTooltip('Show keyboard'), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalToolbar(
              onToolbarAction: (_) {},
              keyboardShown: false,
              arrowPadOpen: false,
              onArrowPadToggleRequested: () {},
              onHistoryPicked: (_) {},
              recentCommands: const [],
              ctrlActive: false,
            ),
          ),
        ),
      );
      expect(find.byTooltip('Show keyboard'), findsOneWidget);
      expect(find.byTooltip('Hide keyboard'), findsNothing);
    });

    testWidgets('arrow pad toggle fires callback in both states', (tester) async {
      var open = false;
      var toggleCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalToolbar(
              onToolbarAction: (_) {},
              keyboardShown: true,
              arrowPadOpen: open,
              onArrowPadToggleRequested: () => toggleCount++,
              onHistoryPicked: (_) {},
              recentCommands: const [],
              ctrlActive: false,
            ),
          ),
        ),
      );

      await tester.tap(find.byTooltip('Arrow pad'));
      await tester.pump();

      open = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalToolbar(
              onToolbarAction: (_) {},
              keyboardShown: true,
              arrowPadOpen: open,
              onArrowPadToggleRequested: () => toggleCount++,
              onHistoryPicked: (_) {},
              recentCommands: const [],
              ctrlActive: false,
            ),
          ),
        ),
      );

      await tester.tap(find.byTooltip('Arrow pad'));
      await tester.pump();

      expect(toggleCount, 2);
    });

    testWidgets('toolbar row is wrapped in a horizontal scroll view',
        (tester) async {
      // On phones narrower than 7 × 48 = 336 dp (the scrollable region),
      // the leftmost icons would overflow. Verify the left side is
      // hosted inside a horizontal SingleChildScrollView so the user
      // can scroll to reach Esc / Tab / Ctrl / Arrows / Clipboard /
      // History / Chat.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320, // narrower than the 7 × 48 scrollable region
              child: TerminalToolbar(
                onToolbarAction: (_) {},
                keyboardShown: true,
                arrowPadOpen: false,
                onArrowPadToggleRequested: () {},
                onHistoryPicked: (_) {},
                recentCommands: const [],
                ctrlActive: false,
              ),
            ),
          ),
        ),
      );
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(
        tester
            .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
            .scrollDirection,
        Axis.horizontal,
      );
    });

    testWidgets('keyboard and 3-dots are pinned outside the scroll view',
        (tester) async {
      // The right-most two icons (Keyboard, ⋯) must never scroll off
      // the screen. They are pinned to the right edge of the toolbar
      // by being children of the outer Row, not the inner scroll view.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 280, // very narrow, only the pinned icons fit
              child: TerminalToolbar(
                onToolbarAction: (_) {},
                keyboardShown: true,
                arrowPadOpen: false,
                onArrowPadToggleRequested: () {},
                onHistoryPicked: (_) {},
                recentCommands: const [],
                ctrlActive: false,
              ),
            ),
          ),
        ),
      );

      // Pinned icons (still findable, never inside the scroll view).
      final scrollView = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      final scrollChild = scrollView.child; // the inner Row
      expect(scrollChild, isA<Row>());
      // The scrollable Row has 7 children: Esc, Tab, Ctrl, Arrows,
      // Clipboard, History, Chat.
      expect((scrollChild as Row).children.length, 7);

      // The keyboard and cboard icons live outside the SingleChildScrollView.
      expect(
        find.descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.byTooltip('Hide keyboard'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.byTooltip('Toggle cboard'),
        ),
        findsNothing,
      );
      // And the divider is between the two regions.
      // (No direct assertion possible without a Key on the divider; the
      //  structural assertions above are the load-bearing checks.)
    });

    testWidgets('history PopupMenuButton surfaces recent commands',
        (tester) async {
      String? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalToolbar(
              onToolbarAction: (_) {},
              keyboardShown: true,
              arrowPadOpen: false,
              onArrowPadToggleRequested: () {},
              onHistoryPicked: (cmd) => picked = cmd,
              recentCommands: const ['ls -la', 'git status', 'echo hi'],
              ctrlActive: false,
            ),
          ),
        ),
      );

      // Open the history menu and pick an entry.
      await tester.tap(find.byTooltip('History'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('git status').last);
      await tester.pumpAndSettle();

      expect(picked, 'git status');
    });
  });
}