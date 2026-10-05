import '../database/database_helper.dart';
import '../models/product.dart';
import '../models/stock_movement.dart';

class ProductService {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<List<Product>> getAll({String? search, int? categoryId, bool lowStockOnly = false}) async {
    final db = await _db.database;
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
    final db = await _db.database;
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
    final db = await _db.database;
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
    if (product.sellPrice < 0 || product.costPrice < 0) throw Exception('الأسعار لا يمكن أن تكون سالبة');
    if (product.stock < 0) throw Exception('المخزون لا يمكن أن يكون سالبًا');
    final db = await _db.database;
    return db.transaction((txn) async {
      final data = product.toMap()..remove('id');
      final opening = product.stock;
      data['stock'] = 0;
      final id = await txn.insert('products', data);
      if (opening > 0) {
        final now = DateTime.now().toIso8601String();
        await txn.update('products', {'stock': opening, 'updated_at': now}, where: 'id = ?', whereArgs: [id]);
        await txn.insert('stock_movements', {
          'product_id': id,
          'type': 'opening',
          'quantity': opening,
          'previous_stock': 0,
          'new_stock': opening,
          'reference_type': 'product_opening',
          'reference_id': id,
          'notes': 'رصيد افتتاحي عند إنشاء المنتج',
          'created_at': now,
        });
      }
      return id;
    });
  }

  Future<int> update(Product product) async {
    if (product.id == null) throw Exception('معرّف المنتج غير موجود');
    if (product.name.trim().isEmpty) throw Exception('اسم المنتج مطلوب');
    final db = await _db.database;
    final data = product.toMap()..remove('id');
    data.remove('stock');
    return db.update('products', data, where: 'id = ?', whereArgs: [product.id]);
  }

  Future<int> delete(int id) async {
    final db = await _db.database;
    return db.update('products', {'is_active': 0, 'updated_at': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> setStock(int productId, int targetStock, {String? notes}) async {
    if (targetStock < 0) throw Exception('المخزون لا يمكن أن يكون سالبًا');
    final db = await _db.database;
    await db.transaction((txn) async {
      final rows = await txn.query('products', columns: ['stock'], where: 'id = ? AND is_active = 1', whereArgs: [productId]);
      if (rows.isEmpty) throw Exception('المنتج غير موجود');
      final previous = (rows.first['stock'] as num).toInt();
      if (previous == targetStock) return;
      final now = DateTime.now().toIso8601String();
      await txn.update(
        'products',
        {'stock': targetStock, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [productId],
      );
      await txn.insert('stock_movements', {
        'product_id': productId,
        'type': 'adjust',
        'quantity': (targetStock - previous).abs(),
        'previous_stock': previous,
        'new_stock': targetStock,
        'reference_type': 'manual_adjustment',
        'reference_id': null,
        'notes': notes ?? 'تسوية يدوية للمخزون',
        'created_at': now,
      });
    });
  }

  Future<void> adjustStock(int productId, int quantity, String type, {String? notes, String? refType, int? refId}) async {
    if (quantity <= 0) throw Exception('الكمية يجب أن تكون أكبر من صفر');
    final db = await _db.database;
    await db.transaction((txn) async {
      final rows = await txn.query('products', columns: ['stock'], where: 'id = ?', whereArgs: [productId]);
      if (rows.isEmpty) throw Exception('المنتج غير موجود');
      final previous = (rows.first['stock'] as num).toInt();
      final normalized = type.toLowerCase();
      final newStock = normalized == 'out' ? previous - quantity : normalized == 'adjust' ? quantity : previous + quantity;
      if (newStock < 0) throw Exception('المخزون غير كافٍ');
      final now = DateTime.now().toIso8601String();
      await txn.update('products', {'stock': newStock, 'updated_at': now}, where: 'id = ?', whereArgs: [productId]);
      await txn.insert('stock_movements', StockMovement(
        productId: productId,
        type: normalized,
        quantity: quantity,
        previousStock: previous,
        newStock: newStock,
        referenceType: refType,
        referenceId: refId,
        notes: notes,
        createdAt: now,
      ).toMap()..remove('id'));
    });
  }

  Future<double> getInventoryValue() async {
    final db = await _db.database;
    final rows = await db.rawQuery('SELECT COALESCE(SUM(stock * cost_price), 0) AS value FROM products WHERE is_active = 1');
    return (rows.first['value'] as num).toDouble();
  }

  Future<List<Product>> getLowStock() => getAll(lowStockOnly: true);

  Future<List<Map<String, dynamic>>> getTopSelling({int limit = 5, int days = 30}) async {
    final db = await _db.database;
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

  Future<List<StockMovement>> getMovements({int? productId, int limit = 200}) async {
    final db = await _db.database;
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
      ORDER BY sm.created_at DESC
      LIMIT ?
    ''', args);
    return rows.map(StockMovement.fromMap).toList();
  }
}
