/// Mirrors the `suppliers` table / API payload from store_pos_backend
/// (see migrations/002_suppliers.sql and
/// src/validators/supplierValidators.js).
class Supplier {
  final String id;
  final String name;
  final String? contactName;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
  final bool isActive;

  const Supplier({
    required this.id,
    required this.name,
    this.contactName,
    this.phone,
    this.email,
    this.address,
    this.notes,
    this.isActive = true,
  });

  factory Supplier.fromJson(Map<String, dynamic> json) {
    return Supplier(
      id: json['id'] as String,
      name: json['name'] as String,
      contactName: json['contact_name'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      address: json['address'] as String?,
      notes: json['notes'] as String?,
      isActive: json['is_active'] is bool
          ? json['is_active'] as bool
          : (json['is_active'] as num? ?? 1) != 0,
    );
  }
}
