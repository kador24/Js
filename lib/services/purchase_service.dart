import '../database/database_helper.dart';
import '../models/purchase.dart';

class PurchaseService {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<int> createPurchase({
    int? supplierId,
    String? invoiceNumber,
    String? notes,
    String paymentMethod = 'cash',
    double? paidAmount,
    String? dueDate,
    required List<Map<String, dynamic>> items,
  }) async {
    if (items.isEmpty) throw Exception('أضف منتجًا واحدًا على الأقل');
    final db = await _db.database;
    return db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      var total = 0.0;
      final normalized = <Map<String, dynamic>>[];
      for (final item in items) {
        final productId = item['productId'] as int?;
        final qty = (item['quantity'] as num?)?.toInt() ?? 0;
        final unitCost = (item['unitCost'] as num?)?.toDouble() ?? 0;
        if (productId == null || qty <= 0 || unitCost < 0) throw Exception('بيانات الشراء غير صحيحة');
        final rows = await txn.query('products', where: 'id = ? AND is_active = 1', whereArgs: [productId]);
        if (rows.isEmpty) throw Exception('المنتج غير موجود');
        total += qty * unitCost;
        normalized.add({'productId': productId, 'quantity': qty, 'unitCost': unitCost});
      }

      final paid = paymentMethod == 'credit' ? (paidAmount ?? 0) : total;
      if (paid < 0 || paid > total) throw Exception('المبلغ المدفوع غير صحيح');
      if (paymentMethod == 'credit' && paid < total && (dueDate == null || dueDate.isEmpty)) {
        throw Exception('حدد تاريخ الاستحقاق للمشتريات الآجلة');
      }

      final purchaseId = await txn.insert('purchases', {
        'supplier_id': supplierId,
        'invoice_number': invoiceNumber?.trim().isEmpty == true ? null : invoiceNumber?.trim(),
        'total_amount': total,
        'payment_method': paymentMethod,
        'paid_amount': paid,
        'due_date': dueDate,
        'notes': notes,
        'purchase_date': now,
        'created_at': now,
      });

      for (final item in normalized) {
        final productId = item['productId'] as int;
        final qty = item['quantity'] as int;
        final unitCost = item['unitCost'] as double;
        final rows = await txn.query('products', where: 'id = ?', whereArgs: [productId]);
        final product = rows.first;
        final previous = (product['stock'] as num).toInt();
        final oldCost = (product['cost_price'] as num).toDouble();
        final newStock = previous + qty;
        final weightedCost = newStock == 0 ? unitCost : ((previous * oldCost) + (qty * unitCost)) / newStock;

        await txn.insert('purchase_items', {
          'purchase_id': purchaseId,
          'product_id': productId,
          'quantity': qty,
          'unit_cost': unitCost,
          'total_cost': qty * unitCost,
        });
        await txn.update('products', {
          'stock': newStock,
          'cost_price': weightedCost,
          'updated_at': now,
        }, where: 'id = ?', whereArgs: [productId]);
        await txn.insert('stock_movements', {
          'product_id': productId,
          'type': 'in',
          'quantity': qty,
          'previous_stock': previous,
          'new_stock': newStock,
          'reference_type': 'purchase',
          'reference_id': purchaseId,
          'notes': 'شراء',
          'created_at': now,
        });
      }
      return purchaseId;
    });
  }

  Future<List<Purchase>> getAll({DateTime? from, DateTime? to}) async {
    final db = await _db.database;
    var where = '1=1';
    final args = <dynamic>[];
    if (from != null) {
      where += ' AND p.purchase_date >= ?';
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where += ' AND p.purchase_date <= ?';
      args.add(to.toIso8601String());
    }
    final rows = await db.rawQuery('''
      SELECT p.*, s.name AS supplier_name
      FROM purchases p
      LEFT JOIN suppliers s ON s.id = p.supplier_id
      WHERE $where
      ORDER BY p.purchase_date DESC
    ''', args);
    return rows.map(Purchase.fromMap).toList();
  }

  Future<Purchase?> getById(int id) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT p.*, s.name AS supplier_name
      FROM purchases p
      LEFT JOIN suppliers s ON s.id = p.supplier_id
      WHERE p.id = ?
    ''', [id]);
    if (rows.isEmpty) return null;
    final purchase = Purchase.fromMap(rows.first);
    final itemRows = await db.rawQuery('''
      SELECT pi.*, pr.name AS product_name
      FROM purchase_items pi
      JOIN products pr ON pr.id = pi.product_id
      WHERE pi.purchase_id = ?
      ORDER BY pi.id ASC
    ''', [id]);
    return Purchase(
      id: purchase.id,
      supplierId: purchase.supplierId,
      invoiceNumber: purchase.invoiceNumber,
      totalAmount: purchase.totalAmount,
      paymentMethod: purchase.paymentMethod,
      paidAmount: purchase.paidAmount,
      dueDate: purchase.dueDate,
      notes: purchase.notes,
      purchaseDate: purchase.purchaseDate,
      createdAt: purchase.createdAt,
      supplierName: purchase.supplierName,
      items: itemRows.map(PurchaseItem.fromMap).toList(),
    );
  }
}
