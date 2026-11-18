import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sfa_mobile/core/api_client.dart';
import 'package:sfa_mobile/core/offline_store.dart';
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

/// A mutable clock, so tests can move to the next day.
class _Clock {
  DateTime now = DateTime(2026, 11, 18, 8, 0);
  DateTime call() => now;
}

AuthState _auth({
  ApiEnvelope? login,
  InMemoryTokenStorage? storage,
  InMemoryOfflineStore? offline,
  _Clock? clock,
  FakeAuthRepository? repository,
}) =>
    AuthState(
      repository: repository ?? FakeAuthRepository(login ?? _loginOk()),
      storage: storage ?? InMemoryTokenStorage(),
      offlineStore: offline ?? InMemoryOfflineStore(),
      clock: (clock ?? _Clock()).call,
    );

void main() {
  test('login() stores the user and flips status to signedIn on success', () async {
    final storage = InMemoryTokenStorage();
    final auth = _auth(storage: storage);

    final ok = await auth.login('jdelacruz', 'Secret#12345');

    expect(ok, isTrue);
    expect(auth.status, AuthStatus.signedIn);
    expect(auth.user?.employeeId, 'E1');
    expect(auth.user?.deviceId, 'phone-1');
    expect(auth.salesOrg, ['1000']);
    expect(auth.userRoutes, ['R1']);
    expect(auth.loginDay, '2026-11-18');
    expect(storage.values['token'], 'tok-123');
  });

  test('login() surfaces the backend message and stays signedOut on failure', () async {
    final storage = InMemoryTokenStorage();
    final auth = _auth(login: ApiEnvelope(code: 401, message: 'Login failed: Invalid username or password.'), storage: storage);

    final ok = await auth.login('jdelacruz', 'wrong');

    expect(ok, isFalse);
    expect(auth.status, AuthStatus.signedOut);
    expect(auth.errorMessage, 'Login failed: Invalid username or password.');
    expect(storage.values, isEmpty);
  });

  test('bootstrap() restores a session saved earlier the same day', () async {
    final storage = InMemoryTokenStorage();
    final clock = _Clock();
    await _auth(storage: storage, clock: clock).login('jdelacruz', 'Secret#12345');

    clock.now = DateTime(2026, 11, 18, 17, 45);
    final reopened = _auth(storage: storage, clock: clock);
    await reopened.bootstrap();

    expect(reopened.status, AuthStatus.signedIn);
    expect(reopened.user?.employeeId, 'E1');
    expect(reopened.salesOrg, ['1000']);
  });

  test('bootstrap() ends a session from an earlier day and deletes its downloaded data', () async {
    final storage = InMemoryTokenStorage();
    final offline = InMemoryOfflineStore();
    final clock = _Clock();
    await _auth(storage: storage, offline: offline, clock: clock).login('jdelacruz', 'Secret#12345');
    await offline.write(OfflineDocs.downloadData, {'day': '2026-11-18'});
    await offline.write(OfflineDocs.pricing, {'day': '2026-11-18'});

    clock.now = DateTime(2026, 11, 19, 7, 0);
    final reopened = _auth(storage: storage, offline: offline, clock: clock);
    await reopened.bootstrap();

    expect(reopened.status, AuthStatus.signedOut);
    expect(reopened.errorMessage, AuthState.yesterdaySessionMessage);
    expect(storage.values.containsKey('token'), isFalse);
    expect(await offline.read(OfflineDocs.downloadData), isNull);
    expect(await offline.read(OfflineDocs.pricing), isNotNull, reason: 'the pricing cache is kept, as in the RN app');
  });

  test('endSessionIfNewDay() ends the session only once the day has changed', () async {
    final clock = _Clock();
    final auth = _auth(clock: clock);
    await auth.login('jdelacruz', 'Secret#12345');

    clock.now = DateTime(2026, 11, 18, 23, 59);
    expect(await auth.endSessionIfNewDay(), isFalse);
    expect(auth.status, AuthStatus.signedIn);

    clock.now = DateTime(2026, 11, 19, 0, 1);
    expect(await auth.endSessionIfNewDay(), isTrue);
    expect(auth.status, AuthStatus.signedOut);
    expect(auth.errorMessage, AuthState.yesterdaySessionMessage);
  });

  test('bootstrap() discards a token saved without a session', () async {
    final storage = InMemoryTokenStorage()..values['token'] = 'old-token';
    final auth = _auth(storage: storage);

    await auth.bootstrap();

    expect(auth.status, AuthStatus.signedOut);
    expect(storage.values.containsKey('token'), isFalse);
  });

  test('bootstrap() signs out on a corrupt session', () async {
    final storage = InMemoryTokenStorage()
      ..values['token'] = 't'
      ..values['session'] = jsonEncode({'user': 'not a map'});
    final auth = _auth(storage: storage);

    await auth.bootstrap();

    expect(auth.status, AuthStatus.signedOut);
    expect(auth.user, isNull);
  });

  test('logout() calls the server and clears the saved session and downloaded data', () async {
    final storage = InMemoryTokenStorage();
    final offline = InMemoryOfflineStore();
    final repo = FakeAuthRepository(_loginOk());
    final auth = _auth(storage: storage, offline: offline, repository: repo);
    await auth.login('jdelacruz', 'Secret#12345');
    await offline.write(OfflineDocs.downloadData, {'day': '2026-11-18'});

    await auth.logout();

    expect(repo.logoutCalls, 1);
    expect(auth.status, AuthStatus.signedOut);
    expect(auth.user, isNull);
    expect(storage.values, isEmpty);
    expect(await offline.read(OfflineDocs.downloadData), isNull);
  });
}
