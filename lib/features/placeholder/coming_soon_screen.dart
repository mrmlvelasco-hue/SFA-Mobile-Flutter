import 'package:flutter/material.dart';

/// Stand-in for every screen not yet ported from the React Native app.
/// Swapped out for the real screen module-by-module in later milestones.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({super.key, required this.title, this.note, this.embedded = false});

  final String title;
  final String? note;

  /// True when shown as the body of the app shell, which already has its own app bar -- then
  /// this renders just the message instead of a second Scaffold/AppBar.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.construction, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text('$title is not ported yet.', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
              if (note != null) ...[
                const SizedBox(height: 8),
                Text(note!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Colors.grey)),
              ],
            ],
          ),
        ),
      );
    if (embedded) return body;
    return Scaffold(appBar: AppBar(title: Text(title)), body: body);
  }
}
