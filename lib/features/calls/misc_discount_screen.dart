import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_colors.dart';
import '../../core/formatting.dart';
import '../master_data/master_data_state.dart';
import 'call_navigation.dart';
import 'call_rules.dart';
import 'call_state.dart';
import 'order_draft.dart';
import 'order_summary_screen.dart';

/// Misc Discount -- pick-up discount (Pick Up orders) and rebate claim (the RN app's
/// MiscDiscountScreen). Promos are listed read-only: promo selection isn't ported yet.
class MiscDiscountScreen extends StatefulWidget {
  const MiscDiscountScreen({super.key, required this.ctx, required this.draft});
  final CallContext ctx;
  final OrderDraft draft;

  @override
  State<MiscDiscountScreen> createState() => _MiscDiscountScreenState();
}

class _MiscDiscountScreenState extends State<MiscDiscountScreen> {
  late final List<Rebate> _rebates;
  late final List<Map<String, dynamic>> _promos;
  late final TextEditingController _claim;

  OrderDraft get _draft => widget.draft;

  @override
  void initState() {
    super.initState();
    final data = context.read<MasterDataState>().data;
    _rebates = rebatesFor(data, widget.ctx.customerNumber);
    _promos = promosFor(data, widget.ctx.customerNumber);
    if (_rebates.every((r) => r.number != _draft.rebateCode)) {
      _draft.rebateCode = '';
      _draft.rebateClaim = 0;
    }
    _claim = TextEditingController(text: _draft.rebateClaim == 0 ? '' : _draft.rebateClaim.toString());
    if (_draft.availablePickupDiscount == 0) _draft.pickupSelected = false;
  }

  @override
  void dispose() {
    _claim.dispose();
    super.dispose();
  }

  Rebate? get _selectedRebate {
    for (final r in _rebates) {
      if (r.number == _draft.rebateCode) return r;
    }
    return null;
  }

  bool get _rebateValid {
    final r = _selectedRebate;
    return r != null && OrderDraft.rebateClaimValid(_draft.rebateClaim, r.balance);
  }

  /// handleIsDisabled: Next needs a valid rebate claim unless the pick-up discount is chosen.
  bool get _canNext => _draft.pickupSelected || _rebateValid;

  Future<void> _go({required bool skip}) async {
    if (skip) {
      _draft.pickupSelected = false;
      _draft.rebateCode = '';
      _draft.rebateClaim = 0;
    } else if (_draft.rebateCode.isNotEmpty && !_rebateValid) {
      _draft.rebateCode = '';
      _draft.rebateClaim = 0;
    }
    _draft.discountsChosen = true;
    await context.read<CallState>().draftChanged();
    if (!mounted) return;
    await pushCallScreen(context, OrderSummaryScreen(ctx: widget.ctx, draft: _draft));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final pickup = _draft.availablePickupDiscount;
    final rebate = _selectedRebate;
    return Scaffold(
      appBar: AppBar(title: const Text('Misc Discount')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text('Pick-up Discount', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          if (_draft.orderType != OrderType.pickUp)
            const Padding(padding: EdgeInsets.all(8), child: Text('Only for Pick Up orders.'))
          else if (pickup == 0)
            const Padding(padding: EdgeInsets.all(8), child: Text('No pick-up discount for these SKUs.'))
          else
            CheckboxListTile(
              key: const Key('pickupDiscount'),
              value: _draft.pickupSelected,
              title: Text('PHP ${numberWithDecimals(pickup)}'),
              onChanged: (v) => setState(() => _draft.pickupSelected = v ?? false),
            ),
          const Divider(),
          const Text('Rebate', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          if (_rebates.isEmpty)
            const Padding(padding: EdgeInsets.all(8), child: Text('No rebate available for this customer.'))
          else ...[
            DropdownButtonFormField<String>(
              key: const Key('rebateCode'),
              isExpanded: true,
              value: _draft.rebateCode.isEmpty ? null : _draft.rebateCode,
              decoration: const InputDecoration(labelText: 'Rebate'),
              items: [
                for (final r in _rebates)
                  DropdownMenuItem(value: r.number, child: Text('${r.number} - balance ${numberWithDecimals(r.balance)}')),
              ],
              onChanged: (v) => setState(() => _draft.rebateCode = v ?? ''),
            ),
            TextField(
              key: const Key('rebateClaim'),
              controller: _claim,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: InputDecoration(
                labelText: 'Amount to claim',
                errorText: rebate != null && _claim.text.isNotEmpty && !_rebateValid
                    ? 'Must be more than 0 and not over the balance (${numberWithDecimals(rebate.balance)})'
                    : null,
              ),
              onChanged: (v) => setState(() => _draft.rebateClaim = jsParseFloat(v.replaceAll(',', ''))),
            ),
          ],
          const Divider(),
          const Text('Promos', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          if (_promos.isEmpty)
            const Padding(padding: EdgeInsets.all(8), child: Text('No promo for this customer.'))
          else ...[
            for (final p in _promos)
              ListTile(
                dense: true,
                title: Text((p['promo_desc'] ?? p['description'] ?? p['promo_code'] ?? 'Promo').toString()),
                subtitle: Text((p['promo_code'] ?? p['group_code'] ?? '').toString()),
              ),
            const Text('Promo selection is not ported yet -- these promos are not applied to the order.',
                style: TextStyle(color: AppColors.red2, fontSize: 12)),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(key: const Key('discountSkip'), onPressed: () => _go(skip: true), child: const Text('Skip')),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  key: const Key('discountNext'),
                  onPressed: _canNext ? () => _go(skip: false) : null,
                  child: const Text('Next'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
