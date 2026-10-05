import '../database/database_helper.dart';
import '../models/expense.dart';

class ExpenseService {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<int> insert(Expense expense) async {
    final db = await _db.database;
    return await db.insert('expenses', expense.toMap()..remove('id'));
  }

  Future<List<Expense>> getAll({DateTime? from, DateTime? to}) async {
    final db = await _db.database;
    String where = "status = 'active'";
    List<dynamic> args = [];
    if (from != null) {
      where += ' AND expense_date >= ?';
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where += ' AND expense_date <= ?';
      args.add(to.toIso8601String());
    }
    final result = await db.query('expenses', where: where, whereArgs: args, orderBy: 'expense_date DESC');
    return result.map((e) => Expense.fromMap(e)).toList();
  }

  Future<double> getTotal({DateTime? from, DateTime? to}) async {
    final db = await _db.database;
    String where = "status = 'active'";
    List<dynamic> args = [];
    if (from != null) {
      where += ' AND expense_date >= ?';
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where += ' AND expense_date <= ?';
      args.add(to.toIso8601String());
    }
    final result = await db.rawQuery('SELECT COALESCE(SUM(amount), 0) as total FROM expenses WHERE $where', args);
    return (result.first['total'] as num).toDouble();
  }

  Future<int> delete(int id) async {
    final db = await _db.database;
    return await db.update('expenses', {'status': 'voided'}, where: 'id = ?', whereArgs: [id]);
  }
}
