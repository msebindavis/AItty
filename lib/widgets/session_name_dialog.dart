import 'package:flutter/material.dart';

import '../models/session_start_choice.dart';
import '../services/tmux_startup.dart';

class SessionNameDialog {
  static Future<SessionStartChoice?> show(
    BuildContext context, {
    required String title,
    required String initialName,
  }) async {
    final controller = TextEditingController(text: initialName);
    var useTmux = true;

    return showDialog<SessionStartChoice>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Use tmux'),
                subtitle: const Text('Named session you can resume after closing the app'),
                value: useTmux,
                onChanged: (v) => setState(() => useTmux = v),
              ),
              if (useTmux) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'tmux session name',
                    hintText: 'api-build',
                  ),
                ),
              ] else
                Text(
                  'Opens a normal shell in the selected directory. State is not preserved after disconnect.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (useTmux) {
                  final name = controller.text.trim();
                  if (!TmuxStartup.isValidSessionName(name)) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Use letters, numbers, _ or - (max 64 chars)')),
                    );
                    return;
                  }
                  Navigator.pop(ctx, SessionStartChoice(useTmux: true, sessionName: name));
                } else {
                  Navigator.pop(ctx, const SessionStartChoice(useTmux: false));
                }
              },
              child: Text(useTmux ? 'Continue with tmux' : 'Open plain terminal'),
            ),
          ],
        ),
      ),
    );
  }
}
