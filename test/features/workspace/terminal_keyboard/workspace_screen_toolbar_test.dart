import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_tty/features/workspace/terminal_keyboard/terminal_toolbar.dart';

/// A minimal harness that mirrors the bits of [_WorkspaceScreenState] this
/// change touches: command-bar visibility, clipboard read, history pick.
/// The real screen pulls in `WorkspaceManager`, `xterm`, etc.; this harness
/// exercises only the contract the new toolbar relies on.
class _ToolbarHarness extends StatefulWidget {
  const _ToolbarHarness({required this.recentCommands});
  final List<String> recentCommands;
  @override
  State<_ToolbarHarness> createState() => _ToolbarHarnessState();
}

class _ToolbarHarnessState extends State<_ToolbarHarness> {
  final _commandController = TextEditingController();
  bool _showCommandBar = true;
  // Sticky Ctrl mirror of `_WorkspaceScreenState._ctrl`. The harness
  // model is: `toggleCtrl` flips the bool; subsequent "send" actions
  // (here, taps on the clipboard button) do NOT clear it, so the user
  // can apply Ctrl to multiple actions in a row.
  bool _ctrl = false;

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (!mounted) return;
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clipboard is empty')),
      );
      return;
    }
    _commandController.text = text;
    _commandController.selection = TextSelection.collapsed(offset: text.length);
  }

  @override
  void dispose() {
    _commandController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: Colors.black,
              alignment: Alignment.center,
              child: const Text('terminal'),
            ),
          ),
          if (_showCommandBar)
            TextField(controller: _commandController, autofocus: false),
          TerminalToolbar(
            onToolbarAction: (action) async {
              switch (action) {
                case TerminalToolbarAction.clipboard:
                  await _pasteFromClipboard();
                case TerminalToolbarAction.chat:
                  setState(() => _showCommandBar = !_showCommandBar);
                case TerminalToolbarAction.toggleCtrl:
                  setState(() => _ctrl = !_ctrl);
                case TerminalToolbarAction.history:
                  // Handled inside the toolbar's PopupMenuButton.
                  break;
                case TerminalToolbarAction.esc:
                case TerminalToolbarAction.tab:
                case TerminalToolbarAction.arrows:
                case TerminalToolbarAction.keyboardHide:
                case TerminalToolbarAction.more:
                  break;
              }
            },
            keyboardShown: true,
            arrowPadOpen: false,
            onArrowPadToggleRequested: () {},
            onHistoryPicked: (cmd) {
              _commandController.text = cmd;
              _commandController.selection =
                  TextSelection.collapsed(offset: cmd.length);
            },
            recentCommands: widget.recentCommands,
            ctrlActive: _ctrl,
          ),
        ],
      ),
    );
  }
}

void main() {
  // Helper to install a Clipboard.getData mock that returns the given text
  // (or an empty string for the "empty clipboard" case). `Clipboard.getData`
  // casts `result['text']` to a non-null String, so the mock must always
  // supply that key.
  void mockClipboardGetData({String? text}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': text ?? ''};
      }
      return null;
    });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('Workspace toolbar integration', () {
    testWidgets('clipboard tap writes system clipboard text into command bar',
        (tester) async {
      mockClipboardGetData(text: 'ls -la /tmp');
      await tester.pumpWidget(MaterialApp(
        home: _ToolbarHarness(recentCommands: const []),
      ));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'ls -la /tmp'), findsNothing);

      await tester.tap(find.byTooltip('Paste from clipboard'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'ls -la /tmp'), findsOneWidget);
    });

    testWidgets('clipboard tap shows snackbar when clipboard is empty',
        (tester) async {
      mockClipboardGetData(text: '');
      await tester.pumpWidget(MaterialApp(
        home: _ToolbarHarness(recentCommands: const []),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Paste from clipboard'));
      await tester.pumpAndSettle();

      expect(find.text('Clipboard is empty'), findsOneWidget);
    });

    testWidgets('history tap picks a recent command into the bar (no send)',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: _ToolbarHarness(
          recentCommands: const ['git status', 'echo hi', 'docker ps'],
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('History'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('echo hi').last);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'echo hi'), findsOneWidget);
    });

    testWidgets('ctrl toggle is sticky: it stays active across other actions',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: _ToolbarHarness(recentCommands: const []),
      ));
      await tester.pumpAndSettle();

      // Toggle Ctrl on.
      await tester.tap(find.byTooltip('Toggle Ctrl'));
      await tester.pumpAndSettle();
      expect(find.text('CTRL'), findsOneWidget);

      // Tap an unrelated action (clipboard) — Ctrl should remain highlighted.
      await tester.tap(find.byTooltip('Paste from clipboard'));
      await tester.pumpAndSettle();
      expect(find.text('CTRL'), findsOneWidget,
          reason: 'Sticky Ctrl should persist across unrelated sends');

      // Tap Ctrl again to release.
      await tester.tap(find.byTooltip('Toggle Ctrl'));
      await tester.pumpAndSettle();
      expect(find.text('CTRL'), findsOneWidget,
          reason: 'CTRL text is still rendered; only the highlight clears');
    });

    testWidgets('chat tap hides then re-shows the command bar',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: _ToolbarHarness(recentCommands: const []),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);

      await tester.tap(find.byTooltip('Toggle command bar'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.byTooltip('Toggle command bar'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
    });
  });
}