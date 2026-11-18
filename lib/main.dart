import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_theme.dart';
import 'features/auth/auth_state.dart';
import 'features/auth/login_screen.dart';
import 'features/home/drawer_shell.dart';
import 'features/placeholder/coming_soon_screen.dart';
import 'features/route_calls/route_call_state.dart';

void main() {
  runApp(const SfaApp());
}

class SfaApp extends StatelessWidget {
  const SfaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthState()..bootstrap(),
      child: MaterialApp(
        title: 'SFA',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const AuthGate(),
        routes: {
          '/forgot-password': (_) => const ComingSoonScreen(
                title: 'Forgot Password',
                note: 'The backend does not expose a mobile forgot-password endpoint yet '
                    '(only the admin-portal one) -- see README "Known gaps".',
              ),
        },
      ),
    );
  }
}

/// Shows Login or the signed-in app shell based on AuthState, the Flutter
/// equivalent of the RN app's AuthNavigation vs MainNavigation switch.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    switch (auth.status) {
      case AuthStatus.unknown:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case AuthStatus.signedIn:
        // Created per signed-in session, so logging out and in as someone else starts clean.
        return ChangeNotifierProvider(
          create: (ctx) => RouteCallState(auth: ctx.read<AuthState>()),
          child: const DrawerShell(),
        );
      case AuthStatus.signedOut:
      case AuthStatus.signingIn:
        return const LoginScreen();
    }
  }
}
