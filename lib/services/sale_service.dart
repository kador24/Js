import '../models/sale.dart';
import '../repositories/store_repository.dart';
import '../utils/money.dart';

class SaleService {
  SaleService({StoreRepository? repository})
      : _repo = repository ?? StoreRepository();

  final StoreRepository _repo;

  static const paymentMethods = {'cash', 'card', 'transfer', 'credit'};

  String _normalizePayment(String value) {
    if (!paymentMethods.contains(value)) throw Exception('طريقة الدفع غير صحيحة');
    return value;
  }

  Future<String> _generateInvoiceNumber(dynamic txn) async {
    final now = DateTime.now();
    final prefix =
        'INV-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final rows = await txn.rawQuery(
      'SELECT COUNT(*) AS cnt FROM sales WHERE invoice_number LIKE ?',
      ['$prefix%'],
    );
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
    String initialPaymentMethod = 'cash',
    String? dueDate,
    String? notes,
    String? initialPaymentNote,
  }) async {
    if (items.isEmpty) throw Exception('السلة فارغة');
    final cleanDiscount = Money.round(discount);
    if (cleanDiscount < 0) throw Exception('الخصم غير صحيح');
    final method = _normalizePayment(paymentMethod);

    return _repo.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      var subtotal = 0.0;
      final saleItems = <Map<String, dynamic>>[];

      for (final raw in items) {
        final productId = raw['productId'] as int?;
        final qty = (raw['quantity'] as num?)?.toInt() ?? 0;
        final unitPrice = Money.round(
          (raw['unitPrice'] as num?)?.toDouble() ?? -1,
        );
        if (productId == null || qty <= 0 || unitPrice < 0) {
          throw Exception('بيانات المنتج غير صحيحة');
        }
        final rows = await txn.query(
          'products',
          columns: ['id', 'name', 'stock', 'cost_price'],
          where: 'id = ? AND is_active = 1',
          whereArgs: [productId],
        );
        if (rows.isEmpty) throw Exception('المنتج غير موجود');
        final product = rows.first;
        final stock = (product['stock'] as num).toInt();
        if (stock < qty) throw Exception('المخزون غير كافٍ للمنتج: ${product['name']}');
        final unitCost = Money.round((product['cost_price'] as num).toDouble());
        final lineTotal = Money.multiply(unitPrice, qty);
        final lineProfit = Money.multiply(unitPrice - unitCost, qty);
        subtotal = Money.add(subtotal, lineTotal);
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

      final total = Money.subtract(subtotal, cleanDiscount);
      if (total < 0) throw Exception('الخصم أكبر من قيمة الفاتورة');

      // Allocate invoice discount across historical sale_items so recorded
      // gross profit equals net revenue minus historical COGS. The last item
      // receives any rounding remainder to keep the total exact.
      if (cleanDiscount > 0 && subtotal > 0 && saleItems.isNotEmpty) {
        var allocatedDiscount = 0.0;
        for (var i = 0; i < saleItems.length; i++) {
          final lineTotal = saleItems[i]['totalPrice'] as double;
          final allocation = i == saleItems.length - 1
              ? Money.round(cleanDiscount - allocatedDiscount)
              : Money.round(cleanDiscount * lineTotal / subtotal);
          allocatedDiscount = Money.add(allocatedDiscount, allocation);
          saleItems[i]['profit'] = Money.round(
            (saleItems[i]['profit'] as double) - allocation,
          );
        }
      }

      final paid = method == 'credit'
          ? Money.round(initialPayment ?? 0)
          : total;
      if (method == 'credit' && paid > 0 && !{'cash', 'card', 'transfer'}.contains(initialPaymentMethod)) {
        throw Exception('طريقة الدفعة الأولى غير صحيحة');
      }
      if (paid < 0 || paid > total + 0.005) {
        throw Exception('المبلغ المدفوع غير صحيح');
      }
      final remaining = Money.subtract(total, paid);
      if (remaining > 0 && (dueDate == null || dueDate.isEmpty)) {
        throw Exception('حدد تاريخ الاستحقاق للبيع الآجل');
      }

      final invoice = await _generateInvoiceNumber(txn);
      final saleProfit = Money.round(
        saleItems.fold<double>(0, (sum, item) => Money.add(sum, item['profit'] as double)),
      );
      final saleId = await txn.insert('sales', {
        'invoice_number': invoice,
        'customer_name': customerName?.trim().isEmpty == true ? null : customerName?.trim(),
        'customer_phone': customerPhone?.trim().isEmpty == true ? null : customerPhone?.trim(),
        'subtotal': subtotal,
        'discount': cleanDiscount,
        'total': total,
        'profit': saleProfit,
        'payment_method': method,
        'paid_amount': paid,
        'due_date': remaining > 0 ? dueDate : null,
        'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
        'sale_date': now,
        'created_at': now,
        'status': 'completed',
      });

      for (final item in saleItems) {
        final productId = item['productId'] as int;
        final qty = item['quantity'] as int;
        final rows = await txn.query(
          'products',
          columns: ['stock'],
          where: 'id = ? AND is_active = 1',
          whereArgs: [productId],
        );
        if (rows.isEmpty) throw Exception('المنتج غير موجود');
        final previous = (rows.first['stock'] as num).toInt();
        final next = previous - qty;
        if (next < 0) throw Exception('المخزون غير كافٍ');

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
        await txn.update(
          'products',
          {'stock': next, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [productId],
        );
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
          'delta_quantity': -qty,
          'reason_code': 'sale',
        });
      }

      if (paid > 0) {
        await _recordSalePayment(
          txn,
          saleId: saleId,
          amount: paid,
          paymentMethod: method == 'credit' ? initialPaymentMethod : method,
          note: initialPaymentNote?.trim().isEmpty == true
              ? 'دفعة عند إنشاء الفاتورة $invoice'
              : initialPaymentNote?.trim(),
          paymentDate: now,
          paymentType: 'sale_payment',
        );
      }

      return saleId;
    });
  }

  Future<void> returnSale(int saleId) async {
    await _repo.transaction((txn) async {
      final sales = await txn.query('sales', where: 'id = ?', whereArgs: [saleId]);
      if (sales.isEmpty) throw Exception('الفاتورة غير موجودة');
      final sale = sales.first;
      if (sale['status'] == 'returned') throw Exception('الفاتورة مرتجعة بالفعل');

      final items = await txn.query(
        'sale_items',
        where: 'sale_id = ?',
        whereArgs: [saleId],
        orderBy: 'id ASC',
      );
      final now = DateTime.now().toIso8601String();
      for (final item in items) {
        final productId = item['product_id'] as int;
        final quantity = (item['quantity'] as num).toInt();
        final returnedUnitCost = (item['unit_cost'] as num).toDouble();
        final rows = await txn.query(
          'products',
          columns: ['stock', 'cost_price'],
          where: 'id = ?',
          whereArgs: [productId],
        );
        if (rows.isEmpty) throw Exception('منتج في الفاتورة غير موجود: $productId');
        final previous = (rows.first['stock'] as num).toInt();
        final currentCost = (rows.first['cost_price'] as num).toDouble();
        final next = previous + quantity;
        final restoredCost = Money.weightedAverage(
          oldQuantity: previous,
          oldUnitCost: currentCost,
          incomingQuantity: quantity,
          incomingUnitCost: returnedUnitCost,
        );
        await txn.update(
          'products',
          {'stock': next, 'cost_price': restoredCost, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [productId],
        );
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
          'delta_quantity': quantity,
          'reason_code': 'sale_return',
        });
      }

      final paymentRows = await txn.query(
        'payment_ledger',
        where: "reference_type = ? AND reference_id = ? AND direction = 'in' AND entry_type IN ('sale_payment','customer_collection')",
        whereArgs: ['sale', saleId],
        orderBy: 'id ASC',
      );
      for (final payment in paymentRows) {
        final amount = Money.round((payment['amount'] as num).toDouble());
        if (amount <= 0) continue;
        final paymentMethod = payment['payment_method'] as String? ??
            (sale['payment_method'] as String? == 'credit' ? 'cash' : sale['payment_method'] as String? ?? 'cash');
        await _recordSalePayment(
          txn,
          saleId: saleId,
          amount: amount,
          paymentMethod: paymentMethod,
          note: 'رد الدفعة الأصلية بسبب إرجاع الفاتورة ${sale['invoice_number'] ?? saleId}',
          paymentDate: now,
          paymentType: 'refund',
        );
      }

      final oldNotes = (sale['notes'] as String?)?.trim() ?? '';
      await txn.update(
        'sales',
        {
          'status': 'returned',
          'paid_amount': 0,
          'notes': oldNotes.isEmpty ? 'تم الإرجاع' : '$oldNotes • تم الإرجاع',
        },
        where: 'id = ?',
        whereArgs: [saleId],
      );
    });
  }

  Future<void> _recordSalePayment(
    dynamic txn, {
    required int saleId,
    required double amount,
    required String paymentMethod,
    required String? note,
    required String paymentDate,
    required String paymentType,
  }) async {
    final legacyPaymentType = paymentType == 'refund' || paymentType == 'sale_refund' ? 'refund' : 'collection';
    final paymentId = await txn.insert('receivable_payments', {
      'sale_id': saleId,
      'amount': Money.round(amount),
      'payment_type': legacyPaymentType,
      'payment_date': paymentDate,
      'note': note,
      'created_at': paymentDate,
    });
    await txn.insert('payment_ledger', {
      'direction': paymentType == 'refund' ? 'out' : 'in',
      'entry_type': paymentType == 'refund'
          ? 'sale_refund'
          : paymentType,
      'amount': Money.round(amount),
      'payment_method': paymentMethod,
      'source_table': 'receivable_payments',
      'source_id': paymentId,
      'reference_type': 'sale',
      'reference_id': saleId,
      'note': note,
      'transaction_date': paymentDate,
      'created_at': paymentDate,
    });
  }

  Future<void> recordReceivablePayment(
    int saleId,
    double amount, {
    String paymentMethod = 'cash',
    String? note,
  }) async {
    final cleanAmount = Money.round(amount);
    if (cleanAmount <= 0) throw Exception('المبلغ يجب أن يكون أكبر من صفر');
    if (!{'cash', 'card', 'transfer'}.contains(paymentMethod)) {
      throw Exception('طريقة التحصيل غير صحيحة');
    }

    await _repo.transaction((txn) async {
      final rows = await txn.query('sales', where: 'id = ?', whereArgs: [saleId]);
      if (rows.isEmpty) throw Exception('الفاتورة غير موجودة');
      if (rows.first['status'] == 'returned') throw Exception('لا يمكن التحصيل من فاتورة مرتجعة');
      if (rows.first['payment_method'] != 'credit') throw Exception('هذه الفاتورة ليست آجلة');

      final paidRows = await txn.rawQuery('''
        SELECT
          COALESCE(SUM(CASE WHEN direction='in' AND entry_type IN ('sale_payment','customer_collection') THEN amount ELSE 0 END),0) AS paid,
          COALESCE(SUM(CASE WHEN direction='out' AND entry_type='sale_refund' THEN amount ELSE 0 END),0) AS refunded
        FROM payment_ledger
        WHERE reference_type = 'sale' AND reference_id = ?
      ''', [saleId]);
      final paid = (paidRows.first['paid'] as num?)?.toDouble() ?? 0;
      final refunded = (paidRows.first['refunded'] as num?)?.toDouble() ?? 0;
      final total = (rows.first['total'] as num?)?.toDouble() ?? 0;
      final remaining = Money.round(total - paid + refunded);
      if (cleanAmount > remaining + 0.005) throw Exception('المبلغ أكبر من المتبقي');

      final now = DateTime.now().toIso8601String();
      await _recordSalePayment(
        txn,
        saleId: saleId,
        amount: cleanAmount,
        paymentMethod: paymentMethod,
        note: note?.trim().isEmpty == true ? null : note?.trim(),
        paymentDate: now,
        paymentType: 'customer_collection',
      );
      await txn.update(
        'sales',
        {'paid_amount': Money.round(paid + cleanAmount - refunded)},
        where: 'id = ?',
        whereArgs: [saleId],
      );
    });
  }

  Future<Sale?> getById(int id) async {
    final db = await _repo.db;
    final rows = await db.query('sales', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final saleRow = rows.first;
    final paidRows = await db.rawQuery('''
      SELECT COALESCE(SUM(CASE WHEN direction='in' AND entry_type IN ('sale_payment','customer_collection') THEN amount
                               WHEN direction='out' AND entry_type='sale_refund' THEN -amount ELSE 0 END),0) AS net_paid
      FROM payment_ledger WHERE reference_type='sale' AND reference_id = ?
    ''', [id]);
    final paid = (paidRows.first['net_paid'] as num?)?.toDouble() ??
        (saleRow['paid_amount'] as num?)?.toDouble() ?? 0;
    final sale = Sale.fromMap({...saleRow, 'paid_amount': paid});
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
    final db = await _repo.db;
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
    final rows = await db.query(
      'sales',
      where: where,
      whereArgs: args,
      orderBy: 'sale_date DESC, id DESC',
    );
    return Future.wait(rows.map((r) async {
      final sale = await getById(r['id'] as int);
      return sale!;
    }));
  }

  Future<List<Sale>> getReceivables() async {
    final db = await _repo.db;
    final rows = await db.rawQuery('''
      SELECT s.*,
        COALESCE((SELECT SUM(CASE WHEN pl.direction='in' AND pl.entry_type IN ('sale_payment','customer_collection') THEN pl.amount
                                  WHEN pl.direction='out' AND pl.entry_type='sale_refund' THEN -pl.amount ELSE 0 END)
                  FROM payment_ledger pl WHERE pl.reference_type='sale' AND pl.reference_id=s.id), 0) AS ledger_paid
      FROM sales s
      WHERE s.status = 'completed' AND s.payment_method = 'credit'
      ORDER BY s.due_date IS NULL ASC, s.due_date ASC, s.sale_date DESC
    ''');
    return rows
        .map((row) => Sale.fromMap({...row, 'paid_amount': row['ledger_paid']}))
        .where((sale) => sale.remainingAmount > 0)
        .toList();
  }

  Future<Map<String, double>> getTodayStats() async {
    final db = await _repo.db;
    final start = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day).toIso8601String();
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(total),0) AS sales,
             COALESCE(SUM(profit),0) AS profit,
             COUNT(*) AS count
      FROM sales
      WHERE sale_date >= ? AND status = 'completed'
    ''', [start]);
    return {
      'sales': Money.round((rows.first['sales'] as num).toDouble()),
      'profit': Money.round((rows.first['profit'] as num).toDouble()),
      'count': (rows.first['count'] as num).toDouble(),
    };
  }

  Future<List<Map<String, dynamic>>> getSalesChart({int days = 7}) async {
    final db = await _repo.db;
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
      result.add({
        'date': '${day.day}/${day.month}',
        'total': Money.round((rows.first['total'] as num).toDouble()),
      });
    }
    return result;
  }
}
