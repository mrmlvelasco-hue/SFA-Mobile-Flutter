import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_colors.dart';
import '../../core/formatting.dart';
import '../master_data/master_data_state.dart';
import 'call_navigation.dart';
import 'call_state.dart';

/// One SKU counted at the outlet.
class OutletRow {
  OutletRow({required this.sapNumber, required this.description, required this.caseConfig, required this.unitPrice, required this.quantity});

  final String sapNumber;
  final String description;
  final String caseConfig;
  final dynamic unitPrice;
  int quantity;

  String get key => '$sapNumber|$caseConfig';

  Map<String, dynamic> toJson() => {
        'sap_number': sapNumber,
        'description': description,
        'case_config': caseConfig,
        'unit_price': unitPrice,
        'quantity': quantity,
      };

  factory OutletRow.fromJson(Map j) => OutletRow(
        sapNumber: (j['sap_number'] ?? '').toString(),
        description: (j['description'] ?? j['product_description'] ?? '').toString(),
        caseConfig: (j['case_config'] ?? '').toString(),
        unitPrice: j['unit_price'],
        quantity: jsParseInt(j['quantity'] ?? j['outlet_inventory']),
      );
}

/// What changed between the last saved count and this one -- the RN app's comparison that fills
/// addNewSku.product_data (added or changed SKUs) and product_deleted (removed SKUs).
({List<Map<String, dynamic>> data, List<Map<String, dynamic>> deleted}) outletInventoryChanges(
    List<OutletRow> before, List<OutletRow> after) {
  final old = {for (final r in before) r.key: r};
  final now = {for (final r in after) r.key: r};
  return (
    data: [
      for (final r in after)
        if (old[r.key] == null || old[r.key]!.quantity != r.quantity)
          {'materials_id': r.sapNumber, 'quantity': r.quantity, 'case_config': r.caseConfig, 'unit_price': r.unitPrice}
    ],
    deleted: [
      for (final r in before)
        if (now[r.key] == null) {'materials_id': r.sapNumber, 'case_config': r.caseConfig}
    ],
  );
}

/// Outlet Inventory -- count the customer's stock of fulls and empties (the RN app's
/// OutletInventoryScreen). Starts from the last count the server has (download's `outlets`) or
/// today's saved count; Save sends only what changed (outlet-inventory/sku/addNew), queued when
/// offline, and marks today's outlet inventory as done (Add Order needs it).
class OutletInventoryScreen extends StatefulWidget {
  const OutletInventoryScreen({super.key, required this.ctx});
  final CallContext ctx;

  @override
  State<OutletInventoryScreen> createState() => _OutletInventoryScreenState();
}

class _OutletInventoryScreenState extends State<OutletInventoryScreen> {
  late List<OutletRow> _baseFulls;
  late List<OutletRow> _baseEmpties;
  late List<OutletRow> _fulls;
  late List<OutletRow> _empties;
  final Map<String, TextEditingController> _qty = {};

  /// Controllers of removed rows, disposed with the screen (their field may still be on screen
  /// for this frame).
  final List<TextEditingController> _removed = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final data = context.read<MasterDataState>().data;
    final record = context.read<CallState>().record(widget.ctx.customerNumber);
    final saved = record?.outletCounts;
    if (saved != null) {
      _baseFulls = _rows(saved['fulls']);
      _baseEmpties = _rows(saved['empties']);
    } else {
      final outlets = data['outlets'];
      final mine = outlets is Map ? outlets[widget.ctx.customerNumber] : null;
      List<OutletRow> fromOutlet(String key) {
        final group = mine is Map ? mine[key] : null;
        return _rows(group is Map ? group['product_value'] : null);
      }

      _baseFulls = fromOutlet('product_full');
      _baseEmpties = fromOutlet('product_empties');
    }
    _fulls = _baseFulls.map((r) => OutletRow.fromJson(r.toJson())).toList();
    _empties = _baseEmpties.map((r) => OutletRow.fromJson(r.toJson())).toList();
  }

  static List<OutletRow> _rows(dynamic list) =>
      list is List ? list.whereType<Map>().map(OutletRow.fromJson).toList() : <OutletRow>[];

  @override
  void dispose() {
    for (final c in [..._qty.values, ..._removed]) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controller(OutletRow row) =>
      _qty.putIfAbsent(row.key, () => TextEditingController(text: row.quantity.toString()));

  Future<void> _addSku(bool empties) async {
    final inventory = context.read<MasterDataState>().data['inventory'];
    final listed = {...(empties ? _empties : _fulls).map((r) => r.sapNumber)};
    final choices = (inventory is List ? inventory.whereType<Map>() : const <Map>[])
        .where((m) => (m['type'] ?? '').toString().startsWith('LER') == empties)
        .where((m) => !listed.contains((m['sap_number'] ?? '').toString()))
        .toList();
    final picked = await showModalBottomSheet<Map>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SkuPicker(choices: choices),
    );
    if (picked == null) return;
    setState(() {
      (empties ? _empties : _fulls).add(OutletRow(
        sapNumber: (picked['sap_number'] ?? '').toString(),
        description: (picked['sku'] ?? '').toString(),
        caseConfig: (picked['case'] ?? '').toString(),
        unitPrice: picked['unit_price'],
        quantity: 0,
      ));
    });
  }

  Future<void> _save() async {
    for (final r in [..._fulls, ..._empties]) {
      r.quantity = jsParseInt(_controller(r).text);
    }
    final fulls = outletInventoryChanges(_baseFulls, _fulls);
    final empties = outletInventoryChanges(_baseEmpties, _empties);
    setState(() => _saving = true);
    final result = await context.read<CallState>().saveOutletInventory(
      routeCall: widget.ctx.raw,
      counts: {
        'fulls': _fulls.map((r) => r.toJson()).toList(),
        'empties': _empties.map((r) => r.toJson()).toList(),
      },
      productData: [...fulls.data, ...empties.data],
      productDeleted: [...fulls.deleted, ...empties.deleted],
    );
    if (!mounted) return;
    setState(() => _saving = false);
    final String message;
    if (result == null) {
      message = 'Outlet inventory saved (no changes to send).';
    } else if (result.queued) {
      message = 'No connection -- the outlet inventory is saved and will be sent automatically.';
    } else if (result.envelope.isSuccess) {
      message = 'Outlet inventory saved.';
    } else {
      message = 'Saved on the phone, but the server did not accept it: ${result.envelope.message}';
    }
    await messageDialog(context, 'Outlet Inventory', message);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Outlet Inventory'),
          bottom: const TabBar(tabs: [Tab(text: 'Fulls'), Tab(text: 'Empty')]),
        ),
        body: TabBarView(children: [_list(_fulls, false), _list(_empties, true)]),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton(
              key: const Key('saveOutletInventory'),
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving...' : 'Save'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _list(List<OutletRow> rows, bool empties) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No SKU counted yet. Add the SKUs found at the outlet.', textAlign: TextAlign.center),
          ),
        for (final row in rows)
          Card(
            key: ValueKey(row.key),
            child: ListTile(
              title: Text(row.description, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${row.sapNumber} - ${row.caseConfig}'),
              trailing: SizedBox(
                width: 140,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: Key('outletQty-${row.sapNumber}'),
                        controller: _controller(row),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(isDense: true),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: AppColors.red2),
                      onPressed: () => setState(() {
                        rows.remove(row);
                        final c = _qty.remove(row.key);
                        if (c != null) _removed.add(c);
                      }),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: Key(empties ? 'addEmptySku' : 'addFullSku'),
          onPressed: () => _addSku(empties),
          icon: const Icon(Icons.add),
          label: Text(empties ? 'Add Empty SKU' : 'Add SKU'),
        ),
      ],
    );
  }
}

class _SkuPicker extends StatefulWidget {
  const _SkuPicker({required this.choices});
  final List<Map> choices;

  @override
  State<_SkuPicker> createState() => _SkuPickerState();
}

class _SkuPickerState extends State<_SkuPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final shown = widget.choices.where((m) => (m['sku'] ?? '').toString().toLowerCase().contains(q)).toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Search SKU', prefixIcon: Icon(Icons.search)),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: shown.length,
                itemBuilder: (_, i) => ListTile(
                  title: Text((shown[i]['sku'] ?? '').toString()),
                  subtitle: Text('${shown[i]['sap_number']} - ${shown[i]['case']}'),
                  onTap: () => Navigator.of(context).pop(shown[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
