import 'package:sqflite/sqflite.dart';
import '../repositories/store_repository.dart';
import '../utils/money.dart';

class SettingsService {
  SettingsService({StoreRepository? repository})
      : _repo = repository ?? StoreRepository();

  final StoreRepository _repo;

  Future<String?> get(String key) async {
    final db = await _repo.db;
    final result = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    if (result.isEmpty) return null;
    return result.first['value'] as String?;
  }

  Future<void> set(String key, String value) async {
    final db = await _repo.db;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, String>> getAll() async {
    final db = await _repo.db;
    final result = await db.query('settings');
    return {
      for (final row in result)
        row['key'] as String: row['value'] as String? ?? '',
    };
  }

  Future<double> getInitialCapital() async {
    final value = await get('initial_capital');
    return Money.round(double.tryParse(value ?? '0') ?? 0);
  }

  Future<void> setInitialCapital(double value) async {
    final clean = Money.round(value);
    if (clean < 0) throw Exception('رأس المال لا يمكن أن يكون سالبًا');
    final db = await _repo.db;
    await db.transaction((txn) async {
      final currentRows = await txn.query(
        'settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['initial_capital'],
        limit: 1,
      );
      final current = currentRows.isEmpty
          ? 0
          : Money.round(double.tryParse(currentRows.first['value'] as String? ?? '0') ?? 0);
      if (Money.same(current, clean)) return;

      final activity = await txn.rawQuery('''
        SELECT
          (SELECT COUNT(*) FROM sales) +
          (SELECT COUNT(*) FROM purchases) +
          (SELECT COUNT(*) FROM expenses WHERE status = 'active') +
          (SELECT COUNT(*) FROM capital_transactions) AS total
      ''');
      final total = (activity.first['total'] as num?)?.toInt() ?? 0;
      if (total > 0) {
        throw Exception('رأس المال الأولي تم اعتماده. استخدم حركة رأس المال لأي إضافة أو سحب بعد بدء النشاط.');
      }

      await txn.insert(
        'settings',
        {'key': 'initial_capital', 'value': clean.toStringAsFixed(2)},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      final existingLedger = await txn.query(
        'payment_ledger',
        columns: ['id', 'amount'],
        where: "source_table = 'settings_initial_capital' AND source_id = 1",
        limit: 1,
      );
      final now = DateTime.now().toIso8601String();
      if (existingLedger.isEmpty) {
        if (clean > 0) {
          await txn.insert('payment_ledger', {
            'direction': 'in',
            'entry_type': 'initial_capital',
            'amount': clean,
            'payment_method': 'cash',
            'source_table': 'settings_initial_capital',
            'source_id': 1,
            'reference_type': 'settings',
            'reference_id': null,
            'note': 'رأس المال الأولي',
            'transaction_date': now,
            'created_at': now,
          });
        }
      } else {
        final oldAmount = Money.round(
          (existingLedger.first['amount'] as num?)?.toDouble() ?? current,
        );
        final delta = Money.round(clean - oldAmount);
        if (delta != 0) {
          final maxRows = await txn.rawQuery(
            "SELECT COALESCE(MAX(source_id), 0) AS max_id FROM payment_ledger WHERE source_table = 'settings_initial_capital_adjustment'",
          );
          final nextId = ((maxRows.first['max_id'] as num?)?.toInt() ?? 0) + 1;
          await txn.insert('payment_ledger', {
            'direction': delta > 0 ? 'in' : 'out',
            'entry_type': 'initial_capital_adjustment',
            'amount': delta.abs(),
            'payment_method': 'cash',
            'source_table': 'settings_initial_capital_adjustment',
            'source_id': nextId,
            'reference_type': 'settings',
            'reference_id': null,
            'note': 'تصحيح رأس المال الأولي',
            'transaction_date': now,
            'created_at': now,
          });
        }
      }
    });
  }
}
