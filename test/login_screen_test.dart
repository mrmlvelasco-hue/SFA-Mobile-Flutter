import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sfa_mobile/features/auth/auth_state.dart';
import 'package:sfa_mobile/features/auth/login_screen.dart';

Widget _wrap(Widget child) {
  return ChangeNotifierProvider(
    create: (_) => AuthState(),
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets('shows validation errors when submitting an empty form', (tester) async {
    await tester.pumpWidget(_wrap(const LoginScreen()));

    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pump();

    expect(find.text('Username is required'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);
  });

  testWidgets('renders username and password fields', (tester) async {
    await tester.pumpWidget(_wrap(const LoginScreen()));

    expect(find.byKey(const Key('usernameField')), findsOneWidget);
    expect(find.byKey(const Key('passwordField')), findsOneWidget);
  });
}
