import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sfa_mobile/core/api_client.dart';
import 'package:sfa_mobile/core/offline_store.dart';
import 'package:sfa_mobile/features/calls/call_state.dart';
import 'package:sfa_mobile/features/calls/order_draft.dart';
import 'package:sfa_mobile/features/calls/outlet_inventory_screen.dart';

import 'helpers.dart';

final _now = DateTime(2026, 11, 19, 9, 30);
DateTime _clock() => _now;

final _routeCall = <String, dynamic>{
  'customer_number': 'C1',
  'control_number': 'CN1',
  'item_number': '000020',
  'call_date': '2026-11-19 00:00:00.000',
  'sales_route': '213008',
  'sales_office': '2130',
  'credit_term': 'R030',
  'delivering_plant': '2130',
};

CallState _state(FakeOutbox outbox, InMemoryOfflineStore store) =>
    CallState(auth: signedInAuth(clock: _clock), outbox: outbox, store: store, clock: _clock);

OrderDraft _draftOf(CallState state) {
  final draft = state.draftFor('C1',
      routeCall: _routeCall,
      shipTos: const [ShipTo(address: 'Main St', partnerNumber: 'C1')],
      salesOffices: const [
        {'sap_officeId': '2130'}
      ]);
  draft.lines.add(OrderLine(
      sapNumber: 'M1', description: 'Cola 8oz', unit: 'CS', wsp: 196, discountTotal: -9, pickupDiscount: 0, netInventory: 40, quantity: 2));
  draft.discountsChosen = true;
  return draft;
}

void main() {
  test('one call at a time; cancel only before outlet inventory / order', () async {
    final state = _state(FakeOutbox(), InMemoryOfflineStore());
    expect(await state.startCall('C1'), isTrue);
    expect(state.isOngoing('C1'), isTrue);
    expect(state.record('C1')!.startTime, '2026-11-19 09:30:00');
    expect(await state.startCall('C2'), isFalse);
    expect(state.canCancel('C1'), isTrue);
    await state.cancelCall('C1');
    expect(state.record('C1'), isNull);
    expect(await state.startCall('C2'), isTrue);
  });

  test('draft defaults: first ship-to, the DC of the delivering plant, delivery in 2-3 days', () async {
    final state = _state(FakeOutbox(), InMemoryOfflineStore());
    await state.startCall('C1');
    final draft = _draftOf(state);
    expect(draft.shipToAddress, 'Main St');
    expect(draft.distributionCenter, '2130');
    expect(draft.deliveryDate, DateTime(2026, 11, 21));
  });

  test('outlet inventory sends the changes to addNew and marks today done', () async {
    final outbox = FakeOutbox();
    final state = _state(outbox, InMemoryOfflineStore());
    await state.startCall('C1');
    final before = [OutletRow(sapNumber: 'M1', description: 'Cola', caseConfig: 'CS', unitPrice: '196', quantity: 3)];
    final after = [
      OutletRow(sapNumber: 'M1', description: 'Cola', caseConfig: 'CS', unitPrice: '196', quantity: 5),
      OutletRow(sapNumber: 'M2', description: 'Cola 1L', caseConfig: 'CS', unitPrice: '300', quantity: 1),
    ];
    final changes = outletInventoryChanges(before, after);
    expect(changes.data.map((d) => '${d['materials_id']}:${d['quantity']}'), ['M1:5', 'M2:1']);
    expect(outletInventoryChanges(after, before).deleted, [
      {'materials_id': 'M2', 'case_config': 'CS'}
    ]);

    final result = await state.saveOutletInventory(
        routeCall: _routeCall, counts: {'fulls': [], 'empties': []}, productData: changes.data, productDeleted: changes.deleted);
    expect(result!.sent, isTrue);
    expect(outbox.posted.single, '/api/v1/outlet-inventory/sku/addNew');
    final customer = (outbox.bodies.single['customer_data'] as List).single as Map;
    expect(customer['employee_id'], 'E1');
    expect(customer['sales_route'], '213008');
    expect(customer['item_number'], '000020');
    expect(customer['inventory_date_time'], '2026-11-19 09:30:00');
    expect(state.outletInventoryDoneToday('C1'), isTrue);
    expect(state.canCancel('C1'), isFalse);
  });

  test('submit order then end call -- online', () async {
    final outbox = FakeOutbox();
    final state = _state(outbox, InMemoryOfflineStore());
    await state.startCall('C1');
    _draftOf(state);
    final result = await state.submitOrder(routeCall: _routeCall, creditTerm: 'R030', signature: 'data:x', remarks: '');
    expect(result.sent, isTrue);
    expect(state.record('C1')!.orderStatus, OrderStatus.submitted);
    final body = outbox.bodies.single;
    expect(outbox.posted.single, '/api/v1/order/submit');
    expect(body['starttime'], '2026-11-19 09:30:00');
    expect(body['customer_signature'], 'data:x');
    expect(body['total_estimated_amount'], 196 * 2 - 18);
    expect((jsonDecode(body['orders'] as String) as List).length, 1);

    await state.endCall(_routeCall);
    expect(outbox.posted.last, '/api/v1/route/end-call');
    expect(outbox.bodies.last['sequence_number'], '000020');
    expect(state.isCompleted('C1'), isTrue);
    expect(state.ongoingCustomer, isNull);
  });

  test('offline: the order is queued and the call can still end', () async {
    final outbox = FakeOutbox()..online = false;
    final state = _state(outbox, InMemoryOfflineStore());
    await state.startCall('C1');
    _draftOf(state);
    final result = await state.submitOrder(routeCall: _routeCall, creditTerm: 'R030', signature: 'data:x', remarks: '');
    expect(result.queued, isTrue);
    expect(state.record('C1')!.orderStatus, OrderStatus.queued);
    await state.endCall(_routeCall);
    expect(outbox.pendingCount, 2); // order, then end call -- sent in that order later

    outbox.online = true;
    expect(await outbox.flush(), 2);
    expect(outbox.posted, ['/api/v1/order/submit', '/api/v1/route/end-call']);
  });

  test('a rejected order is kept as failed and can be sent again', () async {
    final outbox = FakeOutbox()..answer = (_, __) => ApiEnvelope(code: 422, status: 'Error', message: 'Out of Stock');
    final state = _state(outbox, InMemoryOfflineStore());
    await state.startCall('C1');
    _draftOf(state);
    await state.submitOrder(routeCall: _routeCall, creditTerm: 'R030', signature: 'data:x', remarks: '');
    expect(state.record('C1')!.orderStatus, OrderStatus.failed);
    expect(state.record('C1')!.orderMessage, 'Out of Stock');
    expect(outbox.pendingCount, 0);
  });

  test('ending a call without an order sends nothing', () async {
    final outbox = FakeOutbox();
    final state = _state(outbox, InMemoryOfflineStore());
    await state.startCall('C1');
    expect(await state.endCall(_routeCall), isNull);
    expect(outbox.posted, isEmpty);
    expect(state.isCompleted('C1'), isTrue);
  });

  test("today's calls survive a restart; yesterday's don't", () async {
    final store = InMemoryOfflineStore();
    final state = _state(FakeOutbox(), store);
    await state.startCall('C1');
    _draftOf(state);
    await state.draftChanged();

    final again = _state(FakeOutbox(), store);
    await again.load();
    expect(again.isOngoing('C1'), isTrue);
    expect(again.record('C1')!.draft!.lines.single.quantity, 2);

    final tomorrow = CallState(
        auth: signedInAuth(clock: () => DateTime(2026, 11, 20)),
        outbox: FakeOutbox(),
        store: store,
        clock: () => DateTime(2026, 11, 20));
    await tomorrow.load();
    expect(tomorrow.calls, isEmpty);
  });
}
