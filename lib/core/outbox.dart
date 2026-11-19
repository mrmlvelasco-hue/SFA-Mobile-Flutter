import 'dart:math';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'offline_store.dart';
import 'safe_notifier.dart';

/// One request waiting to reach the server.
class OutboxItem {
  OutboxItem({
    required this.id,
    required this.kind,
    required this.path,
    required this.body,
    required this.createdAt,
    this.attempts = 0,
    this.lastError,
    this.failed = false,
  });

  final String id;

  /// What it is, for the user: 'Order', 'Outlet inventory', 'End call', ...
  final String kind;
  final String path;
  final Map<String, dynamic> body;
  final DateTime createdAt;
  int attempts;
  String? lastError;

  /// The server answered with an error (not a connection problem): retrying the same request
  /// won't help, so it stays here for the user to see instead of being retried forever.
  bool failed;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'path': path,
        'body': body,
        'created_at': createdAt.toIso8601String(),
        'attempts': attempts,
        'last_error': lastError,
        'failed': failed,
      };

  factory OutboxItem.fromJson(Map<String, dynamic> json) => OutboxItem(
        id: json['id'].toString(),
        kind: (json['kind'] ?? '').toString(),
        path: (json['path'] ?? '').toString(),
        body: Map<String, dynamic>.from(json['body'] as Map),
        createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ?? DateTime.now(),
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
        lastError: json['last_error']?.toString(),
        failed: json['failed'] == true,
      );
}

/// Result of [Outbox.send].
class OutboxResult {
  OutboxResult(this.envelope, {this.queued = false});

  /// The server's answer, or the connection error when [queued].
  final ApiEnvelope envelope;

  /// No connection: the request was kept on the phone and will be sent later.
  final bool queued;

  bool get sent => !queued && envelope.isSuccess;
}

/// Sends requests made during a call (orders, outlet inventory, end call), keeping them on the
/// phone when there is no connection and sending them later, in order -- the Flutter equivalent of
/// the RN app's "...ToBeSync" AsyncStorage queues (getApiOrderManagementToBeSync, etc.).
///
/// Kept across logins and days (sign-out deletes the day's download, not this): an order taken
/// offline must still reach the server.
class Outbox extends ChangeNotifier with SafeNotifier {
  Outbox({ApiClient? client, OfflineStore? store, DateTime Function()? clock})
      : _client = client ?? ApiClient.instance,
        _store = store ?? FileOfflineStore.instance,
        _clock = clock ?? DateTime.now;

  final ApiClient _client;
  final OfflineStore _store;
  final DateTime Function() _clock;

  List<OutboxItem> items = [];
  bool _flushing = false;

  int get pendingCount => items.where((i) => !i.failed).length;

  Future<void> load() async {
    final doc = await _store.read(OfflineDocs.outbox);
    final list = doc?['items'];
    items = list is List ? list.whereType<Map>().map((m) => OutboxItem.fromJson(Map<String, dynamic>.from(m))).toList() : [];
    notifyListeners();
  }

  /// Sends now. With no connection the request is queued (and sent by [flush] later); a server
  /// answer -- success or error -- is returned as is, nothing queued.
  ///
  /// If earlier requests are still waiting, this one queues behind them, so the server always
  /// gets them in the order they were made (an order before its end call).
  Future<OutboxResult> send(String kind, String path, Map<String, dynamic> body) async {
    if (pendingCount > 0) await flush();
    if (pendingCount == 0) {
      final result = await post(path, body);
      if (result.code != 0) return OutboxResult(result);
      await _enqueue(kind, path, body, result.message);
      return OutboxResult(result, queued: true);
    }
    await _enqueue(kind, path, body, null);
    return OutboxResult(ApiEnvelope(code: 0, message: 'Queued behind earlier requests'), queued: true);
  }

  /// Tries every waiting request, oldest first; stops at the first connection failure (the rest
  /// would fail too). Returns how many were sent.
  Future<int> flush() async {
    if (_flushing) return 0;
    _flushing = true;
    var sent = 0;
    try {
      for (final item in List<OutboxItem>.from(items)) {
        if (item.failed) continue;
        item.attempts++;
        final result = await post(item.path, item.body);
        if (result.code == 0) {
          item.lastError = result.message;
          break;
        }
        if (result.isUnauthenticated) {
          item.lastError = 'Log in again to send this.';
          break;
        }
        if (result.isSuccess) {
          items.remove(item);
          sent++;
        } else {
          item.failed = true;
          item.lastError = result.message;
        }
      }
    } finally {
      _flushing = false;
      await _save();
      notifyListeners();
    }
    return sent;
  }

  /// Drops a request the server rejected, once the user has seen it.
  Future<void> discard(String id) async {
    items.removeWhere((i) => i.id == id);
    await _save();
    notifyListeners();
  }

  /// Overridable in tests.
  @protected
  Future<ApiEnvelope> post(String path, Map<String, dynamic> body) => postEnvelope(_client, path, body);

  Future<void> _enqueue(String kind, String path, Map<String, dynamic> body, String? error) async {
    final now = _clock();
    items.add(OutboxItem(
      id: '${now.microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}',
      kind: kind,
      path: path,
      body: body,
      createdAt: now,
      attempts: error == null ? 0 : 1,
      lastError: error,
    ));
    await _save();
    notifyListeners();
  }

  Future<void> _save() => _store.write(OfflineDocs.outbox, {'items': items.map((i) => i.toJson()).toList()});
}
