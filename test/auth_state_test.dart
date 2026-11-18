import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sfa_mobile/core/api_client.dart';
import 'package:sfa_mobile/features/auth/auth_state.dart';

import 'helpers.dart';

ApiEnvelope _loginOk() => ApiEnvelope(
      code: 200,
      message: 'Successfully logged in!',
      data: {
        'access_token': 'tok-123',
        'user': {'id': 1, 'employee_id': 'E1', 'username': 'jdelacruz', 'full_name': 'Dela Cruz, Juan', 'device_id': 'phone-1'},
        'sales_org': ['1000'],
        'user_routes': [
          {'sales_route': 'R1'}
        ],
      },
    );

void main() {
  test('login() stores the user and flips status to signedIn on success', () async {
    final storage = InMemoryTokenStorage();
    final auth = AuthState(repository: FakeAuthRepository(_loginOk()), storage: storage);

    final ok = await auth.login('jdelacruz', 'Secret#12345');

    expect(ok, isTrue);
    expect(auth.status, AuthStatus.signedIn);
    expect(auth.user?.employeeId, 'E1');
    expect(auth.salesOrg, ['1000']);
    expect(auth.userRoutes, ['R1']);
    expect(storage.values['token'], 'tok-123');
  });

  test('login() surfaces the backend message and stays signedOut on failure', () async {
    final storage = InMemoryTokenStorage();
    final auth = AuthState(
        repository: FakeAuthRepository(ApiEnvelope(code: 401, message: 'Login failed: Invalid username or password.')),
        storage: storage);

    final ok = await auth.login('jdelacruz', 'wrong');

    expect(ok, isFalse);
    expect(auth.status, AuthStatus.signedOut);
    expect(auth.errorMessage, 'Login failed: Invalid username or password.');
    expect(storage.values, isEmpty);
  });

  test('bootstrap() restores the session saved at login', () async {
    final storage = InMemoryTokenStorage();
    await AuthState(repository: FakeAuthRepository(_loginOk()), storage: storage).login('jdelacruz', 'Secret#12345');

    final reopened = AuthState(repository: FakeAuthRepository(), storage: storage);
    await reopened.bootstrap();

    expect(reopened.status, AuthStatus.signedIn);
    expect(reopened.user?.employeeId, 'E1');
    expect(reopened.salesOrg, ['1000']);
  });

  test('bootstrap() discards a token saved without a session', () async {
    final storage = InMemoryTokenStorage()..values['token'] = 'old-token';
    final auth = AuthState(repository: FakeAuthRepository(), storage: storage);

    await auth.bootstrap();

    expect(auth.status, AuthStatus.signedOut);
    expect(storage.values.containsKey('token'), isFalse);
  });

  test('bootstrap() signs out on a corrupt session', () async {
    final storage = InMemoryTokenStorage()
      ..values['token'] = 't'
      ..values['session'] = jsonEncode({'user': 'not a map'});
    final auth = AuthState(repository: FakeAuthRepository(), storage: storage);

    await auth.bootstrap();

    expect(auth.status, AuthStatus.signedOut);
    expect(auth.user, isNull);
  });

  test('logout() calls the server and clears the saved session', () async {
    final storage = InMemoryTokenStorage();
    final repo = FakeAuthRepository(_loginOk());
    final auth = AuthState(repository: repo, storage: storage);
    await auth.login('jdelacruz', 'Secret#12345');

    await auth.logout();

    expect(repo.logoutCalls, 1);
    expect(auth.status, AuthStatus.signedOut);
    expect(auth.user, isNull);
    expect(storage.values, isEmpty);
  });
}
