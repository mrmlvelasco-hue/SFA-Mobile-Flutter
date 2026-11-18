import 'package:flutter/foundation.dart';

import 'route_call.dart';

enum RouteCallFilter { scheduled, unscheduled }

/// Today's route calls and their done/ongoing state, read from the downloaded master data (works
/// offline) -- the RN app's `offlineData.data.route_calls` / `order_details` plus the Route Call
/// Schedule screen's own filtering logic (src/screens/RouteCallScheduleScreen.js).
class RouteCallState extends ChangeNotifier {
  RouteCallState({required List<RouteCall> calls, List<OrderDetail> orders = const []})
      : calls = List.unmodifiable(calls),
        _doneFromOrders = doneCustomers(calls, orders);

  /// From MasterDataState.data (the combined download).
  factory RouteCallState.fromDownload(Map<String, dynamic> data) {
    final routeCalls = data['route_calls'];
    final list = routeCalls is Map ? routeCalls['list'] : null;
    final orders = data['order_details'];
    return RouteCallState(
      calls: list is List ? list.whereType<Map>().map((m) => RouteCall.fromJson(Map<String, dynamic>.from(m))).toList() : const [],
      orders: orders is List
          ? orders.whereType<Map>().map((m) => OrderDetail.fromJson(Map<String, dynamic>.from(m))).toList()
          : const [],
    );
  }

  /// Every route call for today, in backend order (sfa_routecalls.id).
  final List<RouteCall> calls;

  /// Customers whose call is done because an order matches it (see [doneCustomers]).
  final Set<String> _doneFromOrders;

  /// Customers marked done/ongoing during this session. Nothing sets these yet -- they're filled
  /// in by the start-call / end-call / feedback flows in later milestones (the RN app's
  /// routeCall.doneCustomers, routeCall.customerFeedback and startAndEndRouteCall slices).
  final Set<String> localDone = {};
  final Set<String> ongoing = {};

  RouteCallFilter filter = RouteCallFilter.scheduled;
  String search = '';

  /// A call is done when an order matches its customer, control number, item number
  /// (= the order's sequence_number) and call date -- the RN app's checkIfDone().
  @visibleForTesting
  static Set<String> doneCustomers(List<RouteCall> calls, List<OrderDetail> orders) {
    final done = <String>{};
    for (final order in orders) {
      for (final call in calls) {
        if (call.customerNumber == order.customerNumber &&
            call.controlNumber == order.controlNumber &&
            call.itemNumber == order.sequenceNumber &&
            call.callDay == order.callDay) {
          done.add(call.customerNumber);
          break;
        }
      }
    }
    return done;
  }

  bool isDone(String customerNumber) =>
      _doneFromOrders.contains(customerNumber) || localDone.contains(customerNumber);

  bool isOngoing(String customerNumber) => ongoing.contains(customerNumber);

  void setFilter(RouteCallFilter value) {
    filter = value;
    notifyListeners();
  }

  void setSearch(String value) {
    search = value;
    notifyListeners();
  }

  /// What the list shows: one row per customer (first call wins), filtered by schedule type and
  /// outlet-name search, sorted by item number. Unscheduled calls put ongoing ones first.
  List<RouteCall> get visible {
    final seen = <String>{};
    final unique = calls
        .where((c) => filter == RouteCallFilter.scheduled ? c.isScheduled : c.isUnscheduled)
        .where((c) => seen.add(c.customerNumber))
        .toList();
    if (filter == RouteCallFilter.unscheduled) {
      unique.sort((a, b) => (isOngoing(a.customerNumber) ? 0 : 1).compareTo(isOngoing(b.customerNumber) ? 0 : 1));
    }
    final query = search.trim().toLowerCase();
    final filtered = query.isEmpty ? unique : unique.where((c) => c.outletName.toLowerCase().contains(query)).toList();
    // List.sort isn't stable; sort indexes so equal item numbers keep their order.
    final indexed = filtered.asMap().entries.toList()
      ..sort((a, b) {
        final bySequence = a.value.sequence.compareTo(b.value.sequence);
        return bySequence != 0 ? bySequence : a.key.compareTo(b.key);
      });
    return indexed.map((e) => e.value).toList();
  }
}
