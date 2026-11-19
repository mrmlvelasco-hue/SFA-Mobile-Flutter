import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_colors.dart';
import '../../core/formatting.dart';
import '../master_data/master_data_state.dart';
import 'call_navigation.dart';
import 'order_draft.dart';
import 'sku_catalog.dart';

/// Add Order -- pick SKUs and quantities from the customer's price list, with the selected
/// distribution center's stock (the RN app's AddOrderScreen). Returns the chosen lines.
class AddOrderScreen extends StatefulWidget {
  const AddOrderScreen({super.key, required this.ctx, required this.draft});
  final CallContext ctx;
  final OrderDraft draft;

  @override
  State<AddOrderScreen> createState() => _AddOrderScreenState();
}

class _AddOrderScreenState extends State<AddOrderScreen> {
  late final List<Sku> _catalog;
  final Map<String, int> _picked = {};
  String _query = '';

  @override
  void initState() {
    super.initState();
    final masterData = context.read<MasterDataState>();
    final stock = stockByDescription(masterData.dcInventory, widget.draft.distributionCenter ?? '') ?? const {};
    _catalog = buildSkuCatalog(masterData.data, widget.ctx.customerNumber)
        .map((s) => s.withStock(stock[s.description] ?? 0))
        .toList();
    for (final l in widget.draft.lines) {
      _picked[l.sapNumber] = l.quantity;
    }
  }

  void _setQty(Sku sku, int qty) {
    setState(() {
      if (qty <= 0) {
        _picked.remove(sku.sapNumber);
      } else {
        _picked[sku.sapNumber] = qty;
      }
    });
  }

  Future<void> _done() async {
    final lines = [
      for (final sku in _catalog)
        if (_picked[sku.sapNumber] != null) OrderLine.fromSku(sku, _picked[sku.sapNumber]!),
    ];
    final short = lines.where((l) => l.isOutOfStock == '1').map((l) => l.description).toList();
    if (short.isNotEmpty &&
        !await confirmDialog(context, 'Out of stock',
            'Not enough stock in the Distribution Center for:\n\n${short.join('\n')}\n\nAdd them anyway?',
            ok: 'Add', cancel: 'Back')) {
      return;
    }
    if (mounted) Navigator.of(context).pop(lines);
  }

  @override
  Widget build(BuildContext context) {
    final shown = _catalog.where((s) => matchesSkuSearch(s.description, _query)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Add Order')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              key: const Key('skuSearch'),
              decoration: const InputDecoration(hintText: 'Search SKU', prefixIcon: Icon(Icons.search), isDense: true),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? const Center(child: Text('No SKU found'))
                : ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (_, i) => _SkuTile(
                      key: ValueKey(shown[i].sapNumber),
                      sku: shown[i],
                      quantity: _picked[shown[i].sapNumber] ?? 0,
                      onChanged: (q) => _setQty(shown[i], q),
                    ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            key: const Key('addOrderDone'),
            onPressed: _picked.isEmpty ? null : _done,
            child: Text('Add (${_picked.length})'),
          ),
        ),
      ),
    );
  }
}

class _SkuTile extends StatefulWidget {
  const _SkuTile({super.key, required this.sku, required this.quantity, required this.onChanged});
  final Sku sku;
  final int quantity;
  final ValueChanged<int> onChanged;

  @override
  State<_SkuTile> createState() => _SkuTileState();
}

class _SkuTileState extends State<_SkuTile> {
  late final TextEditingController _qty =
      TextEditingController(text: widget.quantity == 0 ? '' : widget.quantity.toString());

  @override
  void didUpdateWidget(covariant _SkuTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sku.sapNumber != widget.sku.sapNumber) {
      _qty.text = widget.quantity == 0 ? '' : widget.quantity.toString();
    }
  }

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.sku;
    final q = widget.quantity;
    final short = q > 0 && (s.netInventory == 0 || q > s.netInventory);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: q > 0 ? AppColors.green : null,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.description, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('${s.unit}  PHP ${numberWithDecimals(s.wsp)}  |  Stock: ${s.netInventory}',
                      style: const TextStyle(fontSize: 12)),
                  if (short)
                    const Text('Not enough stock', style: TextStyle(color: AppColors.red2, fontSize: 12)),
                ],
              ),
            ),
            SizedBox(
              width: 70,
              child: TextField(
                key: Key('skuQty-${s.sapNumber}'),
                controller: _qty,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(hintText: '0', isDense: true),
                onChanged: (v) => widget.onChanged(jsParseInt(v)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
