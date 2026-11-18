import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/formatting.dart';
import '../../core/offline_store.dart';
import '../../core/token_storage.dart';
import 'auth_repository.dart';
import 'sfa_user.dart';

enum AuthStatus { unknown, signedOut, signingIn, signedIn }

/// App-wide auth/session state, consumed via Provider. The Flutter equivalent of the RN app's
/// Redux `auth` slice.
class AuthState extends ChangeNotifier {
  AuthState({AuthRepository? repository, TokenStorage? storage, OfflineStore? offlineStore, DateTime Function()? clock})
      : _repository = repository ?? AuthRepository(),
        _storage = storage ?? TokenStorage.instance,
        _offlineStore = offlineStore ?? FileOfflineStore.instance,
        _clock = clock ?? DateTime.now;

  final AuthRepository _repository;
  final TokenStorage _storage;
  final OfflineStore _offlineStore;
  final DateTime Function() _clock;

  static const yesterdaySessionMessage = "You haven't logged out from yesterday's session. Please re-login.";

  /// 'YYYY-MM-DD' of the login. A session (and its downloaded data) is only good for that day.
  String? loginDay;

  AuthStatus status = AuthStatus.unknown;
  SfaUser? user;
  String? errorMessage;

  /// The login response's `sales_org` (SAP sales org codes for the user's offices). The RN app
  /// keeps this as `sales_org_download_data` and sends it with the download-datav2 calls.
  List<String> salesOrg = const [];
  List<String> userRoutes = const [];

  /// Restores the session saved at the last successful login, so reopening the app the same day
  /// doesn't require logging in again (the app then runs on the saved download, offline).
  /// A session from an earlier day is ended, as in the RN app: "You haven't logged out from
  /// yesterday's session. Please re-login." A token without a saved session (from a build before
  /// sessions were saved) can't be used -- there's no endpoint to re-fetch the user.
  Future<void> bootstrap() async {
    final token = await _storage.readToken();
    final session = await _storage.readSession();
    if (token != null && token.isNotEmpty && session != null) {
      Map<String, dynamic>? restored;
      try {
        restored = jsonDecode(session) as Map<String, dynamic>;
        _applySession(restored);
      } catch (_) {
        restored = null; // corrupt or old-format session
      }
      if (restored != null) {
        if (loginDay == dayKey(_clock())) {
          status = AuthStatus.signedIn;
          notifyListeners();
          return;
        }
        await signOutLocally(message: yesterdaySessionMessage);
        return;
      }
    }
    await _clearLocal();
    user = null;
    status = AuthStatus.signedOut;
    notifyListeners();
  }

  /// Call when the app comes back to the foreground: ends the session if the day has changed
  /// since login (the RN app checks every 5 seconds). Returns true if it did.
  Future<bool> endSessionIfNewDay() async {
    if (status != AuthStatus.signedIn || loginDay == dayKey(_clock())) return false;
    await signOutLocally(message: yesterdaySessionMessage);
    return true;
  }

  Future<bool> login(String username, String password) async {
    status = AuthStatus.signingIn;
    errorMessage = null;
    notifyListeners();

    final result = await _repository.login(username: username, password: password);
    if (result.isSuccess && result.data is Map) {
      final data = result.data as Map<String, dynamic>;
      final token = data['access_token'] as String?;
      if (token == null || token.isEmpty || data['user'] is! Map) {
        status = AuthStatus.signedOut;
        errorMessage = 'Login succeeded but the server response was incomplete.';
        notifyListeners();
        return false;
      }
      final session = {
        'user': data['user'],
        'sales_org': data['sales_org'] ?? const [],
        'user_routes': data['user_routes'] ?? const [],
        'login_day': dayKey(_clock()),
      };
      await _storage.saveToken(token);
      await _storage.saveSession(jsonEncode(session));
      _applySession(session);
      status = AuthStatus.signedIn;
      notifyListeners();
      return true;
    }

    status = AuthStatus.signedOut;
    errorMessage = result.message.isNotEmpty ? result.message : 'Login failed.';
    notifyListeners();
    return false;
  }

  Future<void> logout() async {
    final employeeId = user?.employeeId;
    if (employeeId != null && employeeId.isNotEmpty) {
      // Best-effort: still clear local state even if the network call fails.
      await _repository.logout(employeeId: employeeId);
    }
    await signOutLocally();
  }

  /// Drops the local session without calling the server -- used when the server has already
  /// rejected the token (401 "Unauthenticated."), or the day has changed.
  Future<void> signOutLocally({String? message}) async {
    await _clearLocal();
    user = null;
    loginDay = null;
    salesOrg = const [];
    userRoutes = const [];
    errorMessage = message;
    status = AuthStatus.signedOut;
    notifyListeners();
  }

  void _applySession(Map<String, dynamic> session) {
    user = SfaUser.fromJson(session['user'] as Map<String, dynamic>);
    salesOrg = _strings(session['sales_org'], (v) => v.toString());
    userRoutes = _strings(session['user_routes'], (v) => v is Map ? (v['sales_route'] ?? '').toString() : v.toString());
    loginDay = session['login_day']?.toString();
  }

  static List<String> _strings(dynamic value, String Function(dynamic) toText) {
    if (value is! List) return const [];
    return value.map(toText).where((s) => s.isNotEmpty).toList();
  }

  /// Also deletes the session's downloaded data (the RN app drops its DownloadData table on
  /// re-login). The pricing cache is kept, as the RN app keeps PricingList.db.
  Future<void> _clearLocal() async {
    await _storage.clearToken();
    await _storage.clearSession();
    await _offlineStore.delete(OfflineDocs.downloadData);
  }
}
