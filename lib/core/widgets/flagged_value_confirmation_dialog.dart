import 'package:flutter/material.dart';

class FlaggedValueConfirmationDialog extends StatelessWidget {
  final List<String> outOfRangeMessages;

  const FlaggedValueConfirmationDialog({
    super.key,
    required this.outOfRangeMessages,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirm flagged value(s)'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: outOfRangeMessages.map((msg) => Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Text(msg),
          )).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Review'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Confirm & Save'),
        ),
      ],
    );
  }
}
