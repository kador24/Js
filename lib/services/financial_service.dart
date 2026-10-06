import 'package:sqflite/sqflite.dart';
import '../repositories/store_repository.dart';
import '../utils/money.dart';
import 'product_service.dart';

class FinancialService {
  FinancialService({StoreRepository? repository})
      : _repo = repository ?? StoreRepository(),
        _products = ProductService(repository: repository);

  final StoreRepository _repo;
  final ProductService _products;

  Future<double> _initialCapital(Database db) async {
    final rows = await db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['initial_capital'],
      limit: 1,
    );
    return rows.isEmpty
        ? 0
        : Money.round(double.tryParse(rows.first['value'] as String? ?? '') ?? 0);
  }

  Future<double> _ledgerBalance(Database db, {DateTime? to}) async {
    var where = '1=1';
    final args = <dynamic>[];
    if (to != null) {
      where += ' AND transaction_date <= ?';
      args.add(to.toIso8601String());
    }
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(CASE WHEN direction = 'in' THEN amount ELSE -amount END), 0) AS balance
      FROM payment_ledger
      WHERE $where
    ''', args);
    return Money.round((rows.first['balance'] as num?)?.toDouble() ?? 0);
  }

  Future<Map<String, double>> getSummary({DateTime? from, DateTime? to}) async {
    final db = await _repo.db;
    final end = to ?? DateTime.now();

    var salesWhere = "status = 'completed'";
    var expenseWhere = "status = 'active'";
    var purchaseWhere = '1=1';
    var capitalWhere = '1=1';
    final salesArgs = <dynamic>[];
    final expenseArgs = <dynamic>[];
    final purchaseArgs = <dynamic>[];
    final capitalArgs = <dynamic>[];

    if (from != null) {
      salesWhere += ' AND sale_date >= ?';
      expenseWhere += ' AND expense_date >= ?';
      purchaseWhere += ' AND purchase_date >= ?';
      capitalWhere += ' AND transaction_date >= ?';
      final value = from.toIso8601String();
      salesArgs.add(value);
      expenseArgs.add(value);
      purchaseArgs.add(value);
      capitalArgs.add(value);
    }
    salesWhere += ' AND sale_date <= ?';
    expenseWhere += ' AND expense_date <= ?';
    purchaseWhere += ' AND purchase_date <= ?';
    capitalWhere += ' AND transaction_date <= ?';
    salesArgs.add(end.toIso8601String());
    expenseArgs.add(end.toIso8601String());
    purchaseArgs.add(end.toIso8601String());
    capitalArgs.add(end.toIso8601String());

    final sale = await db.rawQuery('''
      SELECT COALESCE(SUM(total),0) AS sales,
             COALESCE(SUM(profit),0) AS gross_profit,
             COUNT(*) AS invoices
      FROM sales WHERE $salesWhere
    ''', salesArgs);
    final expenses = await db.rawQuery(
      'SELECT COALESCE(SUM(amount),0) AS total FROM expenses WHERE $expenseWhere',
      expenseArgs,
    );
    final purchases = await db.rawQuery('''
      SELECT COALESCE(SUM(total_amount),0) AS total
      FROM purchases WHERE $purchaseWhere
    ''', purchaseArgs);
    final purchasePayments = await db.rawQuery('''
      SELECT COALESCE(SUM(amount),0) AS paid
      FROM payment_ledger
      WHERE direction='out' AND entry_type='supplier_payment'
        AND transaction_date >= ? AND transaction_date <= ?
    ''', [
      (from ?? DateTime.fromMillisecondsSinceEpoch(0)).toIso8601String(),
      end.toIso8601String(),
    ]);
    final capital = await db.rawQuery('''
      SELECT COALESCE(SUM(CASE WHEN type='contribution' THEN amount ELSE 0 END),0) AS in_amount,
             COALESCE(SUM(CASE WHEN type='withdrawal' THEN amount ELSE 0 END),0) AS out_amount
      FROM capital_transactions WHERE $capitalWhere
    ''', capitalArgs);

    final receivableRows = await db.rawQuery('''
      SELECT COALESCE(SUM(
        s.total - COALESCE((SELECT SUM(CASE WHEN pl.direction='in' THEN pl.amount ELSE -pl.amount END)
                            FROM payment_ledger pl
                            WHERE pl.reference_type='sale' AND pl.reference_id=s.id
                              AND pl.entry_type IN ('sale_payment','customer_collection','sale_refund')
                              AND pl.transaction_date <= ?), 0)
      ),0) AS total
      FROM sales s
      WHERE s.status='completed' AND s.payment_method='credit'
        AND s.sale_date <= ?
        AND s.total > COALESCE((SELECT SUM(CASE WHEN pl.direction='in' THEN pl.amount ELSE -pl.amount END)
                                FROM payment_ledger pl
                                WHERE pl.reference_type='sale' AND pl.reference_id=s.id
                                  AND pl.entry_type IN ('sale_payment','customer_collection','sale_refund')
                                  AND pl.transaction_date <= ?),0)
    ''', [end.toIso8601String(), end.toIso8601String(), end.toIso8601String()]);
    final payableRows = await db.rawQuery('''
      SELECT COALESCE(SUM(
        p.total_amount - COALESCE((SELECT SUM(pl.amount) FROM payment_ledger pl
                                  WHERE pl.reference_type='purchase'
                                    AND pl.reference_id=p.id
                                    AND pl.entry_type='supplier_payment'
                                    AND pl.direction='out'
                                    AND pl.transaction_date <= ?),0)
      ),0) AS total
      FROM purchases p
      WHERE p.purchase_date <= ?
        AND p.total_amount > COALESCE((SELECT SUM(pl.amount) FROM payment_ledger pl
                                      WHERE pl.reference_type='purchase'
                                        AND pl.reference_id=p.id
                                        AND pl.entry_type='supplier_payment'
                                        AND pl.direction='out'
                                        AND pl.transaction_date <= ?),0)
    ''', [end.toIso8601String(), end.toIso8601String(), end.toIso8601String()]);

    final initialCapital = await _initialCapital(db);
    final inventoryValue = await _products.getInventoryValue();
    final allCash = await _ledgerBalance(db);
    final closingCash = await _ledgerBalance(db, to: end);

    var ledgerWhere = 'transaction_date >= ? AND transaction_date <= ?';
    final ledgerArgs = [
      (from ?? DateTime.fromMillisecondsSinceEpoch(0)).toIso8601String(),
      end.toIso8601String(),
    ];
    final periodLedgerRows = await db.rawQuery('''
      SELECT COALESCE(SUM(CASE WHEN direction='in' THEN amount ELSE 0 END),0) AS inflow,
             COALESCE(SUM(CASE WHEN direction='out' THEN amount ELSE 0 END),0) AS outflow,
             COALESCE(SUM(CASE WHEN direction='in' AND entry_type IN ('sale_payment','customer_collection') THEN amount ELSE 0 END),0) AS collections,
             COALESCE(SUM(CASE WHEN direction='out' AND entry_type='sale_refund' THEN amount ELSE 0 END),0) AS refunds
      FROM payment_ledger WHERE $ledgerWhere
    ''', ledgerArgs);

    final salesTotal = (sale.first['sales'] as num?)?.toDouble() ?? 0;
    final grossProfit = (sale.first['gross_profit'] as num?)?.toDouble() ?? 0;
    final expenseTotal = (expenses.first['total'] as num?)?.toDouble() ?? 0;
    final purchaseTotal = (purchases.first['total'] as num?)?.toDouble() ?? 0;
    final purchasePaid = (purchasePayments.first['paid'] as num?)?.toDouble() ?? 0;
    final capitalIn = (capital.first['in_amount'] as num?)?.toDouble() ?? 0;
    final capitalOut = (capital.first['out_amount'] as num?)?.toDouble() ?? 0;
    final receivableTotal = (receivableRows.first['total'] as num?)?.toDouble() ?? 0;
    final payableTotal = (payableRows.first['total'] as num?)?.toDouble() ?? 0;
    final periodInflow = (periodLedgerRows.first['inflow'] as num?)?.toDouble() ?? 0;
    final periodOutflow = (periodLedgerRows.first['outflow'] as num?)?.toDouble() ?? 0;
    final periodCollections = (periodLedgerRows.first['collections'] as num?)?.toDouble() ?? 0;
    final periodRefunds = (periodLedgerRows.first['refunds'] as num?)?.toDouble() ?? 0;

    return {
      'initialCapital': Money.round(initialCapital),
      'sales': Money.round(salesTotal),
      'grossProfit': Money.round(grossProfit),
      'expenses': Money.round(expenseTotal),
      'netProfit': Money.round(grossProfit - expenseTotal),
      'purchasePaid': Money.round(purchasePaid),
      'purchaseTotal': Money.round(purchaseTotal),
      'capitalIn': Money.round(capitalIn),
      'capitalOut': Money.round(capitalOut),
      'cashBalance': allCash,
      'closingCash': closingCash,
      'cashMovement': Money.round(periodInflow - periodOutflow),
      // Balance-sheet identity: current owner equity is what remains after
      // settling current liabilities, independent of the selected report period.
      'currentCapital': Money.round(allCash + receivableTotal + inventoryValue - payableTotal),
      'receivables': Money.round(receivableTotal),
      'supplierPayables': Money.round(payableTotal),
      'inventoryValue': Money.round(inventoryValue),
      'collected': Money.round(periodCollections),
      'refunds': Money.round(periodRefunds),
      'periodOutflow': Money.round(periodOutflow),
      'invoices': (sale.first['invoices'] as num?)?.toDouble() ?? 0,
    };
  }

  Future<void> addCapitalTransaction({
    required String type,
    required double amount,
    String? description,
  }) async {
    final cleanAmount = Money.round(amount);
    if (cleanAmount <= 0) throw Exception('المبلغ يجب أن يكون أكبر من صفر');
    if (type != 'contribution' && type != 'withdrawal') {
      throw Exception('نوع الحركة غير صحيح');
    }

    await _repo.transaction((txn) async {
      if (type == 'withdrawal') {
        final rows = await txn.rawQuery('''
          SELECT COALESCE(SUM(CASE WHEN direction='in' THEN amount ELSE -amount END),0) AS balance
          FROM payment_ledger
        ''');
        final current = (rows.first['balance'] as num?)?.toDouble() ?? 0;
        if (cleanAmount > current + 0.005) {
          throw Exception('السحب أكبر من السيولة الحالية');
        }
      }
      final now = DateTime.now().toIso8601String();
      final id = await txn.insert('capital_transactions', {
        'type': type,
        'amount': cleanAmount,
        'description': description?.trim().isEmpty == true ? null : description?.trim(),
        'transaction_date': now,
        'created_at': now,
      });
      await txn.insert('payment_ledger', {
        'direction': type == 'contribution' ? 'in' : 'out',
        'entry_type': type == 'contribution' ? 'capital_in' : 'capital_out',
        'amount': cleanAmount,
        'payment_method': 'cash',
        'source_table': 'capital_transactions',
        'source_id': id,
        'reference_type': 'capital',
        'reference_id': id,
        'note': description,
        'transaction_date': now,
        'created_at': now,
      });
    });
  }

  Future<List<Map<String, dynamic>>> getCapitalTransactions({int limit = 100}) async {
    final db = await _repo.db;
    return db.query('capital_transactions', orderBy: 'transaction_date DESC, id DESC', limit: limit);
  }
}
