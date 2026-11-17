/// The subset of the login response's `data.user` the app actually reads.
/// The backend returns many more fields (see user_json in auth.py); add
/// them here as screens need them rather than modelling the whole row.
class SfaUser {
  final int id;
  final String employeeId;
  final String username;
  final String fullName;
  final List<String> locationSalesOffice;

  SfaUser({
    required this.id,
    required this.employeeId,
    required this.username,
    required this.fullName,
    required this.locationSalesOffice,
  });

  factory SfaUser.fromJson(Map<String, dynamic> json) {
    return SfaUser(
      id: (json['id'] as num?)?.toInt() ?? 0,
      employeeId: (json['employee_id'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      fullName: (json['full_name'] ?? '').toString(),
      locationSalesOffice: (json['location_sales_office'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }
}
