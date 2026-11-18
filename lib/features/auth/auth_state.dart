import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/token_storage.dart';
import 'auth_repository.dart';
import 'sfa_user.dart';

enum AuthStatus { unknown, signedOut, signingIn, signedIn }

/// App-wide auth/session state, consumed via Provider. The Flutter equivalent of the RN app's
/// Redux `auth` slice.
class AuthState extends ChangeNotifier {
  AuthState({AuthRepository? repository, TokenStorage? storage})
      : _repository = repository ?? AuthRepository(),
        _storage = storage ?? TokenStorage.instance;

  final AuthRepository _repository;
  final TokenStorage _storage;

  AuthStatus status = AuthStatus.unknown;
  SfaUser? user;
  String? errorMessage;

  /// The login response's `sales_org` (SAP sales org codes for the user's offices). The RN app
  /// keeps this as `sales_org_download_data` and sends it with the download-datav2 calls.
  List<String> salesOrg = const [];
  List<String> userRoutes = const [];

  /// Restores the session saved at the last successful login, so reopening the app doesn't
  /// require logging in again. A token without a saved session (e.g. from a build before sessions
  /// were saved) can't be used -- there's no endpoint to re-fetch the user -- so it is discarded.
  Future<void> bootstrap() async {
    final token = await _storage.readToken();
    final session = await _storage.readSession();
    if (token != null && token.isNotEmpty && session != null) {
      try {
        _applySession(jsonDecode(session) as Map<String, dynamic>);
        status = AuthStatus.signedIn;
        notifyListeners();
        return;
      } catch (_) {
        // corrupt or old-format session: fall through to signed out
      }
    }
    await _clearLocal();
    status = AuthStatus.signedOut;
    notifyListeners();
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
  /// rejected the token (401 "Unauthenticated."), so there's nothing to log out of.
  Future<void> signOutLocally({String? message}) async {
    await _clearLocal();
    user = null;
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
  }

  static List<String> _strings(dynamic value, String Function(dynamic) toText) {
    if (value is! List) return const [];
    return value.map(toText).where((s) => s.isNotEmpty).toList();
  }

  Future<void> _clearLocal() async {
    await _storage.clearToken();
    await _storage.clearSession();
  }
}
