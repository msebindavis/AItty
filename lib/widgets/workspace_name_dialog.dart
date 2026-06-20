import 'package:flutter/material.dart';

class WorkspaceNameDialog {
  static Future<String?> show(
    BuildContext context, {
    required String title,
    String initialName = '',
    List<String> existingNames = const [],
  }) async {
    final controller = TextEditingController(text: initialName);
    final formKey = GlobalKey<FormState>();

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Workspace Name',
                  hintText: 'e.g. backend-service',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Workspace name cannot be empty';
                  }
                  final trimmed = v.trim();
                  if (existingNames.any((name) => name.toLowerCase() == trimmed.toLowerCase())) {
                    return 'A workspace with this name already exists';
                  }
                  return null;
                },
                onFieldSubmitted: (v) {
                  if (formKey.currentState?.validate() ?? false) {
                    Navigator.pop(ctx, controller.text.trim());
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(ctx, controller.text.trim());
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}
