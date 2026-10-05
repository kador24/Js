import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import 'product_service.dart';

class FinancialService {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final ProductService _products = ProductService();

  Future<double> _initialCapital(Database db) async {
    final rows = await db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['initial_capital'],
    );
    return rows.isEmpty
        ? 0
        : double.tryParse(rows.first['value'] as String? ?? '') ?? 0;
  }

  Future<Map<String, double>> _sumPaymentLedger(
    Database db, {
    DateTime? from,
    DateTime? to,
  }) async {
    var where = '1=1';
    final args = <dynamic>[];
    if (from != null) {
      where += ' AND payment_date >= ?';
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where += ' AND payment_date <= ?';
      args.add(to.toIso8601String());
    }

    final rows = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN payment_type = 'collection' THEN amount ELSE 0 END), 0) AS collections,
        COALESCE(SUM(CASE WHEN payment_type = 'refund' THEN amount ELSE 0 END), 0) AS refunds
      FROM receivable_payments
      WHERE $where
    ''', args);
    return {
      'collections': (rows.first['collections'] as num?)?.toDouble() ?? 0,
      'refunds': (rows.first['refunds'] as num?)?.toDouble() ?? 0,
    };
  }

  Future<Map<String, double>> getSummary({DateTime? from, DateTime? to}) async {
    final db = await _db.database;

    var salesWhere = "s.status = 'completed'";
    var expenseWhere = "status = 'active'";
    var purchaseWhere = '1=1';
    var capitalWhere = '1=1';
    final salesArgs = <dynamic>[];
    final expenseArgs = <dynamic>[];
    final purchaseArgs = <dynamic>[];
    final capitalArgs = <dynamic>[];

    if (from != null) {
      salesWhere += ' AND s.sale_date >= ?';
      expenseWhere += ' AND expense_date >= ?';
      purchaseWhere += ' AND purchase_date >= ?';
      capitalWhere += ' AND transaction_date >= ?';
      salesArgs.add(from.toIso8601String());
      expenseArgs.add(from.toIso8601String());
      purchaseArgs.add(from.toIso8601String());
      capitalArgs.add(from.toIso8601String());
    }
    if (to != null) {
      salesWhere += ' AND s.sale_date <= ?';
      expenseWhere += ' AND expense_date <= ?';
      purchaseWhere += ' AND purchase_date <= ?';
      capitalWhere += ' AND transaction_date <= ?';
      salesArgs.add(to.toIso8601String());
      expenseArgs.add(to.toIso8601String());
      purchaseArgs.add(to.toIso8601String());
      capitalArgs.add(to.toIso8601String());
    }

    final sale = await db.rawQuery('''
      SELECT
        COALESCE(SUM(total), 0) AS sales,
        COALESCE(SUM(profit), 0) AS gross_profit,
        COUNT(*) AS invoices
      FROM sales s
      WHERE $salesWhere
    ''', salesArgs);

    final expenses = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) AS total FROM expenses WHERE $expenseWhere',
      expenseArgs,
    );

    final purchases = await db.rawQuery('''
      SELECT
        COALESCE(SUM(total_amount), 0) AS total,
        COALESCE(SUM(paid_amount), 0) AS paid
      FROM purchases
      WHERE $purchaseWhere
    ''', purchaseArgs);

    final capital = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN type = 'contribution' THEN amount ELSE 0 END), 0) AS in_amount,
        COALESCE(SUM(CASE WHEN type = 'withdrawal' THEN amount ELSE 0 END), 0) AS out_amount
      FROM capital_transactions
      WHERE $capitalWhere
    ''', capitalArgs);

    final receivables = await db.rawQuery('''
      SELECT COALESCE(SUM(total - paid_amount), 0) AS total
      FROM sales
      WHERE status = 'completed'
        AND payment_method = 'credit'
        AND total > paid_amount
    ''');

    final periodPayments = await _sumPaymentLedger(db, from: from, to: to);
    final allPayments = await _sumPaymentLedger(db);

    final initialCapital = await _initialCapital(db);
    final inventoryValue = await _products.getInventoryValue();

    final salesTotal = (sale.first['sales'] as num?)?.toDouble() ?? 0;
    final grossProfit = (sale.first['gross_profit'] as num?)?.toDouble() ?? 0;
    final expenseTotal = (expenses.first['total'] as num?)?.toDouble() ?? 0;
    final purchasePaid = (purchases.first['paid'] as num?)?.toDouble() ?? 0;
    final capitalIn = (capital.first['in_amount'] as num?)?.toDouble() ?? 0;
    final capitalOut = (capital.first['out_amount'] as num?)?.toDouble() ?? 0;
    final receivableTotal = (receivables.first['total'] as num?)?.toDouble() ?? 0;
    final collections = periodPayments['collections'] ?? 0;
    final refunds = periodPayments['refunds'] ?? 0;
    final netCollected = collections - refunds;
    final netProfit = grossProfit - expenseTotal;

    final allSales = await db.rawQuery('''
      SELECT COALESCE(SUM(profit), 0) AS gross_profit
      FROM sales
      WHERE status = 'completed'
    ''');
    final allExpenses = await db.rawQuery(
      "SELECT COALESCE(SUM(amount), 0) AS total FROM expenses WHERE status = 'active'",
    );
    final allPurchases = await db.rawQuery(
      'SELECT COALESCE(SUM(paid_amount), 0) AS paid FROM purchases',
    );
    final allCapital = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN type = 'contribution' THEN amount ELSE 0 END), 0) AS in_amount,
        COALESCE(SUM(CASE WHEN type = 'withdrawal' THEN amount ELSE 0 END), 0) AS out_amount
      FROM capital_transactions
    ''');

    final currentGrossProfit =
        (allSales.first['gross_profit'] as num?)?.toDouble() ?? 0;
    final currentExpenses =
        (allExpenses.first['total'] as num?)?.toDouble() ?? 0;
    final currentPurchasePaid =
        (allPurchases.first['paid'] as num?)?.toDouble() ?? 0;
    final currentCapitalIn =
        (allCapital.first['in_amount'] as num?)?.toDouble() ?? 0;
    final currentCapitalOut =
        (allCapital.first['out_amount'] as num?)?.toDouble() ?? 0;
    final currentCash = initialCapital +
        currentCapitalIn -
        currentCapitalOut +
        (allPayments['collections'] ?? 0) -
        (allPayments['refunds'] ?? 0) -
        currentPurchasePaid -
        currentExpenses;
    final currentCapital = initialCapital +
        currentCapitalIn -
        currentCapitalOut +
        currentGrossProfit -
        currentExpenses;

    return {
      'initialCapital': initialCapital,
      'sales': salesTotal,
      'grossProfit': grossProfit,
      'expenses': expenseTotal,
      'netProfit': netProfit,
      'purchasePaid': purchasePaid,
      'capitalIn': capitalIn,
      'capitalOut': capitalOut,
      'cashBalance': currentCash,
      'currentCapital': currentCapital,
      'receivables': receivableTotal,
      'inventoryValue': inventoryValue,
      'collected': collections,
      'refunds': refunds,
      'netCollected': netCollected,
      'invoices': (sale.first['invoices'] as num?)?.toDouble() ?? 0,
      'purchaseTotal': (purchases.first['total'] as num?)?.toDouble() ?? 0,
    };
  }

  Future<void> addCapitalTransaction({
    required String type,
    required double amount,
    String? description,
  }) async {
    if (amount <= 0) throw Exception('المبلغ يجب أن يكون أكبر من صفر');
    if (type != 'contribution' && type != 'withdrawal') {
      throw Exception('نوع الحركة غير صحيح');
    }
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    if (type == 'withdrawal') {
      final current = await getSummary();
      if (amount > (current['cashBalance'] ?? 0) + 0.001) {
        throw Exception('السحب أكبر من السيولة الحالية');
      }
    }
    await db.insert('capital_transactions', {
      'type': type,
      'amount': amount,
      'description': description,
      'transaction_date': now,
      'created_at': now,
    });
  }

  Future<List<Map<String, dynamic>>> getCapitalTransactions({int limit = 100}) async {
    final db = await _db.database;
    return db.query(
      'capital_transactions',
      orderBy: 'transaction_date DESC',
      limit: limit,
    );
  }
}
