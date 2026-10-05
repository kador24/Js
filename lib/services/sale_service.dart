import '../database/database_helper.dart';
import '../models/sale.dart';

class SaleService {
  final DatabaseHelper _db = DatabaseHelper.instance;

  String _normalizePayment(String value) {
    const allowed = {'cash', 'card', 'transfer', 'credit'};
    return allowed.contains(value) ? value : 'cash';
  }

  Future<String> _generateInvoiceNumber(txn) async {
    final now = DateTime.now();
    final prefix = 'INV-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final rows = await txn.rawQuery('SELECT COUNT(*) AS cnt FROM sales WHERE invoice_number LIKE ?', ['$prefix%']);
    final count = ((rows.first['cnt'] as num?)?.toInt() ?? 0) + 1;
    return '$prefix-${count.toString().padLeft(3, '0')}';
  }

  Future<int> createSale({
    required List<Map<String, dynamic>> items,
    String? customerName,
    String? customerPhone,
    double discount = 0,
    String paymentMethod = 'cash',
    double? initialPayment,
    String? dueDate,
    String? notes,
  }) async {
    if (items.isEmpty) throw Exception('السلة فارغة');
    if (discount < 0) throw Exception('الخصم غير صحيح');
    final method = _normalizePayment(paymentMethod);
    final db = await _db.database;

    return db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      var subtotal = 0.0;
      var grossProfit = 0.0;
      final saleItems = <Map<String, dynamic>>[];

      for (final raw in items) {
        final productId = raw['productId'] as int?;
        final qty = (raw['quantity'] as num?)?.toInt() ?? 0;
        final unitPrice = (raw['unitPrice'] as num?)?.toDouble() ?? 0;
        if (productId == null || qty <= 0 || unitPrice < 0) throw Exception('بيانات المنتج غير صحيحة');

        final rows = await txn.query('products', where: 'id = ? AND is_active = 1', whereArgs: [productId]);
        if (rows.isEmpty) throw Exception('المنتج غير موجود');
        final product = rows.first;
        final stock = (product['stock'] as num).toInt();
        if (stock < qty) throw Exception('المخزون غير كافٍ للمنتج: ${product['name']}');
        final unitCost = (product['cost_price'] as num).toDouble();
        final lineTotal = unitPrice * qty;
        final lineProfit = (unitPrice - unitCost) * qty;
        subtotal += lineTotal;
        grossProfit += lineProfit;
        saleItems.add({
          'productId': productId,
          'productName': product['name'],
          'quantity': qty,
          'unitPrice': unitPrice,
          'unitCost': unitCost,
          'totalPrice': lineTotal,
          'profit': lineProfit,
        });
      }

      final total = subtotal - discount;
      if (total < 0) throw Exception('الخصم أكبر من قيمة الفاتورة');

      final paid = method == 'credit' ? (initialPayment ?? 0) : total;
      if (paid < 0 || paid > total) throw Exception('المبلغ المدفوع غير صحيح');
      if (method == 'credit' && paid < total && (dueDate == null || dueDate!.isEmpty)) {
        throw Exception('حدد تاريخ الاستحقاق للبيع الآجل');
      }

      final invoice = await _generateInvoiceNumber(txn);
      final saleId = await txn.insert('sales', {
        'invoice_number': invoice,
        'customer_name': customerName?.trim().isEmpty == true ? null : customerName?.trim(),
        'customer_phone': customerPhone?.trim().isEmpty == true ? null : customerPhone?.trim(),
        'subtotal': subtotal,
        'discount': discount,
        'total': total,
        'profit': grossProfit - discount,
        'payment_method': method,
        'paid_amount': paid,
        'due_date': method == 'credit' ? dueDate : null,
        'notes': notes,
        'sale_date': now,
        'created_at': now,
        'status': 'completed',
      });

      if (paid > 0) {
        await txn.insert('receivable_payments', {
          'sale_id': saleId,
          'amount': paid,
          'payment_type': 'collection',
          'payment_date': now,
          'note': 'دفعة عند إنشاء الفاتورة $invoice',
          'created_at': now,
        });
      }

      for (final item in saleItems) {
        final productId = item['productId'] as int;
        final qty = item['quantity'] as int;
        final rows = await txn.query('products', columns: ['stock'], where: 'id = ?', whereArgs: [productId]);
        final previous = (rows.first['stock'] as num).toInt();
        final next = previous - qty;
        await txn.insert('sale_items', {
          'sale_id': saleId,
          'product_id': productId,
          'product_name': item['productName'],
          'quantity': qty,
          'unit_price': item['unitPrice'],
          'unit_cost': item['unitCost'],
          'total_price': item['totalPrice'],
          'profit': item['profit'],
        });
        await txn.update('products', {'stock': next, 'updated_at': now}, where: 'id = ?', whereArgs: [productId]);
        await txn.insert('stock_movements', {
          'product_id': productId,
          'type': 'out',
          'quantity': qty,
          'previous_stock': previous,
          'new_stock': next,
          'reference_type': 'sale',
          'reference_id': saleId,
          'notes': 'بيع - $invoice',
          'created_at': now,
        });
      }
      return saleId;
    });
  }

  Future<void> returnSale(int saleId) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final sales = await txn.query('sales', where: 'id = ?', whereArgs: [saleId]);
      if (sales.isEmpty) throw Exception('الفاتورة غير موجودة');
      final sale = sales.first;
      if (sale['status'] == 'returned') throw Exception('الفاتورة مرتجعة بالفعل');
      final now = DateTime.now().toIso8601String();
      final items = await txn.query('sale_items', where: 'sale_id = ?', whereArgs: [saleId]);
      for (final item in items) {
        final productId = item['product_id'] as int;
        final quantity = item['quantity'] as int;
        final rows = await txn.query('products', columns: ['stock'], where: 'id = ?', whereArgs: [productId]);
        if (rows.isEmpty) continue;
        final previous = (rows.first['stock'] as num).toInt();
        final next = previous + quantity;
        await txn.update('products', {'stock': next, 'updated_at': now}, where: 'id = ?', whereArgs: [productId]);
        await txn.insert('stock_movements', {
          'product_id': productId,
          'type': 'return',
          'quantity': quantity,
          'previous_stock': previous,
          'new_stock': next,
          'reference_type': 'sale_return',
          'reference_id': saleId,
          'notes': 'إرجاع الفاتورة ${sale['invoice_number'] ?? saleId}',
          'created_at': now,
        });
      }
      final paidBeforeReturn = (sale['paid_amount'] as num?)?.toDouble() ?? 0;
      if (paidBeforeReturn > 0) {
        await txn.insert('receivable_payments', {
          'sale_id': saleId,
          'amount': paidBeforeReturn,
          'payment_type': 'refund',
          'payment_date': now,
          'note': 'رد المبلغ بسبب إرجاع الفاتورة ${sale['invoice_number'] ?? saleId}',
          'created_at': now,
        });
      }
      final oldNotes = (sale['notes'] as String?)?.trim() ?? '';
      await txn.update('sales', {
        'status': 'returned',
        'notes': oldNotes.isEmpty ? 'تم الإرجاع' : '$oldNotes • تم الإرجاع',
      }, where: 'id = ?', whereArgs: [saleId]);
    });
  }

  Future<Sale?> getById(int id) async {
    final db = await _db.database;
    final rows = await db.query('sales', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final sale = Sale.fromMap(rows.first);
    final items = await db.query('sale_items', where: 'sale_id = ?', whereArgs: [id], orderBy: 'id ASC');
    return Sale(
      id: sale.id,
      invoiceNumber: sale.invoiceNumber,
      customerName: sale.customerName,
      customerPhone: sale.customerPhone,
      subtotal: sale.subtotal,
      discount: sale.discount,
      total: sale.total,
      profit: sale.profit,
      paymentMethod: sale.paymentMethod,
      paidAmount: sale.paidAmount,
      dueDate: sale.dueDate,
      notes: sale.notes,
      saleDate: sale.saleDate,
      createdAt: sale.createdAt,
      status: sale.status,
      items: items.map(SaleItem.fromMap).toList(),
    );
  }

  Future<List<Sale>> getAll({DateTime? from, DateTime? to}) async {
    final db = await _db.database;
    var where = '1=1';
    final args = <dynamic>[];
    if (from != null) {
      where += ' AND sale_date >= ?';
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where += ' AND sale_date <= ?';
      args.add(to.toIso8601String());
    }
    final rows = await db.query('sales', where: where, whereArgs: args, orderBy: 'sale_date DESC');
    return rows.map(Sale.fromMap).toList();
  }

  Future<void> recordReceivablePayment(int saleId, double amount, {String? note}) async {
    if (amount <= 0) throw Exception('المبلغ يجب أن يكون أكبر من صفر');
    final db = await _db.database;
    await db.transaction((txn) async {
      final rows = await txn.query('sales', where: 'id = ?', whereArgs: [saleId]);
      if (rows.isEmpty) throw Exception('الفاتورة غير موجودة');
      final sale = Sale.fromMap(rows.first);
      if (sale.isReturned) throw Exception('لا يمكن التحصيل من فاتورة مرتجعة');
      if (sale.paymentMethod != 'credit') throw Exception('هذه الفاتورة ليست آجلة');
      final remaining = sale.remainingAmount;
      if (amount > remaining + 0.001) throw Exception('المبلغ أكبر من المتبقي');
      final now = DateTime.now().toIso8601String();
      await txn.insert('receivable_payments', {
        'sale_id': saleId,
        'amount': amount,
        'payment_type': 'collection',
        'payment_date': now,
        'note': note,
        'created_at': now,
      });
      await txn.update('sales', {'paid_amount': sale.paidAmount + amount}, where: 'id = ?', whereArgs: [saleId]);
    });
  }

  Future<List<Sale>> getReceivables() async {
    final sales = await getAll();
    return sales.where((sale) => !sale.isReturned && sale.remainingAmount > 0).toList();
  }

  Future<List<Map<String, dynamic>>> getReceivablePayments(int saleId) async {
    final db = await _db.database;
    return db.query('receivable_payments', where: 'sale_id = ?', whereArgs: [saleId], orderBy: 'payment_date DESC');
  }

  Future<Map<String, double>> getTodayStats() async {
    final db = await _db.database;
    final d = DateTime.now();
    final start = DateTime(d.year, d.month, d.day).toIso8601String();
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(total),0) AS sales,
             COALESCE(SUM(profit),0) AS profit,
             COUNT(*) AS count
      FROM sales
      WHERE sale_date >= ? AND status = 'completed'
    ''', [start]);
    return {
      'sales': (rows.first['sales'] as num).toDouble(),
      'profit': (rows.first['profit'] as num).toDouble(),
      'count': (rows.first['count'] as num).toDouble(),
    };
  }

  Future<List<Map<String, dynamic>>> getSalesChart({int days = 7}) async {
    final db = await _db.database;
    final result = <Map<String, dynamic>>[];
    final now = DateTime.now();
    for (var i = days - 1; i >= 0; i--) {
      final day = now.subtract(Duration(days: i));
      final start = DateTime(day.year, day.month, day.day).toIso8601String();
      final end = DateTime(day.year, day.month, day.day, 23, 59, 59, 999).toIso8601String();
      final rows = await db.rawQuery('''
        SELECT COALESCE(SUM(total),0) AS total
        FROM sales WHERE sale_date >= ? AND sale_date <= ? AND status = 'completed'
      ''', [start, end]);
      result.add({'date': '${day.day}/${day.month}', 'total': (rows.first['total'] as num).toDouble()});
    }
    return result;
  }
}
