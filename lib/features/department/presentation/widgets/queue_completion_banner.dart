import 'package:flutter/material.dart';

/// No timer: partial-save feedback stays visible until explicitly dismissed.
MaterialBanner queueCompletionBanner(String message, VoidCallback onDismiss) {
  return MaterialBanner(
    leading: const Icon(Icons.warning_amber_rounded),
    content: Text(message),
    actions: [TextButton(onPressed: onDismiss, child: const Text('Dismiss'))],
  );
}
