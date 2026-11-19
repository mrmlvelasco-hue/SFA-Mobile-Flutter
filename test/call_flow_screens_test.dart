import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sfa_mobile/core/offline_store.dart';
import 'package:sfa_mobile/core/outbox.dart';
import 'package:sfa_mobile/features/calls/call_navigation.dart';
import 'package:sfa_mobile/features/calls/call_state.dart';
import 'package:sfa_mobile/features/calls/customer_screen.dart';
import 'package:sfa_mobile/features/calls/signature_screen.dart';
import 'package:sfa_mobile/features/master_data/master_data_state.dart';
import 'package:sfa_mobile/features/route_calls/route_call.dart';

import 'helpers.dart';

Map<String, dynamic> _call(String status) => {
      'customer_number': 'C1',
      'outlet_name': 'UPHR - LAS PINAS',
      'owner_name': '',
      'address': 'ALABANG ZAPOTE RD.',
      'control_number': 'CN1',
      'item_number': '000020',
      'call_date': '2026-11-19 00:00:00.000',
      'sales_route': '213008',
      'sales_office': '2130',
      'credit_term': 'R030',
      'credit_balance': 792347.0,
      'account_status_desc': status,
      'delivering_plant': '2130',
    };

Map<String, dynamic> _data() => {
      'constants': {
        'allowed_ocl': '',
        'sales_offices': [
          {'sap_officeId': '2130', 'desc': 'SO Metro PB'}
        ],
      },
      'inventory': [
        {'sap_number': 'M1', 'sku': 'Cola 8oz', 'case': 'CS', 'unit_price': '150', 'type': 'FERT'},
      ],
      'pricing': [
        {'customer_number': 'C1', 'sap_number': 'M1', 'wsp': '196', 'discount_total': '-9'},
      ],
      'partners': [
        {'customer_number': 'C1', 'partner_func': 'Ship-To-Party', 'customer_partner': 'C1', 'address': 'ALABANG ZAPOTE RD.'},
      ],
      'rebates': [],
      'outlets': {},
    };

Future<(CallState, FakeOutbox)> _pump(WidgetTester tester, String accountStatus) async {
  final auth = signedInAuth();
  final masterData = MasterDataState(auth: auth, repository: FakeMasterDataRepository(), store: InMemoryOfflineStore())
    ..data = _data()
    ..dcInventory = {
      '2130': [
        {'sales_office': '2130', 'sku_desc': 'Cola 8oz', 'net_inventory': '40'}
      ]
    };
  final outbox = FakeOutbox();
  final calls = CallState(auth: auth, outbox: outbox, store: InMemoryOfflineStore());
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<Outbox>.value(value: outbox),
      ChangeNotifierProvider<MasterDataState>.value(value: masterData),
      ChangeNotifierProvider<CallState>.value(value: calls),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => pushCallScreen(context, CustomerScreen(call: RouteCall.fromJson(_call(accountStatus))),
                  name: customerRouteName),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (calls, outbox);
}

void main() {
  testWidgets('Start Call shows the call menu', (tester) async {
    final (calls, _) = await _pump(tester, 'Active');
    expect(find.text('UPHR - LAS PINAS'), findsOneWidget);
    await tester.tap(find.byKey(const Key('startCall')));
    await tester.pumpAndSettle();
    expect(calls.isOngoing('C1'), isTrue);
    expect(find.byKey(const Key('menuOutletInventory')), findsOneWidget);
    expect(find.byKey(const Key('cancelCall')), findsOneWidget);
  });

  testWidgets('Order Management needs outlet inventory first (non-NREQ)', (tester) async {
    await _pump(tester, 'Active');
    await tester.tap(find.byKey(const Key('startCall')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menuOrderManagement')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Outlet Inventory first'), findsOneWidget);
  });

  testWidgets('order flow up to the signature (NREQ customer)', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final (calls, _) = await _pump(tester, 'Mixed NREQ');
    await tester.tap(find.byKey(const Key('startCall')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menuOrderManagement')));
    await tester.pumpAndSettle();
    expect(find.text('Order Management'), findsOneWidget);

    await tester.tap(find.byKey(const Key('addOrder')));
    await tester.pumpAndSettle();
    expect(find.text('Cola 8oz'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('skuQty-M1')), '2');
    await tester.pump();
    await tester.tap(find.byKey(const Key('addOrderDone')));
    await tester.pumpAndSettle();

    final draft = calls.record('C1')!.draft!;
    expect(draft.lines.single.quantity, 2);
    expect(draft.lines.single.netInventory, 40);
    expect(find.text('PHP 374.00'), findsOneWidget); // (196 - 9) x 2

    await tester.tap(find.byKey(const Key('orderNext')));
    await tester.pumpAndSettle();
    expect(find.text('Misc Discount'), findsOneWidget);
    await tester.tap(find.byKey(const Key('discountSkip')));
    await tester.pumpAndSettle();
    expect(find.text('Order Summary'), findsOneWidget);
    expect(find.byKey(const Key('summaryTotal')), findsOneWidget);

    await tester.tap(find.byKey(const Key('summarySubmit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    expect(find.byType(SignatureScreen), findsOneWidget);
  });
}
