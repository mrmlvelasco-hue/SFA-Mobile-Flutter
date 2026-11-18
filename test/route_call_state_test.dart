import 'package:flutter_test/flutter_test.dart';
import 'package:sfa_mobile/core/api_client.dart';
import 'package:sfa_mobile/features/auth/auth_state.dart';
import 'package:sfa_mobile/features/route_calls/route_call.dart';
import 'package:sfa_mobile/features/route_calls/route_call_state.dart';

import 'helpers.dart';

List<String> _numbers(List<RouteCall> calls) => calls.map((c) => c.customerNumber).toList();

void main() {
  group('RouteCall.isUnscheduled mirrors the RN app\'s JS loose `item_number == 0`', () {
    RouteCall call(String? item) => RouteCall.fromJson(routeCallJson('C', 'X', item));

    test('zero-ish values are unscheduled', () {
      for (final v in ['000000', '0', '', ' 0 ']) {
        expect(call(v).isUnscheduled, isTrue, reason: 'item_number $v');
      }
    });

    test('positive, null and non-numeric values are scheduled', () {
      for (final v in ['000001', '12', null, 'abc']) {
        expect(call(v).isScheduled, isTrue, reason: 'item_number $v');
      }
    });
  });

  test('load() fetches today\'s calls, then order details for those customers', () async {
    final repo = FakeRouteCallRepository();
    final state = RouteCallState(auth: signedInAuth(), repository: repo);

    await state.load();

    expect(state.status, LoadStatus.loaded);
    expect(state.calls, hasLength(5));
    expect(repo.lastOrderCustomers, containsAll(['DEMO0001', 'DEMO0005']));
    expect(state.downloadData['constants'], {'app_version': '1.0.0'});
  });

  test('Scheduled (the default) shows scheduled calls sorted by item number', () async {
    final state = RouteCallState(auth: signedInAuth(), repository: FakeRouteCallRepository());
    await state.load();

    expect(state.filter, RouteCallFilter.scheduled);
    expect(_numbers(state.visible), ['DEMO0001', 'DEMO0002', 'DEMO0003', 'DEMO0004']);
  });

  test('Unscheduled shows only item number 0 calls', () async {
    final state = RouteCallState(auth: signedInAuth(), repository: FakeRouteCallRepository());
    await state.load();

    state.setFilter(RouteCallFilter.unscheduled);

    expect(_numbers(state.visible), ['DEMO0005']);
  });

  test('search filters by outlet name, case-insensitively', () async {
    final state = RouteCallState(auth: signedInAuth(), repository: FakeRouteCallRepository());
    await state.load();

    state.setSearch('  mini MART ');

    expect(_numbers(state.visible), ['DEMO0002']);
  });

  test('a customer with several calls today is listed once (first call wins)', () async {
    final repo = FakeRouteCallRepository(calls: [
      routeCallJson('C1', 'Store One', '000002', control: 'A'),
      routeCallJson('C1', 'Store One', '000005', control: 'B'),
      routeCallJson('C2', 'Store Two', '000001'),
    ]);
    final state = RouteCallState(auth: signedInAuth(), repository: repo);
    await state.load();

    expect(_numbers(state.visible), ['C2', 'C1']);
    expect(state.visible.last.controlNumber, 'A-C1');
  });

  test('a call is done only when an order matches customer, control number, item number and date', () async {
    final order = {
      'customer_number': 'DEMO0002',
      'control_number': 'CN-DEMO0002',
      'sequence_number': '000002',
      'call_date': '2026-11-18 00:00:00.000',
    };
    final state = RouteCallState(
      auth: signedInAuth(),
      repository: FakeRouteCallRepository(orders: [
        order,
        {...order, 'customer_number': 'DEMO0001', 'control_number': 'CN-DEMO0001', 'sequence_number': '000009'},
        {...order, 'customer_number': 'DEMO0003', 'control_number': 'CN-DEMO0003', 'sequence_number': '000003', 'call_date': '2026-11-17 00:00:00.000'},
        {...order, 'customer_number': 'DEMO0004', 'control_number': 'OTHER', 'sequence_number': '000004'},
      ]),
    );
    await state.load();

    expect(state.isDone('DEMO0002'), isTrue);
    expect(state.isDone('DEMO0001'), isFalse, reason: 'different item number');
    expect(state.isDone('DEMO0003'), isFalse, reason: 'order from another day');
    expect(state.isDone('DEMO0004'), isFalse, reason: 'different control number');
  });

  test('a backend error is shown, not thrown', () async {
    final state = RouteCallState(
      auth: signedInAuth(),
      repository: FakeRouteCallRepository(summaryResponse: ApiEnvelope(code: 500, message: 'Attempt to read property "id" on null')),
    );

    await state.load();

    expect(state.status, LoadStatus.error);
    expect(state.errorMessage, 'Attempt to read property "id" on null');
  });

  test('an expired/rejected token signs the user out with a message', () async {
    final auth = signedInAuth();
    final state = RouteCallState(
      auth: auth,
      repository: FakeRouteCallRepository(summaryResponse: ApiEnvelope(code: 401, message: 'Unauthenticated.')),
    );

    await state.load();

    expect(auth.status, AuthStatus.signedOut);
    expect(auth.errorMessage, contains('session has expired'));
  });
}
