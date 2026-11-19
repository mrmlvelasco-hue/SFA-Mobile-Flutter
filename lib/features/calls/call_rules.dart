import '../../core/formatting.dart';
import 'order_draft.dart';

/// Business rules of the call -> order flow that don't belong to one screen, ported from the RN
/// app (CustomerMasterDataComponent, OrderManagementScreen, OrderSummaryScreen) and kept pure so
/// they can be unit-tested.

/// JavaScript truthiness: null, false, 0, NaN and '' are false; anything else ('0' included) true.
/// The RN app tests `constants.allowed_ocl` this way.
bool jsTruthy(dynamic value) {
  if (value == null || value == false) return false;
  if (value is num) return value != 0 && !value.isNaN;
  if (value is String) return value.isNotEmpty;
  return true;
}

/// Add Order needs today's outlet inventory first -- except for customers whose account status
/// matches /NREQ*/ (e.g. 'Mixed NREQ': outlet inventory not required).
bool outletInventoryRequired(Map<String, dynamic> routeCall) =>
    !RegExp('NREQ*').hasMatch((routeCall['account_status_desc'] ?? '').toString());

/// Why Add Order is blocked for this customer, or null when it isn't (OrderManagementScreen:
/// `!allow_ocl && credit_balance <= 0` disables the button).
String? addOrderBlockedReason(Map<String, dynamic> routeCall, dynamic allowedOcl) {
  final balance = asNum(routeCall['credit_balance']) ?? 0;
  if (!jsTruthy(allowedOcl) && balance <= 0) {
    return 'This customer has no remaining credit balance, so orders can\'t be added.';
  }
  return null;
}

/// The ship-to choices: the customer's Ship-To-Party partners (download's `partners`).
List<ShipTo> shipTosFor(Map<String, dynamic> data, String customerNumber) {
  final partners = data['partners'];
  final out = <ShipTo>[];
  if (partners is! List) return out;
  for (final p in partners.whereType<Map>()) {
    if ((p['customer_number'] ?? '').toString() != customerNumber) continue;
    final func = (p['partner_func'] ?? '').toString();
    if (func.isNotEmpty && func != 'Ship-To-Party') continue;
    final address = (p['address'] ?? '').toString();
    if (out.any((s) => s.address == address)) continue; // the address is the choice's key
    out.add(ShipTo(
      address: address,
      partnerNumber: (p['customer_partner'] ?? '').toString(),
    ));
  }
  return out;
}

/// The distribution centers to choose from (constants.sales_offices).
List<Map<String, dynamic>> salesOfficesOf(Map<String, dynamic> data) {
  final constants = data['constants'];
  final offices = constants is Map ? constants['sales_offices'] : null;
  return offices is List ? offices.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList() : [];
}

/// The customer's claimable rebates (download's `rebates`).
List<Rebate> rebatesFor(Map<String, dynamic> data, String customerNumber) {
  final rebates = data['rebates'];
  if (rebates is! List) return const [];
  return [
    for (final r in rebates.whereType<Map>())
      if ((r['customer_number'] ?? '').toString() == customerNumber)
        Rebate(
          number: (r['rebate_number'] ?? '').toString(),
          balance: asNum(r['balance']) ?? 0,
          description: (r['customer_name'] ?? '').toString(),
        ),
  ];
}

/// The customer's promos (download's `customer_promo`), shown read-only for now.
List<Map<String, dynamic>> promosFor(Map<String, dynamic> data, String customerNumber) {
  final promos = data['customer_promo'];
  if (promos is! List) return const [];
  return [
    for (final p in promos.whereType<Map>())
      if ((p['customer_number'] ?? '').toString() == customerNumber) Map<String, dynamic>.from(p),
  ];
}

enum CreditOutcome { proceed, warnThenProceed, blocked }

class CreditCheck {
  const CreditCheck(this.outcome, [this.message]);
  final CreditOutcome outcome;
  final String? message;
}

/// The Order Summary submit check (handleOnPressSubmit). COD customers always pass; for others it
/// depends on constants.allowed_ocl and the credit balance. [amount] is the net gross.
CreditCheck creditCheck({
  required String creditTerm,
  required num creditBalance,
  required dynamic allowedOcl,
  required num amount,
  required DateTime deliveryDate,
}) {
  if (creditTerm == 'COD') return const CreditCheck(CreditOutcome.proceed);
  final ocl = jsTruthy(allowedOcl);
  final date = '${deliveryDate.month.toString().padLeft(2, '0')}/${deliveryDate.day.toString().padLeft(2, '0')}/${deliveryDate.year}';
  final overLimit =
      'Your Transaction is over the credit limit. If this is not Approved before $date, The Transaction will be cancelled';
  if (ocl && creditBalance > 0) {
    return amount > creditBalance
        ? CreditCheck(CreditOutcome.warnThenProceed, overLimit)
        : const CreditCheck(CreditOutcome.proceed);
  }
  if (ocl) return CreditCheck(CreditOutcome.warnThenProceed, overLimit);
  if (creditBalance > 0) {
    return amount > creditBalance
        ? const CreditCheck(CreditOutcome.blocked,
            'Order Amount is already over the credit limit. Please revisit remanining balance to continue with the order')
        : const CreditCheck(CreditOutcome.proceed);
  }
  // The RN app does nothing at all here (its Add Order button is already disabled in this case).
  return const CreditCheck(CreditOutcome.blocked, 'This customer has no remaining credit balance.');
}
