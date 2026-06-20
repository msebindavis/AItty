import 'package:flutter/material.dart';

import '../models/session_start_choice.dart';
import '../services/tmux_startup.dart';

class SessionNameDialog {
  static Future<SessionStartChoice?> show(
    BuildContext context, {
    required String title,
    required String initialName,
    List<({String name, String? cwd})> existingSessions = const [],
  }) async {
    final controller = TextEditingController(text: initialName);
    var useTmux = true;
    var mode = existingSessions.isNotEmpty ? 'existing' : 'new';
    String? selectedExistingSession = existingSessions.isNotEmpty ? existingSessions.first.name : null;

    return showModalBottomSheet<SessionStartChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 24,
            right: 24,
            top: 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Use tmux'),
                  subtitle: const Text('Named session you can resume after closing the app'),
                  value: useTmux,
                  onChanged: (v) => setState(() => useTmux = v),
                ),
                if (useTmux) ...[
                  if (existingSessions.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'existing', label: Text('Attach Existing')),
                        ButtonSegment(value: 'new', label: Text('Create New')),
                      ],
                      selected: {mode},
                      onSelectionChanged: (newSelection) {
                        setState(() => mode = newSelection.first);
                      },
                      showSelectedIcon: false,
                    ),
                    const SizedBox(height: 16),
                  ] else
                    const SizedBox(height: 8),

                  if (mode == 'existing') ...[
                    Container(
                      constraints: const BoxConstraints(maxHeight: 250),
                      decoration: BoxDecoration(
                        border: Border.all(color: Theme.of(ctx).dividerColor),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: existingSessions.length,
                        itemBuilder: (ctx, index) {
                          final s = existingSessions[index];
                          return RadioListTile<String>(
                            title: Text(s.name),
                            subtitle: s.cwd != null ? Text(s.cwd!, style: Theme.of(ctx).textTheme.bodySmall) : null,
                            value: s.name,
                            groupValue: selectedExistingSession,
                            onChanged: (val) {
                              setState(() {
                                selectedExistingSession = val;
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ] else ...[
                    TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'tmux session name',
                        hintText: 'api-build',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ]
                ] else
                  Text(
                    'Opens a normal shell in the selected directory. State is not preserved after disconnect.',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        if (useTmux) {
                          String name;
                          if (mode == 'existing') {
                            if (selectedExistingSession == null) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(content: Text('Please select a session')),
                              );
                              return;
                            }
                            name = selectedExistingSession!;
                          } else {
                            name = controller.text.trim();
                            if (!TmuxStartup.isValidSessionName(name)) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(content: Text('Use letters, numbers, _ or - (max 64 chars)')),
                              );
                              return;
                            }
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
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
