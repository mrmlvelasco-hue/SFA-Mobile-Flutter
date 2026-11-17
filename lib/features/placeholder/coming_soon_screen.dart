import 'package:flutter/material.dart';

/// Stand-in for every screen not yet ported from the React Native app.
/// Swapped out for the real screen module-by-module in later milestones.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({super.key, required this.title, this.note});

  final String title;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
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
      ),
    );
  }
}
