import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sfa_mobile/core/offline_store.dart';
import 'package:sfa_mobile/core/outbox.dart';
import 'package:sfa_mobile/features/calls/call_state.dart';
import 'package:sfa_mobile/features/master_data/master_data_state.dart';
import 'package:sfa_mobile/features/route_calls/route_call_schedule_screen.dart';
import 'package:sfa_mobile/features/route_calls/route_call_state.dart';

import 'helpers.dart';

Future<RouteCallState> _pumpScreen(WidgetTester tester,
    {List<Map<String, dynamic>> orders = const [], CallState? calls, FakeOutbox? outbox}) async {
  final state = RouteCallState.fromDownload(downloadDataWith(orders: orders));
  final auth = signedInAuth();
  final box = outbox ?? FakeOutbox();
  final masterData = MasterDataState(auth: auth, repository: FakeMasterDataRepository(), store: InMemoryOfflineStore())
    ..data = downloadDataWith(orders: orders);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<Outbox>.value(value: box),
      ChangeNotifierProvider<MasterDataState>.value(value: masterData),
      ChangeNotifierProvider<CallState>.value(
          value: calls ?? CallState(auth: auth, outbox: box, store: InMemoryOfflineStore())),
      ChangeNotifierProvider<RouteCallState>.value(value: state),
    ],
    child: const MaterialApp(home: Scaffold(body: RouteCallScheduleScreen())),
  ));
  await tester.pumpAndSettle();
  return state;
}

void main() {
  testWidgets('lists scheduled customers from the downloaded data, numbered in route order', (tester) async {
    await _pumpScreen(tester);

    expect(find.text('Aling Nena Sari-Sari Store'), findsOneWidget);
    expect(find.text('Ate Lorna Grocery'), findsOneWidget);
    expect(find.text('Tindahan ni Mang Pepe'), findsNothing, reason: 'unscheduled');
    expect(find.text('01'), findsOneWidget);
    expect(find.text('04'), findsOneWidget);
    expect(find.text('Displaying 4 Customer'), findsOneWidget);
  });

  testWidgets('marks a customer with a matching order as Done', (tester) async {
    await _pumpScreen(tester, orders: [
      {
        'customer_number': 'DEMO0002',
        'control_number': 'CN-DEMO0002',
        'sequence_number': '000002',
        'call_date': '2026-11-18 00:00:00.000',
      }
    ]);

    expect(find.text('Done'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('routeCall-DEMO0002')), matching: find.text('Done')), findsOneWidget);
  });

  testWidgets('switching to Unscheduled shows only unscheduled customers', (tester) async {
    await _pumpScreen(tester);

    await tester.tap(find.byKey(const Key('scheduleFilter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unscheduled').last);
    await tester.pumpAndSettle();

    expect(find.text('Tindahan ni Mang Pepe'), findsOneWidget);
    expect(find.text('Aling Nena Sari-Sari Store'), findsNothing);
    expect(find.text('Displaying 1 Customer'), findsOneWidget);
  });

  testWidgets('search narrows the list by outlet name', (tester) async {
    await _pumpScreen(tester);

    await tester.enterText(find.byKey(const Key('customerSearch')), 'grocery');
    await tester.pumpAndSettle();

    expect(find.text('Ate Lorna Grocery'), findsOneWidget);
    expect(find.text('JM Mini Mart'), findsNothing);
  });

  testWidgets('tapping a customer opens Customer Master Data', (tester) async {
    await _pumpScreen(tester);

    await tester.tap(find.byKey(const Key('routeCall-DEMO0001')));
    await tester.pumpAndSettle();

    expect(find.text('Customer Master Data'), findsOneWidget);
    expect(find.text('Aling Nena Sari-Sari Store'), findsOneWidget);
    expect(find.byKey(const Key('startCall')), findsOneWidget);
  });

  testWidgets('a call started on this phone shows as ongoing, an ended one as done', (tester) async {
    final auth = signedInAuth();
    final outbox = FakeOutbox();
    final calls = CallState(auth: auth, outbox: outbox, store: InMemoryOfflineStore());
    await calls.startCall('DEMO0001');
    await _pumpScreen(tester, calls: calls, outbox: outbox);
    expect(find.descendant(of: find.byKey(const Key('routeCall-DEMO0001')), matching: find.text('Call Ongoing')),
        findsOneWidget);

    await calls.endCall({'customer_number': 'DEMO0001'});
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const Key('routeCall-DEMO0001')), matching: find.text('Done')), findsOneWidget);
  });

  testWidgets('requests saved offline show in a banner', (tester) async {
    final outbox = FakeOutbox()..online = false;
    await outbox.send('Order', '/api/v1/order/submit', {'x': 1});
    await _pumpScreen(tester, outbox: outbox);
    expect(find.text('1 saved offline, waiting to be sent'), findsOneWidget);
  });
}
