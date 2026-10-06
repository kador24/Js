import 'dart:io';
import '../models/product.dart';
import '../models/stock_movement.dart';
import '../repositories/store_repository.dart';
import '../utils/money.dart';

class ProductService {
  ProductService({StoreRepository? repository})
      : _repo = repository ?? StoreRepository();

  final StoreRepository _repo;

  Future<List<Product>> getAll({
    String? search,
    int? categoryId,
    bool lowStockOnly = false,
  }) async {
    final db = await _repo.db;
    var where = 'p.is_active = 1';
    final args = <dynamic>[];
    if (search != null && search.trim().isNotEmpty) {
      where += ' AND (p.name LIKE ? OR p.barcode LIKE ? OR p.brand LIKE ?)';
      final q = '%${search.trim()}%';
      args.addAll([q, q, q]);
    }
    if (categoryId != null) {
      where += ' AND p.category_id = ?';
      args.add(categoryId);
    }
    if (lowStockOnly) where += ' AND p.stock <= p.min_stock';
    final rows = await db.rawQuery('''
      SELECT p.*, c.name_ar AS category_name
      FROM products p
      LEFT JOIN categories c ON p.category_id = c.id
      WHERE $where
      ORDER BY p.name COLLATE NOCASE ASC
    ''', args);
    return rows.map(Product.fromMap).toList();
  }

  Future<Product?> getById(int id) async {
    final db = await _repo.db;
    final rows = await db.rawQuery('''
      SELECT p.*, c.name_ar AS category_name
      FROM products p
      LEFT JOIN categories c ON p.category_id = c.id
      WHERE p.id = ?
    ''', [id]);
    return rows.isEmpty ? null : Product.fromMap(rows.first);
  }

  Future<Product?> getByBarcode(String barcode) async {
    final clean = barcode.trim();
    if (clean.isEmpty) return null;
    final db = await _repo.db;
    final rows = await db.rawQuery('''
      SELECT p.*, c.name_ar AS category_name
      FROM products p
      LEFT JOIN categories c ON p.category_id = c.id
      WHERE p.barcode = ? AND p.is_active = 1
    ''', [clean]);
    return rows.isEmpty ? null : Product.fromMap(rows.first);
  }

  Future<int> insert(Product product) async {
    if (product.name.trim().isEmpty) throw Exception('اسم المنتج مطلوب');
    if (product.sellPrice < 0 || product.costPrice < 0) {
      throw Exception('الأسعار لا يمكن أن تكون سالبة');
    }
    if (product.stock < 0) throw Exception('المخزون لا يمكن أن يكون سالبًا');

    return _repo.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      final data = product.toMap()
        ..remove('id')
        ..['sell_price'] = Money.round(product.sellPrice)
        ..['cost_price'] = Money.round(product.costPrice);
      final opening = product.stock;
      data['stock'] = 0;
      final id = await txn.insert('products', data);
      if (opening > 0) {
        await txn.update(
          'products',
          {'stock': opening, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [id],
        );
        await _insertStockMovement(
          txn,
          productId: id,
          type: 'opening',
          delta: opening,
          previousStock: 0,
          newStock: opening,
          referenceType: 'product_opening',
          referenceId: id,
          reasonCode: 'opening_balance',
          notes: 'رصيد افتتاحي عند إنشاء المنتج',
          createdAt: now,
        );
      }
      return id;
    });
  }

  Future<int> update(Product product) async {
    final id = product.id;
    if (id == null) throw Exception('معرّف المنتج غير موجود');
    if (product.name.trim().isEmpty) throw Exception('اسم المنتج مطلوب');
    if (product.sellPrice < 0 || product.costPrice < 0 || product.stock < 0) {
      throw Exception('قيم المنتج غير صحيحة');
    }

    String? oldImagePath;
    final result = await _repo.transaction((txn) async {
      final rows = await txn.query(
        'products',
        columns: ['id', 'image_path', 'stock'],
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty) throw Exception('المنتج غير موجود');
      oldImagePath = rows.first['image_path'] as String?;
      final data = product.toMap()
        ..remove('id')
        ..remove('stock')
        ..['sell_price'] = Money.round(product.sellPrice)
        ..['cost_price'] = Money.round(product.costPrice);
      return txn.update('products', data, where: 'id = ?', whereArgs: [id]);
    });

    final newImagePath = product.imagePath;
    if (oldImagePath != null && oldImagePath != newImagePath) {
      await _deleteFileSafely(oldImagePath!);
    }
    return result;
  }

  Future<int> delete(int id) async {
    final product = await getById(id);
    if (product == null) throw Exception('المنتج غير موجود');
    final db = await _repo.db;
    final result = await db.update(
      'products',
      {'is_active': 0, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (result > 0 && product.imagePath != null) {
      await _deleteFileSafely(product.imagePath!);
    }
    return result;
  }

  Future<void> setStock(
    int productId,
    int targetStock, {
    String? notes,
  }) async {
    if (targetStock < 0) throw Exception('المخزون لا يمكن أن يكون سالبًا');
    final delta = await _changeStock(
      productId,
      targetStock: targetStock,
      type: 'adjust',
      reasonCode: 'manual_adjustment',
      notes: notes ?? 'تسوية يدوية للمخزون',
    );
    if (delta == null) throw Exception('المنتج غير موجود');
  }

  Future<void> adjustStock(
    int productId,
    int quantity,
    String type, {
    String? notes,
    String? refType,
    int? refId,
  }) async {
    final normalized = type.toLowerCase();
    final allowed = {'in', 'out', 'return', 'adjust', 'opening'};
    if (!allowed.contains(normalized)) throw Exception('نوع حركة المخزون غير صحيح');
    if (quantity == 0 || (normalized != 'adjust' && quantity < 0)) {
      throw Exception('الكمية غير صحيحة');
    }
    await _changeStock(
      productId,
      delta: normalized == 'out' ? -quantity.abs() :
          normalized == 'adjust' ? quantity : quantity.abs(),
      type: normalized,
      referenceType: refType,
      referenceId: refId,
      reasonCode: 'manual_adjustment',
      notes: notes,
    );
  }

  Future<int?> _changeStock(
    int productId, {
    int? targetStock,
    int? delta,
    required String type,
    String? referenceType,
    int? referenceId,
    String? reasonCode,
    String? notes,
  }) async {
    return _repo.transaction((txn) async {
      final rows = await txn.query(
        'products',
        columns: ['stock'],
        where: 'id = ? AND is_active = 1',
        whereArgs: [productId],
      );
      if (rows.isEmpty) return null;
      final previous = (rows.first['stock'] as num).toInt();
      final computedDelta = targetStock == null ? delta! : targetStock - previous;
      if (computedDelta == 0) return previous;
      final next = targetStock ?? (previous + computedDelta);
      if (next < 0) throw Exception('المخزون غير كافٍ');
      final now = DateTime.now().toIso8601String();
      await txn.update(
        'products',
        {'stock': next, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [productId],
      );
      await _insertStockMovement(
        txn,
        productId: productId,
        type: type,
        delta: computedDelta,
        previousStock: previous,
        newStock: next,
        referenceType: referenceType,
        referenceId: referenceId,
        reasonCode: reasonCode,
        notes: notes,
        createdAt: now,
      );
      return next;
    });
  }

  Future<void> applyTransactionalStockChange(
    dynamic txn, {
    required int productId,
    required int delta,
    required String type,
    String? referenceType,
    int? referenceId,
    String? reasonCode,
    String? notes,
    String? createdAt,
  }) async {
    if (delta == 0) throw Exception('تغيير المخزون لا يمكن أن يكون صفرًا');
    final rows = await txn.query(
      'products',
      columns: ['stock'],
      where: 'id = ? AND is_active = 1',
      whereArgs: [productId],
    );
    if (rows.isEmpty) throw Exception('المنتج غير موجود');
    final previous = (rows.first['stock'] as num).toInt();
    final next = previous + delta;
    if (next < 0) throw Exception('المخزون غير كافٍ');
    final now = createdAt ?? DateTime.now().toIso8601String();
    await txn.update(
      'products',
      {'stock': next, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [productId],
    );
    await _insertStockMovement(
      txn,
      productId: productId,
      type: type,
      delta: delta,
      previousStock: previous,
      newStock: next,
      referenceType: referenceType,
      referenceId: referenceId,
      reasonCode: reasonCode,
      notes: notes,
      createdAt: now,
    );
  }

  Future<void> _insertStockMovement(
    dynamic txn, {
    required int productId,
    required String type,
    required int delta,
    required int previousStock,
    required int newStock,
    String? referenceType,
    int? referenceId,
    String? reasonCode,
    String? notes,
    required String createdAt,
  }) async {
    if (previousStock + delta != newStock) {
      throw Exception('حركة المخزون غير متسقة');
    }
    if (newStock < 0) throw Exception('المخزون لا يمكن أن يكون سالبًا');
    await txn.insert('stock_movements', {
      'product_id': productId,
      'type': type,
      'quantity': delta.abs(),
      'previous_stock': previousStock,
      'new_stock': newStock,
      'reference_type': referenceType,
      'reference_id': referenceId,
      'notes': notes,
      'created_at': createdAt,
      'delta_quantity': delta,
      'reason_code': reasonCode,
    });
  }

  Future<bool> auditStockIntegrity({int? productId}) async {
    final db = await _repo.db;
    final products = await db.query(
      'products',
      columns: ['id', 'stock'],
      where: productId == null ? null : 'id = ?',
      whereArgs: productId == null ? null : [productId],
    );
    for (final product in products) {
      final id = product['id'] as int;
      final rows = await db.query(
        'stock_movements',
        where: 'product_id = ?',
        whereArgs: [id],
        orderBy: 'id ASC',
      );
      var expected = rows.isEmpty ? 0 : (rows.first['previous_stock'] as num).toInt();
      for (final row in rows) {
        final previous = (row['previous_stock'] as num).toInt();
        final next = (row['new_stock'] as num).toInt();
        final delta = (row['delta_quantity'] as num?)?.toInt() ??
            (next - previous);
        if (previous != expected || previous + delta != next || next < 0) {
          return false;
        }
        expected = next;
      }
      if (expected != (product['stock'] as num).toInt()) return false;
    }
    return true;
  }

  Future<double> getInventoryValue() async {
    final db = await _repo.db;
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(stock * cost_price), 0) AS value FROM products WHERE is_active = 1',
    );
    return Money.round((rows.first['value'] as num).toDouble());
  }

  Future<List<Product>> getLowStock() => getAll(lowStockOnly: true);

  Future<List<Map<String, dynamic>>> getTopSelling({
    int limit = 5,
    int days = 30,
  }) async {
    final db = await _repo.db;
    final since = DateTime.now().subtract(Duration(days: days)).toIso8601String();
    return db.rawQuery('''
      SELECT si.product_id, si.product_name,
             SUM(si.quantity) AS total_qty,
             SUM(si.total_price) AS total_sales
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      WHERE s.sale_date >= ? AND s.status = 'completed'
      GROUP BY si.product_id, si.product_name
      ORDER BY total_qty DESC
      LIMIT ?
    ''', [since, limit]);
  }

  Future<List<StockMovement>> getMovements({
    int? productId,
    int limit = 200,
  }) async {
    final db = await _repo.db;
    final args = <dynamic>[];
    var where = '1=1';
    if (productId != null) {
      where += ' AND sm.product_id = ?';
      args.add(productId);
    }
    args.add(limit);
    final rows = await db.rawQuery('''
      SELECT sm.*, p.name AS product_name
      FROM stock_movements sm
      JOIN products p ON p.id = sm.product_id
      WHERE $where
      ORDER BY sm.created_at DESC, sm.id DESC
      LIMIT ?
    ''', args);
    return rows.map(StockMovement.fromMap).toList();
  }

  Future<void> _deleteFileSafely(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Database state remains authoritative; file cleanup is best-effort.
    }
  }
}
