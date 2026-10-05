import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';

class SettingsService {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<String?> get(String key) async {
    final db = await _db.database;
    final result = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    if (result.isEmpty) return null;
    return result.first['value'] as String?;
  }

  Future<void> set(String key, String value) async {
    final db = await _db.database;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, String>> getAll() async {
    final db = await _db.database;
    final result = await db.query('settings');
    return {for (var r in result) r['key'] as String: r['value'] as String? ?? ''};
  }

  Future<double> getInitialCapital() async {
    final v = await get('initial_capital');
    return double.tryParse(v ?? '0') ?? 0;
  }

  Future<void> setInitialCapital(double value) async {
    if (value < 0) throw Exception('رأس المال لا يمكن أن يكون سالبًا');
    final db = await _db.database;
    final current = await getInitialCapital();
    if ((current - value).abs() < 0.001) return;

    final financialRows = await db.rawQuery('''
      SELECT
        (SELECT COUNT(*) FROM sales) +
        (SELECT COUNT(*) FROM purchases) +
        (SELECT COUNT(*) FROM expenses WHERE status = 'active') +
        (SELECT COUNT(*) FROM capital_transactions) AS total
    ''');
    final total = (financialRows.first['total'] as num?)?.toInt() ?? 0;
    if (total > 0) {
      throw Exception('رأس المال الأولي تم اعتماده. استخدم "حركة رأس المال" لأي إضافة أو سحب بعد بدء النشاط.');
    }
    await set('initial_capital', value.toString());
  }
}
