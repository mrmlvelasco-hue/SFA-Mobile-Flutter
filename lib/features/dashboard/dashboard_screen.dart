import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/app_colors.dart';
import '../../core/formatting.dart';
import 'dashboard_state.dart';
import 'gauge_card.dart';

/// The first screen after login -- the RN app's UserScreen.js: "As of <yesterday>" and five
/// gauges of month-to-date actual vs COOB target.
///
/// Not ported yet: the password-expiry reminder the RN screen shows after the download, and the
/// DC-inventory/floor-stock prefetch it does in the background (they belong with the inventory
/// screens).
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    final state = context.read<DashboardState>();
    if (state.figures.isEmpty && state.status != DashboardStatus.error) {
      // After the first frame, so notifyListeners() doesn't fire during this build.
      WidgetsBinding.instance.addPostFrameCallback((_) => state.load());
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DashboardState>();
    return RefreshIndicator(
      onRefresh: state.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 30, bottom: 24),
        children: [
          Text(
            'As of ${longDateWithWeekday(state.asOf)}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.blue, fontWeight: FontWeight.w800, fontSize: 16),
          ),
          if (state.offlineSince != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Offline -- showing figures saved ${DateFormat('MMM d, h:mm a', 'en_US').format(state.offlineSince!)}',
                key: const Key('dashboardOffline'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.grayLight, fontSize: 12),
              ),
            ),
          if (state.status == DashboardStatus.loading && state.figures.isEmpty)
            const Padding(padding: EdgeInsets.only(top: 80), child: Center(child: CircularProgressIndicator()))
          else if (state.status == DashboardStatus.error)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                Text(state.errorMessage ?? 'Could not load the dashboard.', textAlign: TextAlign.center),
                TextButton(onPressed: state.load, child: const Text('Retry')),
              ]),
            )
          else
            ...state.gauges.map((g) => GaugeCard(key: Key('gauge-${g.label}'), gauge: g)),
        ],
      ),
    );
  }
}
