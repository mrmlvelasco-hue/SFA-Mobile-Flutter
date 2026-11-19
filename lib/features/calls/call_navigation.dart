import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../master_data/master_data_state.dart';
import '../route_calls/route_call.dart';
import 'call_state.dart';

/// The call screens are pushed on the app's navigator, which sits above the signed-in providers,
/// so each push hands the providers it needs down again.
Future<T?> pushCallScreen<T>(BuildContext context, Widget screen, {String? name}) {
  final masterData = context.read<MasterDataState>();
  final calls = context.read<CallState>();
  return Navigator.of(context).push<T>(MaterialPageRoute(
    settings: RouteSettings(name: name),
    builder: (_) => MultiProvider(
      providers: [
        ChangeNotifierProvider<MasterDataState>.value(value: masterData),
        ChangeNotifierProvider<CallState>.value(value: calls),
      ],
      child: screen,
    ),
  ));
}

/// Route name of the Customer Master Data screen -- the order flow returns there once sent.
const customerRouteName = '/call/customer';

/// What every call screen needs to know about the call it's in.
class CallContext {
  CallContext(this.call);

  final RouteCall call;

  String get customerNumber => call.customerNumber;

  /// The route call row with the customer's fields (credit, channel, delivering plant, ...).
  Map<String, dynamic> get raw => call.raw;

  String text(String key) => (raw[key] ?? '').toString();
}

/// A simple OK/Cancel dialog; true when confirmed.
Future<bool> confirmDialog(BuildContext context, String title, String message,
    {String ok = 'OK', String cancel = 'Cancel', bool showCancel = true}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        if (showCancel) TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(cancel)),
        TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(ok)),
      ],
    ),
  );
  return result ?? false;
}

/// An OK-only message.
Future<void> messageDialog(BuildContext context, String title, String message) =>
    confirmDialog(context, title, message, showCancel: false);
