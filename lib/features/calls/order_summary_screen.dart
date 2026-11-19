import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/app_colors.dart';
import '../../core/formatting.dart';
import '../master_data/master_data_state.dart';
import 'call_navigation.dart';
import 'call_rules.dart';
import 'order_draft.dart';
import 'signature_screen.dart';

/// Order Summary -- the order with its discounts and estimated total, the credit check, then on
/// to the customer's signature (the RN app's OrderSummaryScreen).
class OrderSummaryScreen extends StatelessWidget {
  const OrderSummaryScreen({super.key, required this.ctx, required this.draft});
  final CallContext ctx;
  final OrderDraft draft;

  Future<void> _submit(BuildContext context) async {
    final constants = context.read<MasterDataState>().data['constants'];
    final check = creditCheck(
      creditTerm: ctx.text('credit_term'),
      creditBalance: jsParseFloat(ctx.raw['credit_balance']),
      allowedOcl: constants is Map ? constants['allowed_ocl'] : null,
      amount: draft.netGross,
      deliveryDate: draft.deliveryDate ?? DateTime.now(),
    );
    switch (check.outcome) {
      case CreditOutcome.blocked:
        await messageDialog(context, 'Warning', check.message!);
        return;
      case CreditOutcome.warnThenProceed:
        await messageDialog(context, 'Warning', check.message!);
      case CreditOutcome.proceed:
        break;
    }
    if (!context.mounted) return;
    if (!await confirmDialog(context, 'Submit Order', 'Are you sure you want to submit this order?', ok: 'Yes', cancel: 'No')) {
      return;
    }
    if (!context.mounted) return;
    await pushCallScreen(context, SignatureScreen(ctx: ctx, draft: draft));
  }

  @override
  Widget build(BuildContext context) {
    final gross = draft.lines.fold<num>(0, (s, l) => s + l.wsp * l.quantity);
    final lineDiscounts = gross - draft.netGross;
    Widget amount(String label, num value, {bool bold = false, bool less = false, Key? key}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500))),
              Text('${less && value != 0 ? '- ' : ''}${numberWithDecimals(value)}',
                  key: key, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500, fontSize: bold ? 16 : 14)),
            ],
          ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Order Summary')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(ctx.text('outlet_name'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          Text('${draft.orderType.label} on '
              '${draft.deliveryDate == null ? '-' : DateFormat('MM/dd/yyyy').format(draft.deliveryDate!)}'
              '  |  DC ${draft.distributionCenter ?? '-'}'),
          Text('Ship to: ${draft.shipToAddress ?? '-'}', style: const TextStyle(color: AppColors.grayLight)),
          const Divider(),
          for (final l in draft.lines)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(l.description, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${l.quantity} ${l.unit} x ${numberWithDecimals(l.wsp)}'
                  '${l.discountTotal != 0 ? '  less ${numberWithDecimals(l.discountTotal.abs())}/unit' : ''}'
                  '${l.isOutOfStock == '1' ? '  (out of stock)' : ''}'),
              trailing: Text(numberWithDecimals(l.summaryTotal)),
            ),
          const Divider(),
          amount('Gross Amount', gross),
          amount('SKU Discounts', lineDiscounts, less: true),
          amount('Net Gross', draft.netGross),
          amount('Pick-up Discount', draft.pickupDiscount, less: true),
          amount('Rebate${draft.rebateCode.isEmpty ? '' : ' (${draft.rebateCode})'}', draft.rebate, less: true),
          amount('Promo Discount', draft.promoDiscount, less: true),
          const Divider(),
          amount('Total Estimated Amount', draft.totalEstimated, bold: true, key: const Key('summaryTotal')),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(key: const Key('summarySubmit'), onPressed: () => _submit(context), child: const Text('Submit')),
        ),
      ),
    );
  }
}
