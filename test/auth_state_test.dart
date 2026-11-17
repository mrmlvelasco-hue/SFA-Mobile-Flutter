import 'package:flutter_test/flutter_test.dart';
import 'package:sfa_mobile/core/api_client.dart';
import 'package:sfa_mobile/features/auth/auth_repository.dart';
import 'package:sfa_mobile/features/auth/auth_state.dart';

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository(this.response);
  final ApiEnvelope response;

  @override
  Future<ApiEnvelope> login({required String username, required String password}) async => response;

  @override
  Future<ApiEnvelope> logout({required String employeeId}) async =>
      ApiEnvelope(code: 200, message: 'Successfully logged out');
}

void main() {
  test('login() stores the user and flips status to signedIn on success', () async {
    final repo = _FakeAuthRepository(ApiEnvelope(
      code: 200,
      message: 'Successfully logged in!',
      data: {
        'access_token': 'tok-123',
        'user': {'id': 1, 'employee_id': 'E1', 'username': 'jdelacruz', 'full_name': 'Dela Cruz, Juan'},
        'user_routes': [],
      },
    ));
    final auth = AuthState(repository: repo);

    final ok = await auth.login('jdelacruz', 'Secret#12345');

    expect(ok, isTrue);
    expect(auth.status, AuthStatus.signedIn);
    expect(auth.user?.employeeId, 'E1');
  });

  test('login() surfaces the backend message and stays signedOut on failure', () async {
    final repo = _FakeAuthRepository(ApiEnvelope(code: 401, message: 'Login failed: Invalid username or password.'));
    final auth = AuthState(repository: repo);

    final ok = await auth.login('jdelacruz', 'wrong');

    expect(ok, isFalse);
    expect(auth.status, AuthStatus.signedOut);
    expect(auth.errorMessage, 'Login failed: Invalid username or password.');
  });
}
