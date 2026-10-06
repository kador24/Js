import '../models/purchase.dart';
import '../repositories/store_repository.dart';
import '../utils/money.dart';

class PurchaseService {
  PurchaseService({StoreRepository? repository})
      : _repo = repository ?? StoreRepository();

  final StoreRepository _repo;

  String _normalizePayment(String value) {
    const allowed = {'cash', 'transfer', 'credit'};
    if (!allowed.contains(value)) throw Exception('طريقة دفع المورد غير صحيحة');
    return value;
  }

  Future<int> createPurchase({
    int? supplierId,
    String? invoiceNumber,
    String? notes,
    String paymentMethod = 'cash',
    String initialPaymentMethod = 'cash',
    double? paidAmount,
    String? dueDate,
    required List<Map<String, dynamic>> items,
  }) async {
    if (items.isEmpty) throw Exception('أضف منتجًا واحدًا على الأقل');
    final method = _normalizePayment(paymentMethod);

    return _repo.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      var total = 0.0;
      final normalized = <Map<String, dynamic>>[];

      for (final item in items) {
        final productId = item['productId'] as int?;
        final qty = (item['quantity'] as num?)?.toInt() ?? 0;
        final unitCost = Money.round(
          (item['unitCost'] as num?)?.toDouble() ?? -1,
        );
        if (productId == null || qty <= 0 || unitCost < 0) {
          throw Exception('بيانات الشراء غير صحيحة');
        }
        final rows = await txn.query(
          'products',
          columns: ['id'],
          where: 'id = ? AND is_active = 1',
          whereArgs: [productId],
        );
        if (rows.isEmpty) throw Exception('المنتج غير موجود');
        total = Money.add(total, Money.multiply(unitCost, qty));
        normalized.add({
          'productId': productId,
          'quantity': qty,
          'unitCost': unitCost,
        });
      }

      final paid = method == 'credit'
          ? Money.round(paidAmount ?? 0)
          : total;
      if (method == 'credit' && paid > 0 && !{'cash', 'transfer'}.contains(initialPaymentMethod)) {
        throw Exception('طريقة الدفعة الأولى للمورد غير صحيحة');
      }
      if (paid < 0 || paid > total + 0.005) {
        throw Exception('المبلغ المدفوع غير صحيح');
      }
      if (paid > 0 && method == 'credit' && supplierId == null) {
        // A payment without a supplier is still valid for legacy/unassigned purchases.
      }
      final remaining = Money.subtract(total, paid);
      if (remaining > 0 && (dueDate == null || dueDate.isEmpty)) {
        throw Exception('حدد تاريخ الاستحقاق للمشتريات الآجلة');
      }

      final purchaseId = await txn.insert('purchases', {
        'supplier_id': supplierId,
        'invoice_number': invoiceNumber?.trim().isEmpty == true
            ? null
            : invoiceNumber?.trim(),
        'total_amount': total,
        'payment_method': method,
        'paid_amount': paid,
        'due_date': remaining > 0 ? dueDate : null,
        'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
        'purchase_date': now,
        'created_at': now,
      });

      for (final item in normalized) {
        final productId = item['productId'] as int;
        final qty = item['quantity'] as int;
        final unitCost = item['unitCost'] as double;
        final rows = await txn.query(
          'products',
          columns: ['stock', 'cost_price'],
          where: 'id = ? AND is_active = 1',
          whereArgs: [productId],
        );
        if (rows.isEmpty) throw Exception('المنتج غير موجود');
        final product = rows.first;
        final previous = (product['stock'] as num).toInt();
        final oldCost = (product['cost_price'] as num).toDouble();
        final newStock = previous + qty;
        final weightedCost = Money.weightedAverage(
          oldQuantity: previous,
          oldUnitCost: oldCost,
          incomingQuantity: qty,
          incomingUnitCost: unitCost,
        );

        await txn.insert('purchase_items', {
          'purchase_id': purchaseId,
          'product_id': productId,
          'quantity': qty,
          'unit_cost': unitCost,
          'total_cost': Money.multiply(unitCost, qty),
        });
        await txn.update(
          'products',
          {'stock': newStock, 'cost_price': weightedCost, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [productId],
        );
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
          'delta_quantity': qty,
          'reason_code': 'purchase_receipt',
        });
      }

      if (paid > 0) {
        final paymentId = await txn.insert('supplier_payments', {
          'supplier_id': supplierId,
          'purchase_id': purchaseId,
          'amount': paid,
          'payment_method': method == 'credit' ? initialPaymentMethod : method,
          'payment_date': now,
          'note': 'دفعة عند إنشاء الشراء',
          'created_at': now,
        });
        await _insertPaymentLedger(
          txn,
          direction: 'out',
          entryType: 'supplier_payment',
          amount: paid,
          paymentMethod: method == 'credit' ? initialPaymentMethod : method,
          sourceTable: 'supplier_payments',
          sourceId: paymentId,
          referenceType: 'purchase',
          referenceId: purchaseId,
          note: 'دفعة عند إنشاء الشراء',
          transactionDate: now,
          createdAt: now,
        );
      }

      return purchaseId;
    });
  }

  Future<void> recordSupplierPayment(
    int purchaseId,
    double amount, {
    String paymentMethod = 'cash',
    String? note,
  }) async {
    final cleanAmount = Money.round(amount);
    if (cleanAmount <= 0) throw Exception('المبلغ يجب أن يكون أكبر من صفر');
    const allowed = {'cash', 'transfer'};
    if (!allowed.contains(paymentMethod)) {
      throw Exception('طريقة دفع المورد غير صحيحة');
    }

    await _repo.transaction((txn) async {
      final rows = await txn.query(
        'purchases',
        where: 'id = ?',
        whereArgs: [purchaseId],
      );
      if (rows.isEmpty) throw Exception('فاتورة الشراء غير موجودة');
      final purchase = rows.first;
      final total = (purchase['total_amount'] as num?)?.toDouble() ?? 0;
      final paidRows = await txn.rawQuery('''
        SELECT COALESCE(SUM(amount),0) AS paid
        FROM payment_ledger
        WHERE reference_type='purchase' AND reference_id=?
          AND entry_type='supplier_payment' AND direction='out'
      ''', [purchaseId]);
      final paid = (paidRows.first['paid'] as num?)?.toDouble() ?? 0;
      final remaining = Money.subtract(total, paid);
      if (cleanAmount > remaining + 0.005) {
        throw Exception('المبلغ أكبر من المتبقي للمورد');
      }

      final now = DateTime.now().toIso8601String();
      final paymentId = await txn.insert('supplier_payments', {
        'supplier_id': purchase['supplier_id'],
        'purchase_id': purchaseId,
        'amount': cleanAmount,
        'payment_method': paymentMethod,
        'payment_date': now,
        'note': note?.trim().isEmpty == true ? null : note?.trim(),
        'created_at': now,
      });
      await _insertPaymentLedger(
        txn,
        direction: 'out',
        entryType: 'supplier_payment',
        amount: cleanAmount,
        paymentMethod: paymentMethod,
        sourceTable: 'supplier_payments',
        sourceId: paymentId,
        referenceType: 'purchase',
        referenceId: purchaseId,
        note: note,
        transactionDate: now,
        createdAt: now,
      );
      await _syncPurchasePaidAmount(txn, purchaseId, total);
    });
  }

  Future<void> _syncPurchasePaidAmount(dynamic txn, int purchaseId, double total) async {
    final rows = await txn.rawQuery(
      "SELECT COALESCE(SUM(amount),0) AS paid FROM supplier_payments WHERE purchase_id = ?",
      [purchaseId],
    );
    final paid = Money.round((rows.first['paid'] as num?)?.toDouble() ?? 0);
    await txn.update(
      'purchases',
      {'paid_amount': paid.clamp(0, total).toDouble()},
      where: 'id = ?',
      whereArgs: [purchaseId],
    );
  }

  Future<void> _insertPaymentLedger(
    dynamic txn, {
    required String direction,
    required String entryType,
    required double amount,
    required String paymentMethod,
    required String sourceTable,
    required int sourceId,
    String? referenceType,
    int? referenceId,
    String? note,
    required String transactionDate,
    required String createdAt,
  }) async {
    await txn.insert('payment_ledger', {
      'direction': direction,
      'entry_type': entryType,
      'amount': Money.round(amount),
      'payment_method': paymentMethod,
      'source_table': sourceTable,
      'source_id': sourceId,
      'reference_type': referenceType,
      'reference_id': referenceId,
      'note': note,
      'transaction_date': transactionDate,
      'created_at': createdAt,
    });
  }

  Future<List<Purchase>> getAll({DateTime? from, DateTime? to}) async {
    final db = await _repo.db;
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
      SELECT p.*, s.name AS supplier_name,
             COALESCE((SELECT SUM(pl.amount) FROM payment_ledger pl WHERE pl.reference_type='purchase' AND pl.reference_id=p.id AND pl.entry_type='supplier_payment' AND pl.direction='out'), 0) AS ledger_paid
      FROM purchases p
      LEFT JOIN suppliers s ON s.id = p.supplier_id
      WHERE $where
      ORDER BY p.purchase_date DESC, p.id DESC
    ''', args);
    return rows
        .map((row) => Purchase.fromMap({
              ...row,
              'paid_amount': row['ledger_paid'] ?? row['paid_amount'],
            }))
        .toList();
  }

  Future<Purchase?> getById(int id) async {
    final db = await _repo.db;
    final rows = await db.rawQuery('''
      SELECT p.*, s.name AS supplier_name,
             COALESCE((SELECT SUM(pl.amount) FROM payment_ledger pl WHERE pl.reference_type='purchase' AND pl.reference_id=p.id AND pl.entry_type='supplier_payment' AND pl.direction='out'), 0) AS ledger_paid
      FROM purchases p
      LEFT JOIN suppliers s ON s.id = p.supplier_id
      WHERE p.id = ?
    ''', [id]);
    if (rows.isEmpty) return null;
    final purchase = Purchase.fromMap({
      ...rows.first,
      'paid_amount': rows.first['ledger_paid'] ?? rows.first['paid_amount'],
    });
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

  Future<List<Map<String, dynamic>>> getSupplierPayments({int? supplierId}) async {
    final db = await _repo.db;
    final args = <dynamic>[];
    var where = '1=1';
    if (supplierId != null) {
      where += ' AND sp.supplier_id = ?';
      args.add(supplierId);
    }
    return db.rawQuery('''
      SELECT sp.*, s.name AS supplier_name, p.invoice_number
      FROM supplier_payments sp
      LEFT JOIN suppliers s ON s.id = sp.supplier_id
      LEFT JOIN purchases p ON p.id = sp.purchase_id
      WHERE $where
      ORDER BY sp.payment_date DESC, sp.id DESC
    ''', args);
  }

  Future<Map<String, double>> getPayables({DateTime? to}) async {
    final db = await _repo.db;
    var dateWhere = '';
    final args = <dynamic>[];
    if (to != null) {
      dateWhere = ' WHERE p.purchase_date <= ?';
      args.add(to.toIso8601String());
    }
    final totalRows = await db.rawQuery('''
      SELECT COALESCE(SUM(p.total_amount),0) AS total
      FROM purchases p$dateWhere
    ''', args);
    final paidArgs = <dynamic>[];
    var paidWhere = "direction='out' AND entry_type='supplier_payment'";
    if (to != null) {
      paidWhere += ' AND transaction_date <= ?';
      paidArgs.add(to.toIso8601String());
    }
    final paidRows = await db.rawQuery('''
      SELECT COALESCE(SUM(amount),0) AS paid
      FROM payment_ledger
      WHERE $paidWhere
    ''', paidArgs);
    final total = (totalRows.first['total'] as num?)?.toDouble() ?? 0;
    final paid = (paidRows.first['paid'] as num?)?.toDouble() ?? 0;
    return {
      'total': Money.round(total),
      'paid': Money.round(paid),
      'payable': Money.round(total - paid),
    };
  }
}
