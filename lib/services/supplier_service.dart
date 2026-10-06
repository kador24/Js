import '../models/supplier.dart';
import '../repositories/store_repository.dart';
import '../utils/money.dart';

class SupplierService {
  SupplierService({StoreRepository? repository})
      : _repo = repository ?? StoreRepository();

  final StoreRepository _repo;

  Future<List<Supplier>> getAll() async {
    final rows = await _repo.db.then(
      (db) => db.query('suppliers', orderBy: 'name COLLATE NOCASE ASC'),
    );
    return rows.map(Supplier.fromMap).toList();
  }

  Future<int> create({required String name, String? phone, String? notes}) async {
    final clean = name.trim();
    if (clean.isEmpty) throw Exception('اسم المورد مطلوب');
    return _repo.db.then((db) => db.insert('suppliers', {
          'name': clean,
          'phone': phone?.trim().isEmpty == true ? null : phone?.trim(),
          'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
          'created_at': DateTime.now().toIso8601String(),
        }));
  }

  Future<double> getPayable(int supplierId) async {
    final db = await _repo.db;
    final totalRows = await db.rawQuery('''
      SELECT COALESCE(SUM(total_amount), 0) AS total
      FROM purchases
      WHERE supplier_id = ?
    ''', [supplierId]);
    final paidRows = await db.rawQuery('''
      SELECT COALESCE(SUM(pl.amount), 0) AS paid
      FROM payment_ledger pl
      JOIN supplier_payments sp ON sp.id = pl.source_id
      WHERE sp.supplier_id = ?
        AND pl.source_table='supplier_payments'
        AND pl.entry_type='supplier_payment'
        AND pl.direction='out'
    ''', [supplierId]);
    final total = (totalRows.first['total'] as num?)?.toDouble() ?? 0;
    final paid = (paidRows.first['paid'] as num?)?.toDouble() ?? 0;
    return Money.round((total - paid).clamp(0, double.infinity).toDouble());
  }
}
