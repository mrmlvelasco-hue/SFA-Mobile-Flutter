import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_colors.dart';
import '../../core/formatting.dart';
import '../master_data/master_data_state.dart';
import '../placeholder/coming_soon_screen.dart';
import '../route_calls/route_call.dart';
import 'call_navigation.dart';
import 'call_rules.dart';
import 'call_state.dart';
import 'order_management_screen.dart';
import 'outlet_inventory_screen.dart';

/// Customer Master Data with Start / Cancel / End Call and the call menu -- the RN app's
/// CustomerMasterDataComponent + the call's activity menu.
class CustomerScreen extends StatelessWidget {
  const CustomerScreen({super.key, required this.call});

  final RouteCall call;

  @override
  Widget build(BuildContext context) {
    final calls = context.watch<CallState>();
    final ctx = CallContext(call);
    final record = calls.record(call.customerNumber);
    final ongoing = calls.isOngoing(call.customerNumber);
    final completed = calls.isCompleted(call.customerNumber);
    final otherOngoing = calls.ongoingCustomer != null && calls.ongoingCustomer != call.customerNumber;

    return Scaffold(
      appBar: AppBar(title: const Text('Customer Master Data')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _CustomerCard(ctx: ctx),
          const SizedBox(height: 12),
          if (record != null && record.orderStatus != OrderStatus.none) _OrderStatusBanner(record: record),
          if (completed)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('This call is done for today.',
                  textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, color: Colors.green)),
            )
          else if (!ongoing) ...[
            if (otherOngoing)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Another call is ongoing. End it before starting this one.',
                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.red2)),
              ),
            FilledButton.icon(
              key: const Key('startCall'),
              onPressed: otherOngoing ? null : () => calls.startCall(call.customerNumber),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start Call'),
            ),
          ] else ...[
            Text('Call started ${record?.startTime ?? ''}',
                style: const TextStyle(color: AppColors.grayLight, fontSize: 12), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            _menu(context, ctx, calls),
            const SizedBox(height: 16),
            Row(
              children: [
                if (calls.canCancel(call.customerNumber))
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('cancelCall'),
                      onPressed: () => _cancel(context, calls),
                      child: const Text('Cancel Call'),
                    ),
                  ),
                if (calls.canCancel(call.customerNumber)) const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const Key('endCall'),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.red2),
                    onPressed: () => _end(context, ctx, calls),
                    child: const Text('End Call'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _menu(BuildContext context, CallContext ctx, CallState calls) {
    Widget tile(String label, IconData icon, VoidCallback onTap, {String? subtitle, Key? key}) => Card(
          child: ListTile(
            key: key,
            leading: Icon(icon, color: AppColors.primary),
            title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: subtitle == null ? null : Text(subtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: onTap,
          ),
        );
    void soon(String title) => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ComingSoonScreen(title: title, note: 'Not ported from the React Native app yet.'),
        ));
    final inventoryDone = calls.outletInventoryDoneToday(ctx.customerNumber);
    return Column(
      children: [
        tile('Outlet Inventory', Icons.inventory_2_outlined, () => pushCallScreen(context, OutletInventoryScreen(ctx: ctx)),
            subtitle: inventoryDone ? 'Saved today' : null, key: const Key('menuOutletInventory')),
        tile('Order Management', Icons.shopping_cart_outlined, () => _openOrders(context, ctx, calls),
            key: const Key('menuOrderManagement')),
        tile('Sales Return', Icons.assignment_return_outlined, () => soon('Sales Return')),
        tile('Subsidiary Ledger', Icons.receipt_long_outlined, () => soon('Subsidiary Ledger')),
        tile('Payment Collection', Icons.payments_outlined, () => soon('Payment Collection')),
        tile('Empties Pullout', Icons.recycling, () => soon('Empties Pullout')),
      ],
    );
  }

  Future<void> _openOrders(BuildContext context, CallContext ctx, CallState calls) async {
    final record = calls.record(ctx.customerNumber);
    if (record != null && record.hasOrder) {
      await messageDialog(context, 'Order Management', 'An order was already sent for this call.');
      return;
    }
    if (outletInventoryRequired(ctx.raw) && !calls.outletInventoryDoneToday(ctx.customerNumber)) {
      await messageDialog(context, 'Outlet Inventory', 'Please do the Outlet Inventory first before adding orders.');
      return;
    }
    if (!context.mounted) return;
    await pushCallScreen(context, OrderManagementScreen(ctx: ctx));
  }

  Future<void> _cancel(BuildContext context, CallState calls) async {
    if (await confirmDialog(context, 'Cancel Call', 'Are you sure you want to cancel this call?')) {
      await calls.cancelCall(call.customerNumber);
    }
  }

  Future<void> _end(BuildContext context, CallContext ctx, CallState calls) async {
    final record = calls.record(ctx.customerNumber);
    final withOrder = record?.hasOrder ?? false;
    final message = withOrder
        ? 'End the call with ${ctx.text('outlet_name')}?'
        : 'No order was sent for this call. End it without an order?\n\n'
            '(The RN app asks for a no-order reason here -- the Feedback screen is not ported yet, '
            'so the call is ended on this phone only.)';
    if (!await confirmDialog(context, 'End Call', message)) return;
    final result = await calls.endCall(ctx.raw);
    if (!context.mounted) return;
    if (result != null && !result.queued && !result.envelope.isSuccess) {
      await messageDialog(context, 'End Call', 'The server did not accept the end of call: ${result.envelope.message}');
    } else if (result != null && result.queued) {
      await messageDialog(context, 'End Call', 'No connection -- the end of call is saved and will be sent automatically.');
    }
    if (context.mounted) Navigator.of(context).pop();
  }
}

class _OrderStatusBanner extends StatelessWidget {
  const _OrderStatusBanner({required this.record});
  final CallRecord record;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (record.orderStatus) {
      OrderStatus.submitted => (Colors.green, Icons.check_circle),
      OrderStatus.queued => (AppColors.orange, Icons.schedule),
      _ => (AppColors.red2, Icons.error_outline),
    };
    return Card(
      color: color.withAlpha(30),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(switch (record.orderStatus) {
          OrderStatus.submitted => 'Order sent',
          OrderStatus.queued => 'Order waiting for connection',
          _ => 'Order not accepted',
        }),
        subtitle: Text(record.orderMessage ?? ''),
      ),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.ctx});
  final CallContext ctx;

  @override
  Widget build(BuildContext context) {
    String money(String key) {
      final v = asNum(ctx.raw[key]);
      return v == null ? '' : numberWithDecimals(v);
    }

    final rows = <(String, String)>[
      ('Customer No.', ctx.customerNumber),
      ('Owner', ctx.text('owner_name')),
      ('Contact Person', ctx.text('contact_person_name')),
      ('Contact No.', ctx.text('contact_number')),
      ('Address', ctx.text('address')),
      ('Credit Term', ctx.text('credit_term')),
      ('Credit Limit', money('credit_limit')),
      ('Credit Balance', money('credit_balance')),
      ('Payment Type', ctx.text('payment_type')),
      ('Price Zone', ctx.text('price_zone')),
      ('Channel', ctx.text('channel_desc')),
      ('Sub-channel', ctx.text('subchannel_desc')),
      ('Distribution Type', ctx.text('distribution_type_desc')),
      ('Account Status', ctx.text('account_status_desc')),
    ];
    final masterData = context.watch<MasterDataState>();
    final stockNote = masterData.dcInventoryError;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ctx.text('outlet_name'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            for (final (label, value) in rows)
              if (value.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 120, child: Text(label, style: const TextStyle(color: AppColors.grayLight))),
                      Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
                    ],
                  ),
                ),
            if (stockNote != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('DC stock not loaded: $stockNote', style: const TextStyle(color: AppColors.red2, fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }
}
