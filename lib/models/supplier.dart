class Supplier {
  final int? id;
  final String name;
  final String? phone;
  final String? notes;
  final String createdAt;

  Supplier({
    this.id,
    required this.name,
    this.phone,
    this.notes,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'notes': notes,
        'created_at': createdAt,
      };

  factory Supplier.fromMap(Map<String, dynamic> map) => Supplier(
        id: map['id'] as int?,
        name: map['name'] as String,
        phone: map['phone'] as String?,
        notes: map['notes'] as String?,
        createdAt: map['created_at'] as String,
      );
}
