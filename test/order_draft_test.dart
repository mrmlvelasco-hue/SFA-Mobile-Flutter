import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sfa_mobile/features/calls/call_rules.dart';
import 'package:sfa_mobile/features/calls/order_draft.dart';
import 'package:sfa_mobile/features/calls/sku_catalog.dart';

OrderLine _line(String sap, {num wsp = 196, num discount = -9, num pickup = -3, num net = 500, int qty = 2}) => OrderLine(
      sapNumber: sap,
      description: 'SKU $sap',
      unit: 'CS',
      wsp: wsp,
      discountTotal: discount,
      pickupDiscount: pickup,
      netInventory: net,
      quantity: qty,
    );

Map<String, dynamic> _routeCall({String creditTerm = 'R030'}) => {
      'customer_number': '1000002375',
      'control_number': '2130038720',
      'item_number': '000020',
      'call_date': '2026-11-19 00:00:00.000',
      'credit_term': creditTerm,
      'delivering_plant': '2130',
    };

Map<String, dynamic> _payload(OrderDraft draft, {String creditTerm = 'R030', String remarks = ''}) => draft.submitPayload(
      employeeId: 'E1',
      routeCall: _routeCall(creditTerm: creditTerm),
      creditTerm: creditTerm,
      startTime: '2026-11-19 09:00:00',
      startLat: 0,
      startLng: 0,
      endTime: '2026-11-19 09:20:00',
      endLat: 0,
      endLng: 0,
      signature: 'data:image/png;base64,AAA',
      remarks: remarks,
      mobileOrderId: 'id-1',
    );

void main() {
  group('OrderLine', () {
    test('out of stock when the DC has none or fewer than ordered', () {
      expect(_line('A', net: 500, qty: 2).isOutOfStock, '0');
      expect(_line('A', net: 2, qty: 2).isOutOfStock, '0');
      expect(_line('A', net: 1, qty: 2).isOutOfStock, '1');
      expect(_line('A', net: 0, qty: 1).isOutOfStock, '1');
    });

    test('list total truncates the price; summary total does not', () {
      final l = _line('A', wsp: 90.75, discount: -10, qty: 2);
      expect(l.listTotal, (90 - 10) * 2);
      expect(l.summaryTotal, closeTo(90.75 * 2 - 20, 1e-9));
    });
  });

  group('OrderDraft totals', () {
    test('net gross, pick-up only for Pick Up orders, rebate, estimated total', () {
      final draft = OrderDraft(lines: [_line('A', qty: 2), _line('B', wsp: 295, discount: -9, pickup: -5, qty: 1)]);
      expect(draft.netGross, 196 * 2 + 295 - 9 * 2 - 9);
      expect(draft.availablePickupDiscount, 0); // Delivery
      draft.orderType = OrderType.pickUp;
      expect(draft.availablePickupDiscount, 3 * 2 + 5);
      expect(draft.pickupDiscount, 0); // not chosen
      draft.pickupSelected = true;
      draft.rebateCode = 'R1';
      draft.rebateClaim = 50;
      expect(draft.totalEstimated, draft.netGross - 11 - 50);
    });

    test('addLines replaces the quantity of an SKU already on the order', () {
      final draft = OrderDraft(lines: [_line('A', qty: 2)]);
      draft.addLines([_line('A', qty: 5), _line('B')]);
      expect(draft.lines.map((l) => '${l.sapNumber}:${l.quantity}'), ['A:5', 'B:2']);
    });

    test('rebate claim must be > 0 and not over the balance', () {
      expect(OrderDraft.rebateClaimValid(0, 100), isFalse);
      expect(OrderDraft.rebateClaimValid(100, 100), isTrue);
      expect(OrderDraft.rebateClaimValid(101, 100), isFalse);
    });
  });

  group('delivery date', () {
    test('defaults to today + 2, or + 3 when that is a Sunday or Monday', () {
      expect(OrderDraft.defaultDeliveryDate(DateTime(2026, 11, 19)), DateTime(2026, 11, 21)); // Thu -> Sat
      expect(OrderDraft.defaultDeliveryDate(DateTime(2026, 11, 20)), DateTime(2026, 11, 23)); // Fri -> Sun -> Mon
      expect(OrderDraft.defaultDeliveryDate(DateTime(2026, 11, 21)), DateTime(2026, 11, 24)); // Sat -> Mon -> Tue
    });

    test('Sunday or earlier than two days asks for confirmation', () {
      final today = DateTime(2026, 11, 19);
      expect(OrderDraft.deliveryDateWarning(DateTime(2026, 11, 22), today), contains('Sunday'));
      expect(OrderDraft.deliveryDateWarning(DateTime(2026, 11, 20), today), contains('earlier'));
      expect(OrderDraft.deliveryDateWarning(DateTime(2026, 11, 21), today), isNull);
    });
  });

  group('submitPayload', () {
    test('has every field order/submit needs, built like the RN app', () {
      final draft = OrderDraft(
        shipToAddress: 'ALABANG ZAPOTE RD.',
        shipToPartner: '1000002375',
        distributionCenter: '2130',
        deliveringPlant: '2130',
        deliveryDate: DateTime(2026, 11, 21),
        lines: [_line('000000009010000001', qty: 2)],
      )..discountsChosen = true;
      final p = _payload(draft);
      expect(p['employee_id'], 'E1');
      expect(p['sequence_number'], '000020');
      expect(p['customer_partner'], ''); // ships to the customer itself
      expect(p['call_date'], '2026-11-19 00:00:00.000');
      expect(p['order_type'], 'ZA01');
      expect(p['transaction_type'], 'DELIVERY');
      expect(p['delivery_date'], '2026-11-21');
      expect(p['remarks'], '.');
      expect(p['final_total'], '0');
      expect(p['total_rebate'], '0');
      expect(p['total_pickup_discount'], '0');
      expect(p['empties_pullout'], '[]');
      expect(p['total_estimated_amount'], 196 * 2 - 9 * 2);
      final orders = jsonDecode(p['orders'] as String) as List;
      expect(orders.single, {
        'materials_numbers': '000000009010000001',
        'quantity': 2,
        'is_outofstock': '0',
        'is_replacement': '0',
        'promo_code': '0',
        'discount': -9,
        'price_master': 196,
        'total_price': 392,
        'is_freeitem': '0',
        'free_sku': '',
        'free_sku_unit': '',
        'freeitem_quantity': 0,
        'getitem_from': '0',
        'unit': 'CS',
        'pickup_discount': 0,
      });
    });

    test('COD is ZA02; a pick-up order with its discount and a rebate', () {
      final draft = OrderDraft(
        shipToAddress: 'Other branch',
        shipToPartner: '2000000001',
        distributionCenter: '2130',
        orderType: OrderType.pickUp,
        lines: [_line('A', qty: 2, pickup: -3)],
        pickupSelected: true,
        rebateCode: 'RB1',
        rebateClaim: 20,
        discountsChosen: true,
      );
      final p = _payload(draft, creditTerm: 'COD', remarks: 'call before');
      expect(p['order_type'], 'ZA02');
      expect(p['transaction_type'], 'PICK UP');
      expect(p['customer_partner'], '2000000001');
      expect(p['total_pickup_discount'], 6);
      expect(p['total_rebate'], 20);
      expect(p['rebate_code'], 'RB1');
      expect(p['remarks'], 'call before');
      expect(p['delivering_plant'], '2130'); // falls back to the DC
      expect((jsonDecode(p['orders'] as String) as List).single['pickup_discount'], 6);
    });

    test('saved and restored as JSON', () {
      final draft = OrderDraft(shipToAddress: 'X', distributionCenter: '2130', deliveryDate: DateTime(2026, 11, 21),
          orderType: OrderType.pickUp, lines: [_line('A')], rebateCode: 'R', rebateClaim: 5);
      final back = OrderDraft.fromJson(jsonDecode(jsonEncode(draft.toJson())) as Map<String, dynamic>);
      expect(back.toJson(), draft.toJson());
    });
  });

  group('call rules', () {
    test('jsTruthy follows JavaScript', () {
      expect(jsTruthy(''), isFalse);
      expect(jsTruthy(null), isFalse);
      expect(jsTruthy(0), isFalse);
      expect(jsTruthy('0'), isTrue);
      expect(jsTruthy('1'), isTrue);
    });

    test('outlet inventory is not required for NREQ accounts', () {
      expect(outletInventoryRequired({'account_status_desc': 'Mixed NREQ'}), isFalse);
      expect(outletInventoryRequired({'account_status_desc': 'Active'}), isTrue);
    });

    test('Add Order is blocked with no OCL and no balance', () {
      expect(addOrderBlockedReason({'credit_balance': 0}, ''), isNotNull);
      expect(addOrderBlockedReason({'credit_balance': 0}, '1'), isNull);
      expect(addOrderBlockedReason({'credit_balance': 10}, ''), isNull);
    });

    test('credit check', () {
      CreditOutcome check(String term, num balance, dynamic ocl, num amount) => creditCheck(
              creditTerm: term, creditBalance: balance, allowedOcl: ocl, amount: amount, deliveryDate: DateTime(2026, 11, 21))
          .outcome;
      expect(check('COD', 0, '', 9999), CreditOutcome.proceed);
      expect(check('R030', 100, '', 50), CreditOutcome.proceed);
      expect(check('R030', 100, '', 150), CreditOutcome.blocked);
      expect(check('R030', 100, '1', 150), CreditOutcome.warnThenProceed);
      expect(check('R030', 0, '1', 10), CreditOutcome.warnThenProceed);
      expect(creditCheck(creditTerm: 'R030', creditBalance: 0, allowedOcl: '1', amount: 1, deliveryDate: DateTime(2026, 11, 21))
          .message, contains('11/21/2026'));
    });

    test('ship-to choices come from Ship-To-Party partners, one per address', () {
      final data = {
        'partners': [
          {'customer_number': 'C1', 'partner_func': 'Ship-To-Party', 'customer_partner': 'C1', 'address': 'Main'},
          {'customer_number': 'C1', 'partner_func': 'Ship-To-Party', 'customer_partner': 'C9', 'address': 'Branch'},
          {'customer_number': 'C1', 'partner_func': 'Ship-To-Party', 'customer_partner': 'C8', 'address': 'Main'},
          {'customer_number': 'C1', 'partner_func': 'Bill-To-Party', 'customer_partner': 'C7', 'address': 'Bill'},
          {'customer_number': 'C2', 'partner_func': 'Ship-To-Party', 'customer_partner': 'C2', 'address': 'Other'},
        ],
      };
      expect(shipTosFor(data, 'C1').map((s) => '${s.partnerNumber}:${s.address}'), ['C1:Main', 'C9:Branch']);
    });
  });

  group('SKU catalog', () {
    final data = {
      'inventory': [
        {'sap_number': 'E1', 'sku': 'Empty bottle', 'case': 'BOT', 'unit_price': '2', 'type': 'LER1'},
        {'sap_number': 'M1', 'sku': 'Cola 8oz', 'case': 'CS', 'unit_price': '150', 'type': 'FERT'},
        {'sap_number': 'M2', 'sku': 'Cola 1L', 'case': 'CS', 'unit_price': '300', 'type': 'FERT'},
      ],
      'pricing': [
        {'customer_number': 'C1 ', 'sap_number': 'm1', 'wsp': '196', 'discount_total': '-9'},
        {'customer_number': 'C2', 'sap_number': 'M2', 'wsp': '999', 'discount_total': '0'},
      ],
      'pickUpDiscount': [
        {'customer_number': 'C1', 'sap_number': 'M1', 'pickup_discount': '-3'},
      ],
    };

    test('fulls only, priced for the customer, unit price as fallback', () {
      final skus = buildSkuCatalog(data, 'C1');
      expect(skus.map((s) => s.sapNumber), ['M1', 'M2']);
      expect(skus[0].wsp, 196);
      expect(skus[0].discountTotal, -9);
      expect(skus[0].pickupDiscount, -3);
      expect(skus[1].wsp, 300);
    });

    test('DC stock by description; null for a DC without a list', () {
      final grouped = groupStockBySalesOffice([
        [
          {'sales_office': '2130', 'sku_desc': 'Cola 8oz', 'net_inventory': '40'}
        ]
      ]);
      expect(stockByDescription(grouped, '2130'), {'Cola 8oz': 40});
      expect(stockByDescription(grouped, '9999'), isNull);
    });

    test('search: contains the text and starts with the same letter', () {
      expect(matchesSkuSearch('Cola 8oz', 'cola'), isTrue);
      expect(matchesSkuSearch('Pepsi Cola', 'cola'), isFalse);
      expect(matchesSkuSearch('Cola 8oz', ''), isTrue);
    });
  });
}
