class Sale {
  final int? id;
  final String? invoiceNumber;
  final String? customerName;
  final String? customerPhone;
  final double subtotal;
  final double discount;
  final double total;
  final double profit;
  final String paymentMethod;
  final double paidAmount;
  final String? dueDate;
  final String? notes;
  final String saleDate;
  final String createdAt;
  final String status;
  final List<SaleItem> items;

  Sale({
    this.id,
    this.invoiceNumber,
    this.customerName,
    this.customerPhone,
    required this.subtotal,
    this.discount = 0,
    required this.total,
    required this.profit,
    this.paymentMethod = 'cash',
    this.paidAmount = 0,
    this.dueDate,
    this.notes,
    required this.saleDate,
    required this.createdAt,
    this.status = 'completed',
    this.items = const [],
  });

  double get remainingAmount => isReturned ? 0 : (total - paidAmount).clamp(0, double.infinity).toDouble();
  bool get isReturned => status == 'returned';
  bool get isCredit => paymentMethod == 'credit' && remainingAmount > 0;

  Map<String, dynamic> toMap() => {
        'id': id,
        'invoice_number': invoiceNumber,
        'customer_name': customerName,
        'customer_phone': customerPhone,
        'subtotal': subtotal,
        'discount': discount,
        'total': total,
        'profit': profit,
        'payment_method': paymentMethod,
        'paid_amount': paidAmount,
        'due_date': dueDate,
        'notes': notes,
        'sale_date': saleDate,
        'created_at': createdAt,
        'status': status,
      };

  factory Sale.fromMap(Map<String, dynamic> map) => Sale(
        id: map['id'] as int?,
        invoiceNumber: map['invoice_number'] as String?,
        customerName: map['customer_name'] as String?,
        customerPhone: map['customer_phone'] as String?,
        subtotal: (map['subtotal'] as num? ?? 0).toDouble(),
        discount: (map['discount'] as num? ?? 0).toDouble(),
        total: (map['total'] as num? ?? 0).toDouble(),
        profit: (map['profit'] as num? ?? 0).toDouble(),
        paymentMethod: map['payment_method'] as String? ?? 'cash',
        paidAmount: (map['paid_amount'] as num? ?? 0).toDouble(),
        dueDate: map['due_date'] as String?,
        notes: map['notes'] as String?,
        saleDate: map['sale_date'] as String,
        createdAt: map['created_at'] as String,
        status: map['status'] as String? ?? 'completed',
      );
}

class SaleItem {
  final int? id;
  final int saleId;
  final int productId;
  final String productName;
  final int quantity;
  final double unitPrice;
  final double unitCost;
  final double totalPrice;
  final double profit;

  SaleItem({
    this.id,
    required this.saleId,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.unitCost,
    required this.totalPrice,
    required this.profit,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'sale_id': saleId,
        'product_id': productId,
        'product_name': productName,
        'quantity': quantity,
        'unit_price': unitPrice,
        'unit_cost': unitCost,
        'total_price': totalPrice,
        'profit': profit,
      };

  factory SaleItem.fromMap(Map<String, dynamic> map) => SaleItem(
        id: map['id'] as int?,
        saleId: map['sale_id'] as int,
        productId: map['product_id'] as int,
        productName: map['product_name'] as String,
        quantity: map['quantity'] as int,
        unitPrice: (map['unit_price'] as num).toDouble(),
        unitCost: (map['unit_cost'] as num).toDouble(),
        totalPrice: (map['total_price'] as num).toDouble(),
        profit: (map['profit'] as num).toDouble(),
      );
}
