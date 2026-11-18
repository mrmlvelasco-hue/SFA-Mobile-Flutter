import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import '../auth/auth_state.dart';
import 'route_call.dart';
import 'route_call_repository.dart';

enum RouteCallFilter { scheduled, unscheduled }

enum LoadStatus { idle, loading, loaded, error }

/// Today's route calls and their done/ongoing state -- the Flutter equivalent of the RN app's
/// `offlineData` slice (as far as the Route Call Schedule uses it) plus the screen's own
/// filtering logic (src/screens/RouteCallScheduleScreen.js).
class RouteCallState extends ChangeNotifier {
  RouteCallState({required AuthState auth, RouteCallRepository? repository})
      : _auth = auth,
        _repository = repository ?? RouteCallRepository();

  final AuthState _auth;
  final RouteCallRepository _repository;

  LoadStatus status = LoadStatus.idle;
  String? errorMessage;

  /// Every route call for today, in backend order (sfa_routecalls.id).
  List<RouteCall> calls = const [];

  /// The whole download-datav2 `data` object, kept for later screens (constants, feedback
  /// reasons, non-sales activities, order summary...).
  Map<String, dynamic> downloadData = const {};

  /// Customers whose call is done because an order matches it (see [_doneFromOrders]).
  Set<String> _doneFromOrders = const {};

  /// Customers marked done/ongoing during this session. Nothing sets these yet -- they're filled
  /// in by the start-call / end-call / feedback flows in later milestones (the RN app's
  /// routeCall.doneCustomers, routeCall.customerFeedback and startAndEndRouteCall slices).
  final Set<String> localDone = {};
  final Set<String> ongoing = {};

  RouteCallFilter filter = RouteCallFilter.scheduled;
  String search = '';

  Future<void> load() async {
    final user = _auth.user;
    if (user == null) return;
    status = LoadStatus.loading;
    errorMessage = null;
    notifyListeners();

    final summary = await _repository.downloadData(employeeId: user.employeeId, salesOrg: _auth.salesOrg);
    if (await _handleFailure(summary)) return;
    final data = summary.data is Map<String, dynamic> ? summary.data as Map<String, dynamic> : <String, dynamic>{};
    final routeCalls = data['route_calls'];
    final list = routeCalls is Map ? routeCalls['list'] : null;
    final loaded = list is List
        ? list.whereType<Map<String, dynamic>>().map(RouteCall.fromJson).toList()
        : <RouteCall>[];

    var orders = <OrderDetail>[];
    final customerNumbers = loaded.map((c) => c.customerNumber).toSet().toList();
    if (customerNumbers.isNotEmpty) {
      final details = await _repository.orderDetails(customerNumbers);
      if (await _handleFailure(details)) return;
      if (details.data is List) {
        orders = (details.data as List).whereType<Map<String, dynamic>>().map(OrderDetail.fromJson).toList();
      }
    }

    calls = loaded;
    downloadData = data;
    _doneFromOrders = doneCustomers(loaded, orders);
    status = LoadStatus.loaded;
    notifyListeners();
  }

  /// Returns true (and updates state) when [result] is a failure the caller should stop on.
  Future<bool> _handleFailure(ApiEnvelope result) async {
    if (result.isSuccess) return false;
    if (result.isUnauthenticated) {
      await _auth.signOutLocally(message: 'Your session has expired. Please log in again.');
      return true;
    }
    status = LoadStatus.error;
    errorMessage = result.message.isNotEmpty ? result.message : 'Could not load the route calls.';
    notifyListeners();
    return true;
  }

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
