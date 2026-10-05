class StockMovement {
  final int? id;
  final int productId;
  final String type; // in, out, return, adjust
  final int quantity;
  final int previousStock;
  final int newStock;
  final String? referenceType;
  final int? referenceId;
  final String? notes;
  final String createdAt;
  final String? productName;

  StockMovement({
    this.id,
    required this.productId,
    required this.type,
    required this.quantity,
    required this.previousStock,
    required this.newStock,
    this.referenceType,
    this.referenceId,
    this.notes,
    required this.createdAt,
    this.productName,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'product_id': productId,
      'type': type,
      'quantity': quantity,
      'previous_stock': previousStock,
      'new_stock': newStock,
      'reference_type': referenceType,
      'reference_id': referenceId,
      'notes': notes,
      'created_at': createdAt,
    };
  }

  factory StockMovement.fromMap(Map<String, dynamic> map) {
    return StockMovement(
      id: map['id'] as int?,
      productId: map['product_id'] as int,
      type: map['type'] as String,
      quantity: map['quantity'] as int,
      previousStock: map['previous_stock'] as int,
      newStock: map['new_stock'] as int,
      referenceType: map['reference_type'] as String?,
      referenceId: map['reference_id'] as int?,
      notes: map['notes'] as String?,
      createdAt: map['created_at'] as String,
      productName: map['product_name'] as String?,
    );
  }
}
