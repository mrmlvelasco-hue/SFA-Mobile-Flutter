import 'package:flutter_test/flutter_test.dart';
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

  test('fromDownload() reads route_calls.list and order_details from the downloaded data', () {
    final state = RouteCallState.fromDownload(downloadDataWith(orders: [_order('DEMO0002', '000002')]));

    expect(state.calls, hasLength(5));
    expect(state.isDone('DEMO0002'), isTrue);
  });

  test('fromDownload() copes with missing data', () {
    final state = RouteCallState.fromDownload(const {});
    expect(state.calls, isEmpty);
    expect(state.visible, isEmpty);
  });

  test('Scheduled (the default) shows scheduled calls sorted by item number', () {
    final state = RouteCallState.fromDownload(downloadDataWith());

    expect(state.filter, RouteCallFilter.scheduled);
    expect(_numbers(state.visible), ['DEMO0001', 'DEMO0002', 'DEMO0003', 'DEMO0004']);
  });

  test('Unscheduled shows only item number 0 calls', () {
    final state = RouteCallState.fromDownload(downloadDataWith());

    state.setFilter(RouteCallFilter.unscheduled);

    expect(_numbers(state.visible), ['DEMO0005']);
  });

  test('search filters by outlet name, case-insensitively', () {
    final state = RouteCallState.fromDownload(downloadDataWith());

    state.setSearch('  mini MART ');

    expect(_numbers(state.visible), ['DEMO0002']);
  });

  test('a customer with several calls today is listed once (first call wins)', () {
    final state = RouteCallState.fromDownload(downloadDataWith(calls: [
      routeCallJson('C1', 'Store One', '000002', control: 'A'),
      routeCallJson('C1', 'Store One', '000005', control: 'B'),
      routeCallJson('C2', 'Store Two', '000001'),
    ]));

    expect(_numbers(state.visible), ['C2', 'C1']);
    expect(state.visible.last.controlNumber, 'A-C1');
  });

  test('a call is done only when an order matches customer, control number, item number and date', () {
    final state = RouteCallState.fromDownload(downloadDataWith(orders: [
      _order('DEMO0002', '000002'),
      _order('DEMO0001', '000009'),
      _order('DEMO0003', '000003', date: '2026-11-17 00:00:00.000'),
      _order('DEMO0004', '000004', control: 'OTHER'),
    ]));

    expect(state.isDone('DEMO0002'), isTrue);
    expect(state.isDone('DEMO0001'), isFalse, reason: 'different item number');
    expect(state.isDone('DEMO0003'), isFalse, reason: 'order from another day');
    expect(state.isDone('DEMO0004'), isFalse, reason: 'different control number');
  });
}

Map<String, dynamic> _order(String customer, String sequence, {String? control, String date = '2026-11-18 00:00:00.000'}) => {
      'customer_number': customer,
      'control_number': control ?? 'CN-$customer',
      'sequence_number': sequence,
      'call_date': date,
    };
