import 'package:flutter/foundation.dart';

/// For ChangeNotifiers that keep working after an `await` (downloads, network calls): the screen
/// that owns them can go away mid-call (e.g. logging out during the download), and notifying a
/// disposed ChangeNotifier throws. After dispose, notifications are silently dropped.
mixin SafeNotifier on ChangeNotifier {
  bool _disposed = false;

  bool get isDisposed => _disposed;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }
}
