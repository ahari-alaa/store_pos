/// The logged-in staff member. Mirrors the `users` table / the shape
/// returned by POST /api/auth/login and GET /api/auth/me (see
/// store_pos_backend/src/services/authService.js#toPublicUser).
class AppUser {
  final String id;
  final String? storeId;
  final String name;
  final String email;

  /// One of 'admin', 'manager', 'cashier' (see migrations/001_init.sql).
  final String role;
  final bool isActive;

  const AppUser({
    required this.id,
    required this.storeId,
    required this.name,
    required this.email,
    required this.role,
    required this.isActive,
  });

  bool get canManageProducts => role == 'admin' || role == 'manager';
  bool get canManageInventory => role == 'admin' || role == 'manager';
  bool get canManageSuppliers => role == 'admin' || role == 'manager';
  bool get canManageExpenses => role == 'admin' || role == 'manager';
  bool get canViewReports => role == 'admin' || role == 'manager';
  // "Paiements caissiers" (spec §22-§23, §26, §33) — mirrors the backend's
  // 'cashier_settlements.view'/'manage' permissions (authorize.js): admin
  // and manager both see every cashier's settlements and can mark them
  // paid; a cashier never does, however this getter is read.
  bool get canManageCashierSettlements => role == 'admin' || role == 'manager';
  bool get isAdmin => role == 'admin';

  /// The cashier role gets a deliberately tiny app: Caisse, Ventes and its
  /// own Rapport (see core/router/nav_access.dart). The backend enforces the
  /// same limits — this getter only drives what the UI shows.
  bool get isCashier => role == 'cashier';

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as String,
      storeId: json['store_id'] as String?,
      name: json['name'] as String,
      email: json['email'] as String,
      role: json['role'] as String,
      isActive: json['is_active'] is bool
          ? json['is_active'] as bool
          : (json['is_active'] as num? ?? 1) != 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'store_id': storeId,
        'name': name,
        'email': email,
        'role': role,
        'is_active': isActive,
      };
}
