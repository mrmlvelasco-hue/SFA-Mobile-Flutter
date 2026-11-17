import 'package:flutter/foundation.dart';

import '../../core/token_storage.dart';
import 'auth_repository.dart';
import 'sfa_user.dart';

enum AuthStatus { unknown, signedOut, signingIn, signedIn }

/// App-wide auth/session state, consumed via Provider. The Flutter
/// equivalent of the RN app's Redux `auth` slice.
class AuthState extends ChangeNotifier {
  AuthState({AuthRepository? repository}) : _repository = repository ?? AuthRepository();
  final AuthRepository _repository;

  AuthStatus status = AuthStatus.unknown;
  SfaUser? user;
  String? errorMessage;
  List<String> userRoutes = const [];

  Future<void> bootstrap() async {
    final token = await TokenStorage.instance.readToken();
    status = (token != null && token.isNotEmpty) ? AuthStatus.signedIn : AuthStatus.signedOut;
    // Note: we don't have a "/me" endpoint to re-hydrate `user` from a saved
    // token yet, so a resumed session has `user == null` until the next
    // login. Screens that need user fields should tolerate that until a
    // dedicated profile fetch is added.
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
      if (token == null || token.isEmpty) {
        status = AuthStatus.signedOut;
        errorMessage = 'Login succeeded but no access token was returned.';
        notifyListeners();
        return false;
      }
      await TokenStorage.instance.saveToken(token);
      user = SfaUser.fromJson(data['user'] as Map<String, dynamic>);
      userRoutes = (data['user_routes'] as List?)
              ?.map((r) => (r is Map ? r['sales_route']?.toString() : r.toString()) ?? '')
              .where((s) => s.isNotEmpty)
              .toList() ??
          const [];
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
    await TokenStorage.instance.clearToken();
    user = null;
    userRoutes = const [];
    status = AuthStatus.signedOut;
    notifyListeners();
  }
}
