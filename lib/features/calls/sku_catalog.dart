import '../../core/formatting.dart';

/// One orderable product for one customer -- a row of the RN app's "full SKU list" built at Start
/// Call (CustomerMasterDataComponent.getTheSkuFullList).
class Sku {
  Sku({
    required this.sapNumber,
    required this.description,
    required this.unit,
    required this.wsp,
    required this.discountTotal,
    required this.pickupDiscount,
    this.netInventory = 0,
    this.mtdVolPhy,
    this.magoVolPhy,
    this.bts,
    this.mcs,
  });

  final String sapNumber;

  /// The SKU's `sku` text (sfa_materials.desc); also what DC stock is matched on.
  final String description;

  /// The SKU's `case` (e.g. 'CS', 'BOT') -- sent as the order line's `unit`.
  final String unit;

  /// Unit price: the customer's price (pricing.wsp), else the material's unit_price, else 0.
  final num wsp;

  /// Per-unit discount (pricing.discount_total), as the server sends it (may be negative).
  final num discountTotal;

  /// Per-unit pick-up discount for this customer (pickUpDiscount data).
  final num pickupDiscount;

  /// Real-time stock in the selected distribution center (0 when unknown).
  final num netInventory;
  final num? mtdVolPhy;
  final num? magoVolPhy;
  final num? bts;
  final String? mcs;

  Sku withStock(num net) => Sku(
        sapNumber: sapNumber,
        description: description,
        unit: unit,
        wsp: wsp,
        discountTotal: discountTotal,
        pickupDiscount: pickupDiscount,
        netInventory: net,
        mtdVolPhy: mtdVolPhy,
        magoVolPhy: magoVolPhy,
        bts: bts,
        mcs: mcs,
      );
}

/// Builds the orderable SKUs for [customerNumber] from the downloaded master data, as the RN app
/// does at Start Call:
/// - `inventory` (the sku-list) without empties (type LER1),
/// - merged with `materials` (material inventory) by sap_number,
/// - priced from `pricing` rows for this customer (sap_number case-insensitive; customer number
///   trimmed), falling back to the material's unit_price, then 0,
/// - with this customer's per-unit pick-up discount from `pickUpDiscount`.
List<Sku> buildSkuCatalog(Map<String, dynamic> data, String customerNumber) {
  final materialsBySap = <String, Map>{};
  for (final m in _maps(data['materials'])) {
    materialsBySap.putIfAbsent((m['sap_number'] ?? '').toString(), () => m);
  }
  final priceBySap = <String, Map>{};
  for (final p in _maps(data['pricing'])) {
    if ((p['customer_number'] ?? '').toString().trim() == customerNumber) {
      priceBySap.putIfAbsent((p['sap_number'] ?? '').toString().toLowerCase(), () => p);
    }
  }
  final pickupBySap = <String, num>{};
  for (final p in _maps(data['pickUpDiscount'])) {
    if ((p['customer_number'] ?? '').toString() == customerNumber) {
      pickupBySap.putIfAbsent((p['sap_number'] ?? '').toString(), () => asNum(p['pickup_discount']) ?? 0);
    }
  }

  final out = <Sku>[];
  for (final full in _maps(data['inventory'])) {
    if ((full['type'] ?? '').toString() == 'LER1') continue;
    final sap = (full['sap_number'] ?? '').toString();
    final item = {...full, ...?materialsBySap[sap]};
    final price = priceBySap[sap.toLowerCase()];
    final priceWsp = asNum(price?['wsp']);
    final unitPrice = asNum(item['unit_price']);
    out.add(Sku(
      sapNumber: sap,
      description: (item['sku'] ?? item['desc'] ?? '').toString(),
      unit: (item['case'] ?? '').toString(),
      // `findRightPrice?.wsp ? findRightPrice.wsp : item.unit_price ? item.unit_price : 0`
      wsp: (priceWsp != null && priceWsp != 0) ? priceWsp : ((unitPrice != null && unitPrice != 0) ? unitPrice : 0),
      discountTotal: asNum(price?['discount_total']) ?? 0,
      pickupDiscount: pickupBySap[sap] ?? 0,
      mtdVolPhy: asNum(price?['MTD_vol_phy']),
      magoVolPhy: asNum(price?['MAGO_Vol_phy']),
      bts: asNum(price?['BTS']),
      mcs: price?['mcs']?.toString(),
    ));
  }
  return out;
}

/// Real-time stock for one distribution center, keyed by SKU description (the RN app matches
/// `sku_desc` to the SKU's description). Null when the DC has no stock list at all -- the RN app
/// then says "No available inventory in this Distribution Center".
Map<String, num>? stockByDescription(Map<String, dynamic> dcInventory, String salesOffice) {
  final items = dcInventory[salesOffice];
  if (items is! List) return null;
  return {
    for (final item in items.whereType<Map>()) (item['sku_desc'] ?? '').toString(): jsParseInt(item['net_inventory']),
  };
}

/// Groups materials-inventory-sap's `data` ([[items of office 1], [items of office 2]]) by
/// sales_office -- the RN app's groupBySalesOffice.
Map<String, List<Map<String, dynamic>>> groupStockBySalesOffice(dynamic data) {
  final grouped = <String, List<Map<String, dynamic>>>{};
  if (data is! List) return grouped;
  for (final office in data) {
    if (office is! List) continue;
    for (final item in office.whereType<Map>()) {
      grouped.putIfAbsent((item['sales_office'] ?? '').toString(), () => []).add(Map<String, dynamic>.from(item));
    }
  }
  return grouped;
}

/// The Add Order search: the description contains the text AND starts with the same letter (the
/// RN app's rule -- 'cola' finds 'Cola 8oz' but not 'Pepsi Cola').
bool matchesSkuSearch(String description, String query) {
  final q = query.toLowerCase();
  if (q.isEmpty) return true;
  final d = description.toLowerCase();
  return d.contains(q) && d.isNotEmpty && d[0] == q[0];
}

Iterable<Map> _maps(dynamic value) => value is List ? value.whereType<Map>() : const [];
