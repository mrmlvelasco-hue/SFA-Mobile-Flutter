import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Where downloaded data lives on the phone, so the app works without internet after the
/// after-login download -- the Flutter equivalent of the RN app's SQLite tables (offlineDB.db's
/// DownloadData and PricingList.db's PricingItems).
///
/// Each document is one JSON file. The RN app split its JSON into 7000-character SQLite rows to
/// get around SQLite/AsyncStorage size limits; plain files have no such limit.
abstract class OfflineStore {
  Future<Map<String, dynamic>?> read(String name);
  Future<void> write(String name, Map<String, dynamic> value);
  Future<void> delete(String name);
}

/// Document names, in one place so sign-out can clear the right ones.
class OfflineDocs {
  OfflineDocs._();

  /// Everything from the after-login download except pricing. Valid for one user, one day.
  static const downloadData = 'download_data';

  /// download-datav2/all-pricing, kept across logins (as the RN app's PricingList.db is) and only
  /// re-downloaded when the server flags a price update.
  static const pricing = 'pricing';

  /// The last dashboard figures, so the dashboard still shows something offline.
  static const dashboard = 'dashboard';
}

class FileOfflineStore implements OfflineStore {
  FileOfflineStore._();
  static final FileOfflineStore instance = FileOfflineStore._();

  Directory? _dir;

  Future<File> _file(String name) async {
    final dir = _dir ??= Directory('${(await getApplicationDocumentsDirectory()).path}/sfa_offline');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/$name.json');
  }

  @override
  Future<Map<String, dynamic>?> read(String name) async {
    final file = await _file(name);
    if (!await file.exists()) return null;
    try {
      final text = await file.readAsString();
      // The download can be several MB of JSON: decode off the UI thread.
      final decoded = await compute(jsonDecode, text);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null; // unreadable (e.g. app killed mid-write on an old version): treat as missing
    }
  }

  @override
  Future<void> write(String name, Map<String, dynamic> value) async {
    final file = await _file(name);
    final text = await compute(jsonEncode, value);
    // Write to a temporary file, then rename: a crash mid-write never leaves a half-written file.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(file.path);
  }

  @override
  Future<void> delete(String name) async {
    final file = await _file(name);
    if (await file.exists()) await file.delete();
  }
}

/// For tests (path_provider is a native plugin, not available under `flutter test`).
class InMemoryOfflineStore implements OfflineStore {
  final Map<String, String> docs = {};

  @override
  Future<Map<String, dynamic>?> read(String name) async {
    final text = docs[name];
    return text == null ? null : jsonDecode(text) as Map<String, dynamic>;
  }

  @override
  Future<void> write(String name, Map<String, dynamic> value) async => docs[name] = jsonEncode(value);

  @override
  Future<void> delete(String name) async => docs.remove(name);
}
