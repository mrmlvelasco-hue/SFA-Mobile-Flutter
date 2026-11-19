import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_colors.dart';
import '../../core/outbox.dart';
import '../calls/call_navigation.dart';
import '../calls/call_state.dart';
import '../calls/customer_screen.dart';
import 'route_call.dart';
import 'route_call_state.dart';

/// Today's customers to visit -- the RN app's RouteCallScheduleScreen.js.
///
/// Reads the downloaded master data, so it works offline (no refresh: the data is downloaded once
/// after login, as in the RN app).
///
/// Tapping a customer opens Customer Master Data (Start Call and the order flow). Calls started or
/// ended on this phone show as ongoing/done; requests saved offline show in a banner on top.
///
/// Not ported yet: the map of customer locations behind the list (needs a maps package + API
/// key, deferred with GPS) and the "You are offline" banner.
class RouteCallScheduleScreen extends StatefulWidget {
  const RouteCallScheduleScreen({super.key});

  @override
  State<RouteCallScheduleScreen> createState() => _RouteCallScheduleScreenState();
}

class _RouteCallScheduleScreenState extends State<RouteCallScheduleScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.text = context.read<RouteCallState>().search;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openCustomer(RouteCall call) {
    pushCallScreen(context, CustomerScreen(call: call), name: customerRouteName);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RouteCallState>();
    final calls = context.watch<CallState>();
    state.syncLocalCalls(
      ongoing: calls.calls.values.where((c) => c.status == CallStatus.ongoing).map((c) => c.customerNumber),
      done: calls.calls.values.where((c) => c.status == CallStatus.completed).map((c) => c.customerNumber),
    );
    return Column(
      children: [
        const _OutboxBanner(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              DropdownButton<RouteCallFilter>(
                key: const Key('scheduleFilter'),
                value: state.filter,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: RouteCallFilter.scheduled, child: Text('Scheduled')),
                  DropdownMenuItem(value: RouteCallFilter.unscheduled, child: Text('Unscheduled')),
                ],
                onChanged: (value) {
                  if (value != null) state.setFilter(value);
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const Key('customerSearch'),
                  controller: _searchController,
                  onChanged: state.setSearch,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: 'Search customer',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _body(state)),
      ],
    );
  }

  Widget _body(RouteCallState state) {
    final items = state.visible;
    if (items.isEmpty) {
      return const Center(child: Text('No Data', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: items.length + 1,
      itemBuilder: (context, index) {
        if (index == items.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('Displaying ${items.length} Customer',
                textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
          );
        }
        final call = items[index];
        return _RouteCallTile(
          number: index + 1,
          call: call,
          done: state.isDone(call.customerNumber),
          ongoing: state.isOngoing(call.customerNumber),
          onTap: () => _openCustomer(call),
        );
      },
    );
  }
}

class _RouteCallTile extends StatelessWidget {
  const _RouteCallTile({required this.number, required this.call, required this.done, required this.ongoing, required this.onTap});

  final int number;
  final RouteCall call;
  final bool done;
  final bool ongoing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final background = ongoing ? AppColors.orange : (done ? AppColors.green : AppColors.gray2);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(5),
        child: InkWell(
          key: Key('routeCall-${call.customerNumber}'),
          borderRadius: BorderRadius.circular(5),
          onTap: onTap,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 15),
                margin: const EdgeInsets.symmetric(vertical: 5),
                decoration: const BoxDecoration(border: Border(right: BorderSide(color: Color(0xFFE0E0E0), width: 2))),
                // 01, 02, ... 10, 11 -- the RN app's numbering().
                child: Text(number.toString().padLeft(2, '0'), style: const TextStyle(fontSize: 28, color: AppColors.grayFont)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(call.outletName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.grayFont)),
                      Text(call.ownerName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.grayFont)),
                      // The RN app repeats outlet_name on this line (a copy-paste slip); the
                      // address is what the third line was evidently meant to show.
                      Text(call.address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 11, color: AppColors.grayFont)),
                    ],
                  ),
                ),
              ),
              if (ongoing)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Text('Call Ongoing', style: TextStyle(color: AppColors.grayFont, fontWeight: FontWeight.w600, fontSize: 9)),
                )
              else if (done)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Text('Done', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600, fontSize: 12)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Requests saved offline (orders, outlet inventory, end calls): how many are waiting, a Send now
/// button, and any the server rejected.
class _OutboxBanner extends StatelessWidget {
  const _OutboxBanner();

  @override
  Widget build(BuildContext context) {
    final outbox = context.watch<Outbox>();
    final failed = outbox.items.where((i) => i.failed).toList();
    if (outbox.pendingCount == 0 && failed.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: AppColors.orange.withAlpha(80),
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (outbox.pendingCount > 0)
            Row(
              children: [
                Expanded(child: Text('${outbox.pendingCount} saved offline, waiting to be sent')),
                TextButton(key: const Key('outboxSend'), onPressed: outbox.flush, child: const Text('Send now')),
              ],
            ),
          for (final item in failed)
            Row(
              children: [
                Expanded(
                  child: Text('${item.kind} not accepted: ${item.lastError ?? ''}',
                      style: const TextStyle(color: AppColors.red2, fontSize: 12)),
                ),
                TextButton(onPressed: () => outbox.discard(item.id), child: const Text('Dismiss')),
              ],
            ),
        ],
      ),
    );
  }
}
