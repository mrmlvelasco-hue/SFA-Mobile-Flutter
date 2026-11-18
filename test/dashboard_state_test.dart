import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sfa_mobile/core/api_client.dart';
import 'package:sfa_mobile/core/offline_store.dart';
import 'package:sfa_mobile/features/auth/auth_state.dart';
import 'package:sfa_mobile/features/dashboard/dashboard_screen.dart';
import 'package:sfa_mobile/features/dashboard/dashboard_state.dart';

import 'helpers.dart';

/// DashboardState with the HTTP call replaced.
class _FakeDashboard extends DashboardState {
  _FakeDashboard(this.response, {required super.auth, super.store}) : super(clock: () => DateTime(2026, 11, 18, 9));
  ApiEnvelope response;
  Map<String, String>? lastQuery;

  @override
  Future<ApiEnvelope> fetch(ApiClient client, {required String salesOrg, required String salesDistrict}) async {
    lastQuery = {'sales_org': salesOrg, 'sales_district': salesDistrict};
    return response;
  }
}

ApiEnvelope _figures(Map<String, dynamic> row) => ApiEnvelope(code: 200, message: 'Success', data: [row]);

const _sample = {
  'sales_route': 1234,
  'Actual_NSR': 843210.5,
  'COOB_NSR': 1000000,
  'Actual_Raw': '1500.9',
  'COOB_Raw': 2000,
  'Actual_8oe': 0,
  'COOB_8oe': 500,
  'Actual_Phy': 1234567.6,
  'COOB_Phy': 0,
  'Actual_GSR': 12.3456,
  'COOB_GSR': 100,
};

void main() {
  test('sends the first sales org, and the first route as Number(route)', () async {
    final auth = signedInAuth()..userRoutes = const ['001234'];
    final state = _FakeDashboard(_figures(_sample), auth: auth, store: InMemoryOfflineStore());

    await state.load();

    expect(state.lastQuery, {'sales_org': '1000', 'sales_district': '1234'});
  });

  test('without a sales org it sends "false", and a non-numeric route sends "NaN", as the RN app does', () async {
    final auth = signedInAuth()
      ..salesOrg = const []
      ..userRoutes = const ['R1'];
    final state = _FakeDashboard(_figures(_sample), auth: auth, store: InMemoryOfflineStore());

    await state.load();

    expect(state.lastQuery, {'sales_org': 'false', 'sales_district': 'NaN'});
  });

  test('builds the five gauges with the RN formatting', () async {
    final state = _FakeDashboard(_figures(_sample), auth: signedInAuth(), store: InMemoryOfflineStore());
    await state.load();
    final g = {for (final gauge in state.gauges) gauge.label: gauge};

    expect(state.gauges.map((e) => e.label), ['Revenue NSR', 'Volume Raw', 'Volume 8oE', 'Volume Physical', 'Revenue GSR']);
    expect(g['Revenue NSR']!.percentage, '84.3');
    expect(g['Revenue NSR']!.actual, '843,210.50');
    expect(g['Revenue NSR']!.target, '1,000,000.00');
    expect(g['Volume Raw']!.percentage, '75.0', reason: 'parseInt(1500.9) / 2000');
    expect(g['Volume Raw']!.actual, '1,501', reason: 'Math.round');
    expect(g['Volume 8oE']!.percentage, '0.0', reason: 'actual is 0');
    expect(g['Volume Physical']!.percentage, '0.0', reason: 'target is 0');
    expect(g['Volume Physical']!.actual, '1,234,568');
    expect(g['Revenue GSR']!.targetLabel, 'GSR Target');
    expect(g['Revenue GSR']!.actual, '12.35');
  });

  test('saves the figures, and shows the saved ones when offline', () async {
    final store = InMemoryOfflineStore();
    await _FakeDashboard(_figures(_sample), auth: signedInAuth(), store: store).load();

    final offline = _FakeDashboard(ApiEnvelope(code: 0, message: 'Could not reach the server.'), auth: signedInAuth(), store: store);
    await offline.load();

    expect(offline.status, DashboardStatus.loaded);
    expect(offline.offlineSince, isNotNull);
    expect(offline.gauges.first.percentage, '84.3');
  });

  test('offline with nothing saved shows the error', () async {
    final state = _FakeDashboard(ApiEnvelope(code: 0, message: 'Could not reach the server.'), auth: signedInAuth(), store: InMemoryOfflineStore());

    await state.load();

    expect(state.status, DashboardStatus.error);
    expect(state.errorMessage, 'Could not reach the server.');
  });

  test('another user\'s saved figures are not shown', () async {
    final store = InMemoryOfflineStore();
    await store.write(OfflineDocs.dashboard, {'employee_id': 'E9', 'saved_at': '2026-11-17T10:00:00', 'data': _sample});
    final state = _FakeDashboard(ApiEnvelope(code: 0, message: 'offline'), auth: signedInAuth(), store: store);

    await state.load();

    expect(state.status, DashboardStatus.error);
  });

  testWidgets('the screen shows "As of" yesterday and the five gauges', (tester) async {
    final state = _FakeDashboard(_figures(_sample), auth: signedInAuth(), store: InMemoryOfflineStore());
    await tester.pumpWidget(MultiProvider(
      providers: [ChangeNotifierProvider<DashboardState>.value(value: state)],
      child: const MaterialApp(home: Scaffold(body: DashboardScreen())),
    ));
    await tester.pumpAndSettle();

    expect(find.text('As of November 17, 2026 (Tuesday)'), findsOneWidget);
    expect(find.text('84.3%'), findsOneWidget);
    expect(find.text('Revenue NSR'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Revenue GSR'), 200);
    expect(find.text('GSR Target'), findsOneWidget);
  });

  test('a rejected token signs the user out', () async {
    final auth = signedInAuth();
    await _FakeDashboard(ApiEnvelope(code: 401, message: 'Unauthenticated.'), auth: auth, store: InMemoryOfflineStore()).load();
    expect(auth.status, AuthStatus.signedOut);
  });
}
