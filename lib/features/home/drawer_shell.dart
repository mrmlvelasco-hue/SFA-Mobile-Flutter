import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_colors.dart';
import '../auth/auth_state.dart';
import '../dashboard/dashboard_screen.dart';
import '../placeholder/coming_soon_screen.dart';
import '../route_calls/route_call_schedule_screen.dart';
import 'menu_items.dart';

/// App shell shown once signed in: an AppBar + Drawer, with the current
/// screen as the body. The Flutter equivalent of the RN app's
/// DrawerNavigation + CustomDrawer.
class DrawerShell extends StatefulWidget {
  const DrawerShell({super.key});

  @override
  State<DrawerShell> createState() => _DrawerShellState();
}

class _DrawerShellState extends State<DrawerShell> {
  MenuItem _current = drawerMenuItems.first;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final user = auth.user;

    return Scaffold(
      appBar: AppBar(title: Text(_current.label)),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                color: AppColors.primary,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CircleAvatar(radius: 28, backgroundColor: AppColors.white, child: Icon(Icons.person, size: 32, color: AppColors.primary)),
                    const SizedBox(height: 12),
                    Text(
                      user?.fullName.isNotEmpty == true ? user!.fullName : (user?.username ?? 'Signed in'),
                      style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    if (user?.employeeId.isNotEmpty == true)
                      Text(user!.employeeId, style: const TextStyle(color: AppColors.white, fontSize: 12)),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: drawerMenuItems
                      .map((item) => ListTile(
                            title: Text(item.label),
                            selected: item.route == _current.route,
                            onTap: () {
                              setState(() => _current = item);
                              Navigator.of(context).pop();
                            },
                          ))
                      .toList(),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.logout, color: AppColors.red2),
                title: const Text('Logout', style: TextStyle(color: AppColors.red2)),
                onTap: () async {
                  Navigator.of(context).pop();
                  await context.read<AuthState>().logout();
                },
              ),
            ],
          ),
        ),
      ),
      body: _screenFor(_current),
    );
  }

  Widget _screenFor(MenuItem item) {
    switch (item.route) {
      case '/dashboard':
        return const DashboardScreen();
      case '/route-call-schedule':
        return const RouteCallScheduleScreen();
      default:
        return ComingSoonScreen(
          title: item.label,
          embedded: true,
          note: 'This section will be ported from the React Native app in a later milestone.',
        );
    }
  }
}
