class Purchase {
  final int? id;
  final int? supplierId;
  final String? invoiceNumber;
  final double totalAmount;
  final String paymentMethod;
  final double paidAmount;
  final String? dueDate;
  final String? notes;
  final String purchaseDate;
  final String createdAt;
  final String? supplierName;
  final List<PurchaseItem> items;

  Purchase({
    this.id,
    this.supplierId,
    this.invoiceNumber,
    required this.totalAmount,
    this.paymentMethod = 'cash',
    this.paidAmount = 0,
    this.dueDate,
    this.notes,
    required this.purchaseDate,
    required this.createdAt,
    this.supplierName,
    this.items = const [],
  });

  double get remainingAmount => (totalAmount - paidAmount).clamp(0, double.infinity).toDouble();

  Map<String, dynamic> toMap() => {
        'id': id,
        'supplier_id': supplierId,
        'invoice_number': invoiceNumber,
        'total_amount': totalAmount,
        'payment_method': paymentMethod,
        'paid_amount': paidAmount,
        'due_date': dueDate,
        'notes': notes,
        'purchase_date': purchaseDate,
        'created_at': createdAt,
      };

  factory Purchase.fromMap(Map<String, dynamic> map) => Purchase(
        id: map['id'] as int?,
        supplierId: map['supplier_id'] as int?,
        invoiceNumber: map['invoice_number'] as String?,
        totalAmount: (map['total_amount'] as num? ?? 0).toDouble(),
        paymentMethod: map['payment_method'] as String? ?? 'cash',
        paidAmount: (map['paid_amount'] as num? ?? 0).toDouble(),
        dueDate: map['due_date'] as String?,
        notes: map['notes'] as String?,
        purchaseDate: map['purchase_date'] as String,
        createdAt: map['created_at'] as String,
        supplierName: map['supplier_name'] as String?,
      );
}

class PurchaseItem {
  final int? id;
  final int purchaseId;
  final int productId;
  final int quantity;
  final double unitCost;
  final double totalCost;
  final String? productName;

  PurchaseItem({
    this.id,
    required this.purchaseId,
    required this.productId,
    required this.quantity,
    required this.unitCost,
    required this.totalCost,
    this.productName,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'purchase_id': purchaseId,
        'product_id': productId,
        'quantity': quantity,
        'unit_cost': unitCost,
        'total_cost': totalCost,
      };

  factory PurchaseItem.fromMap(Map<String, dynamic> map) => PurchaseItem(
        id: map['id'] as int?,
        purchaseId: map['purchase_id'] as int,
        productId: map['product_id'] as int,
        quantity: map['quantity'] as int,
        unitCost: (map['unit_cost'] as num).toDouble(),
        totalCost: (map['total_cost'] as num).toDouble(),
        productName: map['product_name'] as String?,
      );
}
