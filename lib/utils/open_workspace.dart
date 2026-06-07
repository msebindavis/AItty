import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

void openWorkspace(BuildContext context, String workspaceId, {bool replace = false}) {
  FocusManager.instance.primaryFocus?.unfocus();
  final location = '/workspaces/$workspaceId';
  if (replace) {
    context.go(location);
  } else {
    context.push(location);
  }
}
