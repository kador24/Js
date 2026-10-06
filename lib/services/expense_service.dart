import '../models/expense.dart';
import '../repositories/store_repository.dart';
import '../utils/money.dart';

class ExpenseService {
  ExpenseService({StoreRepository? repository})
      : _repo = repository ?? StoreRepository();

  final StoreRepository _repo;

  Future<int> insert(Expense expense) async {
    final amount = Money.round(expense.amount);
    if (amount <= 0) throw Exception('قيمة المصروف يجب أن تكون أكبر من صفر');
    return _repo.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      final id = await txn.insert('expenses', {
        ...expense.toMap()..remove('id'),
        'amount': amount,
      });
      await txn.insert('payment_ledger', {
        'direction': 'out',
        'entry_type': 'expense',
        'amount': amount,
        'payment_method': 'cash',
        'source_table': 'expenses',
        'source_id': id,
        'reference_type': 'expense',
        'reference_id': id,
        'note': expense.notes,
        'transaction_date': expense.expenseDate,
        'created_at': now,
      });
      return id;
    });
  }

  Future<List<Expense>> getAll({DateTime? from, DateTime? to}) async {
    final db = await _repo.db;
    var where = "status = 'active'";
    final args = <dynamic>[];
    if (from != null) {
      where += ' AND expense_date >= ?';
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where += ' AND expense_date <= ?';
      args.add(to.toIso8601String());
    }
    final result = await db.query('expenses', where: where, whereArgs: args, orderBy: 'expense_date DESC, id DESC');
    return result.map(Expense.fromMap).toList();
  }

  Future<double> getTotal({DateTime? from, DateTime? to}) async {
    final db = await _repo.db;
    var where = "status = 'active'";
    final args = <dynamic>[];
    if (from != null) {
      where += ' AND expense_date >= ?';
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where += ' AND expense_date <= ?';
      args.add(to.toIso8601String());
    }
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) as total FROM expenses WHERE $where',
      args,
    );
    return Money.round((result.first['total'] as num).toDouble());
  }

  Future<int> delete(int id) async {
    return _repo.transaction((txn) async {
      final rows = await txn.query(
        'expenses',
        columns: ['amount', 'status', 'expense_date', 'notes'],
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty) throw Exception('المصروف غير موجود');
      if (rows.first['status'] == 'voided') return 0;
      final amount = Money.round((rows.first['amount'] as num).toDouble());
      final now = DateTime.now().toIso8601String();
      await txn.update('expenses', {'status': 'voided'}, where: 'id = ?', whereArgs: [id]);
      final reverseId = await txn.rawInsert(
        "INSERT INTO payment_ledger(direction,entry_type,amount,payment_method,source_table,source_id,reference_type,reference_id,note,transaction_date,created_at) VALUES(?,?,?,?,?,?,?,?,?,?,?)",
        ['in', 'expense_void', amount, 'cash', 'expense_void', id, 'expense', id, 'إلغاء مصروف', now, now],
      );
      return reverseId;
    });
  }
}
