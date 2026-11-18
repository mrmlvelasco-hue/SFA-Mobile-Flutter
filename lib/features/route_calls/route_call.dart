/// One row of download-datav2's `route_calls.list`: today's call on a customer, joined to the
/// customer record (sfa-api: order_service.get_route_calls). [raw] keeps every field the backend
/// sent, for the screens after this one (Customer Master Data, Order Management, ...).
class RouteCall {
  final String customerNumber;
  final String outletName;
  final String ownerName;
  final String address;
  final String controlNumber;

  /// The call's position in today's route; '000000' (or anything numerically 0) means the
  /// customer is an unscheduled call. Kept as the backend's string -- it's compared as a string
  /// against an order's sequence_number to decide whether the call is done.
  final String? itemNumber;
  final String callDate;
  final Map<String, dynamic> raw;

  RouteCall({
    required this.customerNumber,
    required this.outletName,
    required this.ownerName,
    required this.address,
    required this.controlNumber,
    required this.itemNumber,
    required this.callDate,
    this.raw = const {},
  });

  factory RouteCall.fromJson(Map<String, dynamic> json) {
    String text(String key) => (json[key] ?? '').toString();
    return RouteCall(
      customerNumber: text('customer_number'),
      outletName: text('outlet_name'),
      ownerName: text('owner_name'),
      address: text('address'),
      controlNumber: text('control_number'),
      itemNumber: json['item_number']?.toString(),
      callDate: text('call_date'),
      raw: json,
    );
  }

  /// The RN app's `item_number == 0` / `!= 0` filters use JavaScript's loose equality: '000000',
  /// '0' and '' equal 0; null and non-numeric text don't. Mirrored exactly.
  bool get isUnscheduled {
    final value = itemNumber;
    if (value == null) return false;
    final trimmed = value.trim();
    return trimmed.isEmpty || num.tryParse(trimmed) == 0;
  }

  bool get isScheduled => !isUnscheduled;

  /// Numeric position for sorting (the RN app sorts with `a.item_number - b.item_number`).
  num get sequence => num.tryParse(itemNumber?.trim() ?? '') ?? 0;

  /// 'YYYY-MM-DD' of the call date (the backend sends 'YYYY-MM-DD HH:MM:SS.mmm').
  String get callDay => callDate.length >= 10 ? callDate.substring(0, 10) : callDate;
}

/// The fields of a download-datav2/order-details row used to decide which calls are done.
class OrderDetail {
  final String customerNumber;
  final String controlNumber;
  final String? sequenceNumber;
  final String callDate;

  OrderDetail({required this.customerNumber, required this.controlNumber, this.sequenceNumber, required this.callDate});

  factory OrderDetail.fromJson(Map<String, dynamic> json) => OrderDetail(
        customerNumber: (json['customer_number'] ?? '').toString(),
        controlNumber: (json['control_number'] ?? '').toString(),
        sequenceNumber: json['sequence_number']?.toString(),
        callDate: (json['call_date'] ?? '').toString(),
      );

  String get callDay => callDate.length >= 10 ? callDate.substring(0, 10) : callDate;
}
