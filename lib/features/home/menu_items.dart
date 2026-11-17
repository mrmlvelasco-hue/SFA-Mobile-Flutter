/// Mirrors the menu structure of the RN app's DrawerNavigation/CustomDrawer
/// (src/navigation/DrawerNavigation.js). `ported: true` means a real screen
/// exists at `route`; otherwise it opens ComingSoonScreen with this label.
class MenuItem {
  final String label;
  final String route;
  final bool ported;

  const MenuItem({required this.label, required this.route, this.ported = false});
}

const List<MenuItem> drawerMenuItems = [
  MenuItem(label: 'Route Call Schedule', route: '/route-call-schedule'),
  MenuItem(label: 'Order Management', route: '/order-management'),
  MenuItem(label: 'Order Status', route: '/order-status'),
  MenuItem(label: 'Payment Collection', route: '/payment-collection'),
  MenuItem(label: 'Sales Return', route: '/sales-return'),
  MenuItem(label: 'Outlet Inventory', route: '/outlet-inventory'),
  MenuItem(label: 'DC Inventory', route: '/dc-inventory'),
  MenuItem(label: 'Floor Stock Inventory', route: '/floor-stock-inventory'),
  MenuItem(label: 'Empties Pullout', route: '/empties-pullout'),
  MenuItem(label: 'Subsidiary Ledger', route: '/subsidiary-ledger'),
  MenuItem(label: 'Customer Master Data', route: '/customer-master-data'),
  MenuItem(label: 'Route Productivity', route: '/route-productivity'),
  MenuItem(label: 'Sales Inquiries', route: '/sales-inquiries'),
  MenuItem(label: 'Non-Sales Activities', route: '/non-sales-activities'),
  MenuItem(label: 'Feedback', route: '/feedback'),
  MenuItem(label: 'My Profile', route: '/profile'),
  MenuItem(label: 'Change Password', route: '/change-password'),
];
