import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/app_colors.dart';
import '../../core/formatting.dart';
import '../master_data/master_data_state.dart';
import 'add_order_screen.dart';
import 'call_navigation.dart';
import 'call_rules.dart';
import 'call_state.dart';
import 'misc_discount_screen.dart';
import 'order_draft.dart';
import 'sku_catalog.dart';

/// Order Management -- ship-to, distribution center, delivery/pick-up, delivery date and the
/// ordered SKUs (the RN app's OrderManagementScreen). The order is saved on the phone as it's
/// edited, so leaving and coming back keeps it.
class OrderManagementScreen extends StatefulWidget {
  const OrderManagementScreen({super.key, required this.ctx});
  final CallContext ctx;

  @override
  State<OrderManagementScreen> createState() => _OrderManagementScreenState();
}

class _OrderManagementScreenState extends State<OrderManagementScreen> {
  late final OrderDraft _draft;
  late final List<ShipTo> _shipTos;
  late final List<Map<String, dynamic>> _offices;

  @override
  void initState() {
    super.initState();
    final data = context.read<MasterDataState>().data;
    _shipTos = shipTosFor(data, widget.ctx.customerNumber);
    if (_shipTos.isEmpty) {
      // No partner rows: the customer ships to itself.
      _shipTos.add(ShipTo(address: widget.ctx.text('address'), partnerNumber: widget.ctx.customerNumber));
    }
    _offices = salesOfficesOf(data);
    _draft = context.read<CallState>().draftFor(widget.ctx.customerNumber,
        routeCall: widget.ctx.raw, shipTos: _shipTos, salesOffices: _offices);
  }

  void _changed() {
    setState(() {});
    context.read<CallState>().draftChanged();
  }

  /// New DC: the ordered lines take that DC's stock.
  void _setDistributionCenter(String office) {
    _draft.distributionCenter = office;
    _draft.deliveringPlant = office;
    final stock = stockByDescription(context.read<MasterDataState>().dcInventory, office) ?? const {};
    for (final l in _draft.lines) {
      l.netInventory = stock[l.description] ?? 0;
    }
    _changed();
  }

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _draft.deliveryDate ?? OrderDraft.defaultDeliveryDate(today),
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: today.add(const Duration(days: 60)),
    );
    if (picked == null || !mounted) return;
    final warning = OrderDraft.deliveryDateWarning(picked, today);
    if (warning != null && !await confirmDialog(context, 'Delivery Date', warning, ok: 'Yes', cancel: 'No')) return;
    _draft.deliveryDate = picked;
    _changed();
  }

  Future<void> _addOrder() async {
    final masterData = context.read<MasterDataState>();
    final blocked = addOrderBlockedReason(widget.ctx.raw, _constants(masterData)['allowed_ocl']);
    if (blocked != null) {
      await messageDialog(context, 'Add Order', blocked);
      return;
    }
    final dc = _draft.distributionCenter;
    if (dc == null || dc.isEmpty) {
      await messageDialog(context, 'Add Order', 'Please select a Distribution Center first.');
      return;
    }
    if (stockByDescription(masterData.dcInventory, dc) == null && masterData.dcInventory.isEmpty) {
      // Stock wasn't loaded after the download (no connection then?): try once more now.
      try {
        await masterData.refreshDcInventory();
      } catch (_) {}
      if (!mounted) return;
    }
    if (stockByDescription(masterData.dcInventory, dc) == null) {
      await messageDialog(context, 'Add Order',
          'No available inventory in this Distribution Center. Please select another Distribution center');
      return;
    }
    if (!mounted) return;
    final added = await pushCallScreen<List<OrderLine>>(context, AddOrderScreen(ctx: widget.ctx, draft: _draft));
    if (added == null) return;
    // Add Order shows the whole order: SKUs set back to 0 there are taken off.
    _draft.lines.removeWhere((l) => !added.any((a) => a.sapNumber == l.sapNumber));
    _draft.addLines(added);
    _changed();
  }

  Map _constants(MasterDataState m) => m.data['constants'] is Map ? m.data['constants'] as Map : const {};

  Future<void> _next() async {
    if (!_draft.canProceed) {
      await messageDialog(context, 'Order Management', 'Please complete the ship-to, distribution center and add at least one SKU.');
      return;
    }
    await pushCallScreen(context, MiscDiscountScreen(ctx: widget.ctx, draft: _draft));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final currentShipTo = _shipTos.where((s) => s.address == _draft.shipToAddress).isEmpty ? null : _draft.shipToAddress;
    final officeIds = _offices.map((o) => (o['sap_officeId'] ?? '').toString()).toSet();
    return Scaffold(
      appBar: AppBar(title: const Text('Order Management')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(widget.ctx.text('outlet_name'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: const Key('shipTo'),
            isExpanded: true,
            value: currentShipTo,
            decoration: const InputDecoration(labelText: 'Ship To'),
            items: [
              for (final s in _shipTos)
                DropdownMenuItem(value: s.address, child: Text(s.address, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) {
              final s = _shipTos.firstWhere((s) => s.address == v);
              _draft.shipToAddress = s.address;
              _draft.shipToPartner = s.partnerNumber;
              _changed();
            },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: const Key('distributionCenter'),
            isExpanded: true,
            value: officeIds.contains(_draft.distributionCenter) ? _draft.distributionCenter : null,
            decoration: const InputDecoration(labelText: 'Distribution Center'),
            items: [
              for (final o in _offices)
                DropdownMenuItem(
                  value: (o['sap_officeId'] ?? '').toString(),
                  child: Text('${o['sap_officeId']} - ${o['desc'] ?? ''}'),
                ),
            ],
            onChanged: (v) {
              if (v != null) _setDistributionCenter(v);
            },
          ),
          const SizedBox(height: 12),
          SegmentedButton<OrderType>(
            segments: const [
              ButtonSegment(value: OrderType.delivery, label: Text('Delivery')),
              ButtonSegment(value: OrderType.pickUp, label: Text('Pick Up')),
            ],
            selected: {_draft.orderType},
            onSelectionChanged: (s) {
              _draft.orderType = s.first;
              if (_draft.orderType == OrderType.delivery) _draft.pickupSelected = false;
              _changed();
            },
          ),
          const SizedBox(height: 8),
          ListTile(
            key: const Key('deliveryDate'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text(_draft.orderType == OrderType.delivery ? 'Delivery Date' : 'Pick Up Date'),
            subtitle: Text(_draft.deliveryDate == null ? '-' : DateFormat('MMMM d, y (EEEE)').format(_draft.deliveryDate!)),
            trailing: const Icon(Icons.edit_calendar),
            onTap: _pickDate,
          ),
          const Divider(),
          Row(
            children: [
              const Expanded(child: Text('Orders', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              FilledButton.icon(
                key: const Key('addOrder'),
                onPressed: _addOrder,
                icon: const Icon(Icons.add),
                label: const Text('Add Order'),
              ),
            ],
          ),
          if (_draft.lines.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Text('No orders yet.', textAlign: TextAlign.center)),
          for (final line in _draft.lines) _LineTile(key: ValueKey(line.sapNumber), line: line, onChanged: _changed, onRemove: () {
            _draft.removeLine(line.sapNumber);
            _changed();
          }),
          const Divider(),
          Row(
            children: [
              const Expanded(child: Text('Total', style: TextStyle(fontWeight: FontWeight.w800))),
              Text('PHP ${numberWithDecimals(_draft.listTotal)}',
                  key: const Key('orderTotal'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(key: const Key('orderNext'), onPressed: _next, child: const Text('Next')),
        ),
      ),
    );
  }
}

class _LineTile extends StatefulWidget {
  const _LineTile({super.key, required this.line, required this.onChanged, required this.onRemove});
  final OrderLine line;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  State<_LineTile> createState() => _LineTileState();
}

class _LineTileState extends State<_LineTile> {
  late final TextEditingController _qty = TextEditingController(text: widget.line.quantity.toString());

  @override
  void didUpdateWidget(covariant _LineTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (jsParseInt(_qty.text) != widget.line.quantity) _qty.text = widget.line.quantity.toString();
  }

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.line;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(l.description, style: const TextStyle(fontWeight: FontWeight.w700))),
                IconButton(icon: const Icon(Icons.delete_outline, color: AppColors.red2), onPressed: widget.onRemove),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text('${l.unit}  @ ${numberWithDecimals(l.wsp)}'
                      '${l.discountTotal != 0 ? '  less ${numberWithDecimals(l.discountTotal.abs())}' : ''}'),
                ),
                SizedBox(
                  width: 70,
                  child: TextField(
                    key: Key('lineQty-${l.sapNumber}'),
                    controller: _qty,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(isDense: true),
                    onChanged: (v) {
                      final q = jsParseInt(v);
                      if (q > 0) {
                        l.quantity = q;
                        widget.onChanged();
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: l.isOutOfStock == '1'
                      ? Text('Out of stock (available: ${l.netInventory})',
                          style: const TextStyle(color: AppColors.red2, fontSize: 12))
                      : Text('Available: ${l.netInventory}', style: const TextStyle(color: AppColors.grayLight, fontSize: 12)),
                ),
                Text(numberWithDecimals(l.listTotal), style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
