import 'package:flutter/foundation.dart';

import '../../core/device_info_service.dart';
import '../../core/formatting.dart';
import '../../core/offline_store.dart';
import '../../core/outbox.dart';
import '../../core/safe_notifier.dart';
import '../auth/auth_state.dart';
import 'order_draft.dart';

enum CallStatus { ongoing, completed }

enum OrderStatus { none, submitted, queued, failed }

/// One customer's call today: the RN app's startAndEndRouteCall.customerStartCall entry plus that
/// call's outlet inventory and order.
class CallRecord {
  CallRecord({
    required this.customerNumber,
    required this.status,
    required this.startTime,
    this.startLat = 0,
    this.startLng = 0,
    this.endTime,
    this.outletInventoryDay,
    this.outletCounts,
    this.draft,
    this.orderStatus = OrderStatus.none,
    this.orderMessage,
    this.batch,
  });

  final String customerNumber;
  CallStatus status;

  /// 'yyyy-MM-dd HH:mm:ss'
  final String startTime;
  final num startLat;
  final num startLng;
  String? endTime;

  /// 'yyyy-MM-dd' of the last outlet inventory save -- Add Order needs today's.
  String? outletInventoryDay;

  /// The counted outlet inventory, {'fulls': [...], 'empties': [...]} rows of
  /// {sap_number, description, case_config, unit_price, quantity}.
  Map<String, dynamic>? outletCounts;
  OrderDraft? draft;
  OrderStatus orderStatus;
  String? orderMessage;
  String? batch;

  bool get hasOrder => orderStatus == OrderStatus.submitted || orderStatus == OrderStatus.queued;

  Map<String, dynamic> toJson() => {
        'customer_number': customerNumber,
        'status': status.name,
        'start_time': startTime,
        'start_lat': startLat,
        'start_lng': startLng,
        'end_time': endTime,
        'outlet_inventory_day': outletInventoryDay,
        'outlet_counts': outletCounts,
        'draft': draft?.toJson(),
        'order_status': orderStatus.name,
        'order_message': orderMessage,
        'batch': batch,
      };

  factory CallRecord.fromJson(Map<String, dynamic> j) => CallRecord(
        customerNumber: (j['customer_number'] ?? '').toString(),
        status: j['status'] == CallStatus.completed.name ? CallStatus.completed : CallStatus.ongoing,
        startTime: (j['start_time'] ?? '').toString(),
        startLat: asNum(j['start_lat']) ?? 0,
        startLng: asNum(j['start_lng']) ?? 0,
        endTime: j['end_time']?.toString(),
        outletInventoryDay: j['outlet_inventory_day']?.toString(),
        outletCounts: j['outlet_counts'] is Map ? Map<String, dynamic>.from(j['outlet_counts'] as Map) : null,
        draft: j['draft'] is Map ? OrderDraft.fromJson(Map<String, dynamic>.from(j['draft'] as Map)) : null,
        orderStatus: OrderStatus.values.firstWhere((s) => s.name == j['order_status'], orElse: () => OrderStatus.none),
        orderMessage: j['order_message']?.toString(),
        batch: j['batch']?.toString(),
      );
}

/// Today's calls -- start, outlet inventory, the order, submit, end -- saved on the phone so the
/// day survives an app restart, and sent to the server through the [Outbox] (works offline).
class CallState extends ChangeNotifier with SafeNotifier {
  CallState({required AuthState auth, required Outbox outbox, OfflineStore? store, DateTime Function()? clock})
      : _auth = auth,
        _outbox = outbox,
        _store = store ?? FileOfflineStore.instance,
        _clock = clock ?? DateTime.now;

  final AuthState _auth;
  final Outbox _outbox;
  final OfflineStore _store;
  final DateTime Function() _clock;

  final Map<String, CallRecord> calls = {};

  String get _today => dayKey(_clock());

  Future<void> load() async {
    final doc = await _store.read(OfflineDocs.calls);
    calls.clear();
    if (doc != null && doc['employee_id'] == _auth.user?.employeeId && doc['day'] == _today && doc['calls'] is Map) {
      (doc['calls'] as Map).forEach((key, value) {
        if (value is Map) calls[key.toString()] = CallRecord.fromJson(Map<String, dynamic>.from(value));
      });
    }
    notifyListeners();
  }

  CallRecord? record(String customerNumber) => calls[customerNumber];

  /// The customer whose call is ongoing, if any (only one at a time).
  String? get ongoingCustomer {
    for (final c in calls.values) {
      if (c.status == CallStatus.ongoing) return c.customerNumber;
    }
    return null;
  }

  bool isOngoing(String customerNumber) => calls[customerNumber]?.status == CallStatus.ongoing;
  bool isCompleted(String customerNumber) => calls[customerNumber]?.status == CallStatus.completed;

  /// Start Call -- refused while another customer's call is ongoing (the RN button is disabled).
  /// Nothing is sent to the server at the start; the times and place go with the order.
  Future<bool> startCall(String customerNumber) async {
    final other = ongoingCustomer;
    if (other != null && other != customerNumber) return false;
    final device = DeviceInfoService.instance;
    calls[customerNumber] = CallRecord(
      customerNumber: customerNumber,
      status: CallStatus.ongoing,
      startTime: endRouteDate(_clock()),
      startLat: device.latStub(),
      startLng: device.lngStub(),
    );
    await _save();
    return true;
  }

  /// Cancel Call is allowed until the order is signed or today's outlet inventory is saved.
  bool canCancel(String customerNumber) {
    final r = calls[customerNumber];
    if (r == null || r.status != CallStatus.ongoing) return false;
    return !r.hasOrder && r.orderStatus != OrderStatus.failed && r.outletInventoryDay != _today;
  }

  Future<void> cancelCall(String customerNumber) async {
    if (!canCancel(customerNumber)) return;
    calls.remove(customerNumber);
    await _save();
  }

  bool outletInventoryDoneToday(String customerNumber) => calls[customerNumber]?.outletInventoryDay == _today;

  /// Saves the outlet inventory count; changed/added SKUs go to the server
  /// (outlet-inventory/sku/addNew), queued when offline. Returns null when nothing changed.
  Future<OutboxResult?> saveOutletInventory({
    required Map<String, dynamic> routeCall,
    required Map<String, dynamic> counts,
    required List<Map<String, dynamic>> productData,
    required List<Map<String, dynamic>> productDeleted,
  }) async {
    final customerNumber = (routeCall['customer_number'] ?? '').toString();
    final r = calls[customerNumber];
    if (r == null) return null;
    r.outletInventoryDay = _today;
    r.outletCounts = counts;
    await _save();
    if (productData.isEmpty && productDeleted.isEmpty) return null;
    return _outbox.send('Outlet inventory', '/api/v1/outlet-inventory/sku/addNew', {
      'customer_data': [
        {
          'customer_number': customerNumber,
          'employee_id': _auth.user?.employeeId,
          'sales_route': routeCall['sales_route'],
          'sales_office': routeCall['sales_office'],
          'control_number': routeCall['control_number'],
          'item_number': routeCall['item_number'],
          'call_date': routeCall['call_date'],
          'inventory_date_time': endRouteDate(_clock()),
          'product_data': productData,
          'product_deleted': productDeleted,
        }
      ],
    });
  }

  /// The order being taken for this call, created with the RN defaults on first use: the first
  /// ship-to, the sales office matching the customer's delivering plant, delivery in 2-3 days.
  OrderDraft draftFor(String customerNumber, {required Map<String, dynamic> routeCall, required List<ShipTo> shipTos,
      required List<Map<String, dynamic>> salesOffices}) {
    final r = calls[customerNumber]!;
    if (r.draft != null) return r.draft!;
    final plant = (routeCall['delivering_plant'] ?? '').toString();
    String? office;
    for (final o in salesOffices) {
      if ((o['sap_officeId'] ?? '').toString() == plant) office = plant;
    }
    r.draft = OrderDraft(
      shipToAddress: shipTos.isNotEmpty ? shipTos.first.address : null,
      shipToPartner: shipTos.isNotEmpty ? shipTos.first.partnerNumber : null,
      distributionCenter: office,
      deliveringPlant: office,
      deliveryDate: OrderDraft.defaultDeliveryDate(_clock()),
    );
    return r.draft!;
  }

  /// Saves the draft after the screens change it.
  Future<void> draftChanged() async {
    await _save();
  }

  /// Sends the signed order (order/submit), queued when offline. A server rejection is kept on the
  /// call (OrderStatus.failed) so it can be fixed and submitted again.
  Future<OutboxResult> submitOrder({
    required Map<String, dynamic> routeCall,
    required String creditTerm,
    required String signature,
    required String remarks,
  }) async {
    final customerNumber = (routeCall['customer_number'] ?? '').toString();
    final r = calls[customerNumber]!;
    final now = _clock();
    final device = DeviceInfoService.instance;
    final payload = r.draft!.submitPayload(
      employeeId: _auth.user?.employeeId ?? '',
      routeCall: routeCall,
      creditTerm: creditTerm,
      startTime: r.startTime,
      startLat: r.startLat,
      startLng: r.startLng,
      endTime: endRouteDate(now),
      endLat: device.latStub(),
      endLng: device.lngStub(),
      signature: signature,
      remarks: remarks,
      mobileOrderId: '${now.toUtc().toIso8601String()}_${now.microsecondsSinceEpoch.toRadixString(36)}',
    );
    final result = await _outbox.send('Order', '/api/v1/order/submit', payload);
    if (result.queued) {
      r.orderStatus = OrderStatus.queued;
      r.orderMessage = 'No connection -- the order is saved on the phone and will be sent automatically.';
    } else if (result.envelope.isSuccess) {
      r.orderStatus = OrderStatus.submitted;
      final request = result.envelope.data is Map ? (result.envelope.data as Map)['request'] : null;
      final sap = request is Map ? request['sap_response'] : null;
      r.batch = request is Map ? request['batch']?.toString() : null;
      r.orderMessage = (sap == null || sap.toString().isEmpty) ? 'Order submitted.' : 'Order submitted. SAP: $sap';
    } else {
      r.orderStatus = OrderStatus.failed;
      r.orderMessage = result.envelope.message;
    }
    await _save();
    return result;
  }

  /// End Call. With an order, sends route/end-call (queued when offline), as the RN app does. A
  /// call without an order ends here only: the RN app asks for a no-order feedback reason at this
  /// point (Feedback screen, not ported yet) and sends no end-call.
  Future<OutboxResult?> endCall(Map<String, dynamic> routeCall) async {
    final customerNumber = (routeCall['customer_number'] ?? '').toString();
    final r = calls[customerNumber];
    if (r == null) return null;
    final now = _clock();
    OutboxResult? result;
    if (r.hasOrder) {
      final device = DeviceInfoService.instance;
      result = await _outbox.send('End call', '/api/v1/route/end-call', {
        'employee_id': _auth.user?.employeeId,
        'call_date': endRouteDate(now),
        'control_number': routeCall['control_number'],
        'customer_number': customerNumber,
        'sequence_number': routeCall['item_number'],
        'endtime': endRouteDate(now),
        'end_lat': device.latStub(),
        'end_lng': device.lngStub(),
        if (r.batch != null) 'batch': r.batch,
      });
    }
    r.status = CallStatus.completed;
    r.endTime = endRouteDate(now);
    await _save();
    return result;
  }

  Future<void> _save() async {
    await _store.write(OfflineDocs.calls, {
      'employee_id': _auth.user?.employeeId,
      'day': _today,
      'calls': {for (final e in calls.entries) e.key: e.value.toJson()},
    });
    notifyListeners();
  }
}
