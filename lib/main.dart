import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_theme.dart';
import 'features/auth/auth_state.dart';
import 'features/auth/login_screen.dart';
import 'features/dashboard/dashboard_state.dart';
import 'features/home/drawer_shell.dart';
import 'features/master_data/download_screen.dart';
import 'features/master_data/master_data_state.dart';
import 'features/placeholder/coming_soon_screen.dart';
import 'features/route_calls/route_call_state.dart';

void main() {
  runApp(const SfaApp());
}

class SfaApp extends StatefulWidget {
  const SfaApp({super.key});

  @override
  State<SfaApp> createState() => _SfaAppState();
}

class _SfaAppState extends State<SfaApp> with WidgetsBindingObserver {
  final AuthState _auth = AuthState()..bootstrap();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _auth.dispose();
    super.dispose();
  }

  /// Back in the foreground: a session from an earlier day ends here (the RN app polls for this).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _auth.endSessionIfNewDay();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AuthState>.value(
      value: _auth,
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

/// Login, or the signed-in app -- the RN app's AuthNavigation vs MainNavigation switch.
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
          create: (ctx) => MasterDataState(auth: ctx.read<AuthState>())..start(),
          child: const SignedInHome(),
        );
      case AuthStatus.signedOut:
      case AuthStatus.signingIn:
        return const LoginScreen();
    }
  }
}

/// Downloads (or restores today's saved) master data, then shows the app. Every screen below
/// reads the downloaded data, so the app works offline from here on.
class SignedInHome extends StatelessWidget {
  const SignedInHome({super.key});

  @override
  Widget build(BuildContext context) {
    final masterData = context.watch<MasterDataState>();
    if (!masterData.isReady) return const DownloadScreen();
    return MultiProvider(
      // Rebuilt from the data whenever it is (re)downloaded.
      key: ValueKey(masterData.downloadedAt),
      providers: [
        ChangeNotifierProvider(create: (_) => RouteCallState.fromDownload(masterData.data)),
        ChangeNotifierProvider(create: (ctx) => DashboardState(auth: ctx.read<AuthState>())),
      ],
      child: const DrawerShell(),
    );
  }
}
