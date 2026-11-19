import 'dart:convert';
import 'dart:math';

import '../../core/formatting.dart';
import 'sku_catalog.dart';

/// One order line (the RN app's addedOrderList entries).
class OrderLine {
  OrderLine({
    required this.sapNumber,
    required this.description,
    required this.unit,
    required this.wsp,
    required this.discountTotal,
    required this.pickupDiscount,
    required this.netInventory,
    required this.quantity,
  });

  factory OrderLine.fromSku(Sku sku, int quantity) => OrderLine(
        sapNumber: sku.sapNumber,
        description: sku.description,
        unit: sku.unit,
        wsp: sku.wsp,
        discountTotal: sku.discountTotal,
        pickupDiscount: sku.pickupDiscount,
        netInventory: sku.netInventory,
        quantity: quantity,
      );

  final String sapNumber;
  final String description;
  final String unit;
  final num wsp;
  final num discountTotal;
  final num pickupDiscount;

  /// Stock in the order's distribution center (updated when the DC changes).
  num netInventory;
  int quantity;

  /// '1' when the DC has none or fewer than ordered (the RN rule: net === 0 || qty > net).
  String get isOutOfStock => (netInventory == 0 || quantity > netInventory) ? '1' : '0';

  /// The order list's line total: (parseInt(wsp) - |discount|) * qty -- the RN app truncates the
  /// price to a whole number here (not in the summary).
  num get listTotal => (jsParseInt(wsp) - discountTotal.abs()) * quantity;

  /// The summary's line amount: wsp * qty - |discount| * qty (no discount on replacements; no line
  /// here is a replacement).
  num get summaryTotal => wsp * quantity - discountTotal.abs() * quantity;

  Map<String, dynamic> toJson() => {
        'sap_number': sapNumber,
        'description': description,
        'unit': unit,
        'wsp': wsp,
        'discount_total': discountTotal,
        'pickup_discount': pickupDiscount,
        'net_inventory': netInventory,
        'quantity': quantity,
      };

  factory OrderLine.fromJson(Map<String, dynamic> j) => OrderLine(
        sapNumber: (j['sap_number'] ?? '').toString(),
        description: (j['description'] ?? '').toString(),
        unit: (j['unit'] ?? '').toString(),
        wsp: asNum(j['wsp']) ?? 0,
        discountTotal: asNum(j['discount_total']) ?? 0,
        pickupDiscount: asNum(j['pickup_discount']) ?? 0,
        netInventory: asNum(j['net_inventory']) ?? 0,
        quantity: (asNum(j['quantity']) ?? 1).toInt(),
      );
}

enum OrderType { delivery, pickUp }

extension OrderTypeText on OrderType {
  String get label => this == OrderType.delivery ? 'Delivery' : 'Pick Up';

  /// transaction_type in the payload.
  String get value => this == OrderType.delivery ? 'DELIVERY' : 'PICK UP';
}

/// A ship-to choice (from the customer's Ship-To-Party partners).
class ShipTo {
  const ShipTo({required this.address, required this.partnerNumber});
  final String address;
  final String partnerNumber;
}

/// A rebate the customer can claim against (download's `rebates`).
class Rebate {
  const Rebate({required this.number, required this.balance, this.description = ''});
  final String number;
  final num balance;
  final String description;
}

/// The order being taken during a call -- what the RN app keeps across Order Management, Misc
/// Discount, Order Summary and Digital Signature (orderManagement slice + orderSubmitPayload).
class OrderDraft {
  OrderDraft({
    this.shipToAddress,
    this.shipToPartner,
    this.distributionCenter,
    this.deliveringPlant,
    this.orderType = OrderType.delivery,
    this.deliveryDate,
    List<OrderLine>? lines,
    this.pickupSelected = false,
    this.rebateCode = '',
    this.rebateClaim = 0,
    this.discountsChosen = false,
  }) : lines = lines ?? [];

  String? shipToAddress;
  String? shipToPartner;
  String? distributionCenter;
  String? deliveringPlant;
  OrderType orderType;
  DateTime? deliveryDate;
  final List<OrderLine> lines;

  /// Misc Discount choices.
  bool pickupSelected;
  String rebateCode;
  num rebateClaim;

  /// True once Misc Discount was passed (Next or Skip).
  bool discountsChosen;

  bool get canProceed =>
      lines.isNotEmpty && (shipToAddress ?? '').isNotEmpty && (distributionCenter ?? '').isNotEmpty;

  OrderLine? line(String sapNumber) {
    for (final l in lines) {
      if (l.sapNumber == sapNumber) return l;
    }
    return null;
  }

  void setQuantity(String sapNumber, int quantity) {
    line(sapNumber)?.quantity = max(1, quantity);
  }

  /// Adds lines from Add Order; an SKU already on the order gets the new quantity.
  void addLines(Iterable<OrderLine> added) {
    for (final addedLine in added) {
      final existing = line(addedLine.sapNumber);
      if (existing != null) {
        existing.quantity = addedLine.quantity;
      } else {
        lines.add(addedLine);
      }
    }
  }

  void removeLine(String sapNumber) => lines.removeWhere((l) => l.sapNumber == sapNumber);

  // --- totals -------------------------------------------------------------------------------

  num get listTotal => lines.fold<num>(0, (sum, l) => sum + l.listTotal);

  /// getTotalNetGross(): sum of wsp*qty, minus |discount|*qty of non-replacement lines.
  num get netGross =>
      lines.fold<num>(0, (sum, l) => sum + l.wsp * l.quantity) -
      lines.fold<num>(0, (sum, l) => sum + l.discountTotal.abs() * l.quantity);

  /// Pick-up discount available on this order: |per-unit pick-up| * qty summed -- only for Pick Up
  /// orders (the RN Misc Discount shows it only when pickupType === 'PICK UP').
  num get availablePickupDiscount => orderType == OrderType.pickUp
      ? lines.fold<num>(0, (sum, l) => sum + l.pickupDiscount.abs() * l.quantity)
      : 0;

  num get pickupDiscount => pickupSelected ? availablePickupDiscount : 0;
  num get rebate => rebateCode.isEmpty ? 0 : rebateClaim;

  /// Promos (percentage / free items) aren't ported yet -- always 0.
  num get promoDiscount => 0;

  /// total_estimated_amount: netGross - pick-up - rebate - promo.
  num get totalEstimated => netGross - pickupDiscount - rebate - promoDiscount;

  /// The rebate claim rule (handleIsDisabled): a chosen rebate needs 0 < claim <= balance.
  static bool rebateClaimValid(num claim, num balance) => claim > 0 && jsParseInt(claim) <= jsParseInt(balance);

  /// Default delivery date: today + 2 days, or + 3 when that lands on a Sunday or Monday.
  static DateTime defaultDeliveryDate(DateTime today) {
    final two = DateTime(today.year, today.month, today.day + 2);
    return (two.weekday == DateTime.sunday || two.weekday == DateTime.monday)
        ? DateTime(today.year, today.month, today.day + 3)
        : two;
  }

  /// A chosen delivery date needs a confirmation when it's a Sunday or earlier than today + 2.
  static String? deliveryDateWarning(DateTime chosen, DateTime today) {
    if (chosen.weekday == DateTime.sunday) {
      return 'You have selected Sunday as delivery date, are you sure you want to choose this date?';
    }
    final earliest = DateTime(today.year, today.month, today.day + 2);
    if (DateTime(chosen.year, chosen.month, chosen.day).isBefore(earliest)) {
      return 'The delivery date is earlier than two days from today. Are you sure you want to choose this date?';
    }
    return null;
  }

  // --- payload ------------------------------------------------------------------------------

  /// The `orders` lines, as the RN app sends them (a JSON string in the payload).
  List<Map<String, dynamic>> orderLinesPayload() => [
        for (final l in lines)
          {
            'materials_numbers': l.sapNumber,
            'quantity': l.quantity,
            'is_outofstock': l.isOutOfStock,
            'is_replacement': '0',
            'promo_code': '0',
            'discount': l.discountTotal,
            'price_master': l.wsp,
            'total_price': jsParseInt(l.wsp) * l.quantity,
            'is_freeitem': '0',
            'free_sku': '',
            'free_sku_unit': '',
            'freeitem_quantity': 0,
            'getitem_from': '0',
            'unit': l.unit,
            // Skip on Misc Discount zeroes it; otherwise |per-unit pick-up| * qty.
            'pickup_discount': discountsChosen && !pickupSelected ? 0 : l.pickupDiscount.abs() * l.quantity,
          }
      ];

  /// The order/submit payload (RouteActivities::submitOrder), built the way the RN app's Order
  /// Management, Order Summary and Digital Signature screens fill orderSubmitPayload.
  Map<String, dynamic> submitPayload({
    required String employeeId,
    required Map<String, dynamic> routeCall,
    required String creditTerm,
    required String startTime,
    required num startLat,
    required num startLng,
    required String endTime,
    required num endLat,
    required num endLng,
    required String signature,
    required String remarks,
    required String mobileOrderId,
  }) {
    final customerNumber = (routeCall['customer_number'] ?? '').toString();
    return {
      'employee_id': employeeId,
      'control_number': routeCall['control_number'],
      'sequence_number': routeCall['item_number'],
      'customer_number': customerNumber,
      'customer_partner': shipToPartner == customerNumber ? '' : (shipToPartner ?? ''),
      'shipping_address': shipToAddress,
      // GPS isn't ported yet, so there is no geofence result to send.
      'is_inside_geo': null,
      'deviation_in_meters': null,
      'call_date': routeCall['call_date'],
      'start_call': startTime,
      'starttime': startTime,
      'start_lat': startLat,
      'start_lng': startLng,
      'end_call': startTime,
      'endtime': endTime,
      'end_lat': endLat,
      'end_lng': endLng,
      'customer_signature': signature,
      'mobile_order_id': mobileOrderId,
      'remarks': remarks.trim().isEmpty ? '.' : remarks,
      'total_promo_discount': promoDiscount == 0 ? '0' : promoDiscount,
      'total_pickup_discount': pickupDiscount == 0 ? '0' : pickupDiscount,
      'total_rebate': rebate == 0 ? '0' : rebate,
      'rebate_code': rebate == 0 ? '' : rebateCode,
      'total_estimated_amount': totalEstimated,
      // Never filled in by the RN app either -- the server requires it, so it goes as '0'.
      'final_total': '0',
      'feedback': '',
      'empties_pullout': jsonEncode(const []),
      'delivering_plant': deliveringPlant ?? distributionCenter,
      'distribution_center': distributionCenter,
      'delivery_date': deliveryDate == null ? null : endRouteDate(deliveryDate!, withTime: false),
      'order_type': creditTerm == 'COD' ? 'ZA02' : 'ZA01',
      'orders': jsonEncode(orderLinesPayload()),
      'transaction_type': orderType.value,
    };
  }

  // --- saving -------------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
        'ship_to_address': shipToAddress,
        'ship_to_partner': shipToPartner,
        'distribution_center': distributionCenter,
        'delivering_plant': deliveringPlant,
        'order_type': orderType.name,
        'delivery_date': deliveryDate?.toIso8601String(),
        'lines': lines.map((l) => l.toJson()).toList(),
        'pickup_selected': pickupSelected,
        'rebate_code': rebateCode,
        'rebate_claim': rebateClaim,
        'discounts_chosen': discountsChosen,
      };

  factory OrderDraft.fromJson(Map<String, dynamic> j) => OrderDraft(
        shipToAddress: j['ship_to_address']?.toString(),
        shipToPartner: j['ship_to_partner']?.toString(),
        distributionCenter: j['distribution_center']?.toString(),
        deliveringPlant: j['delivering_plant']?.toString(),
        orderType: j['order_type'] == OrderType.pickUp.name ? OrderType.pickUp : OrderType.delivery,
        deliveryDate: DateTime.tryParse((j['delivery_date'] ?? '').toString()),
        lines: (j['lines'] as List? ?? const [])
            .whereType<Map>()
            .map((m) => OrderLine.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
        pickupSelected: j['pickup_selected'] == true,
        rebateCode: (j['rebate_code'] ?? '').toString(),
        rebateClaim: asNum(j['rebate_claim']) ?? 0,
        discountsChosen: j['discounts_chosen'] == true,
      );
}
