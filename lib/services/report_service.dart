import 'package:intl/intl.dart';
import '../repositories/store_repository.dart';
import '../utils/money.dart';
import 'financial_service.dart';

class ReportService {
  ReportService({StoreRepository? repository})
      : _repo = repository ?? StoreRepository(),
        _financial = FinancialService(repository: repository);

  final StoreRepository _repo;
  final FinancialService _financial;

  Future<Map<String, dynamic>> buildReport({
    required DateTime from,
    required DateTime to,
  }) async {
    final summary = await _financial.getSummary(from: from, to: to);
    final db = await _repo.db;
    final top = await db.rawQuery('''
      SELECT si.product_id, si.product_name,
             SUM(si.quantity) AS total_qty,
             SUM(si.total_price) AS total_sales
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      WHERE s.sale_date >= ? AND s.sale_date <= ? AND s.status = 'completed'
      GROUP BY si.product_id, si.product_name
      ORDER BY total_qty DESC, total_sales DESC
      LIMIT 10
    ''', [from.toIso8601String(), to.toIso8601String()]);
    final start = from.toIso8601String();
    final end = to.toIso8601String();
    final stockAlerts = await db.rawQuery('''
      SELECT id, name, stock, min_stock
      FROM products
      WHERE is_active = 1 AND stock <= min_stock
      ORDER BY stock ASC, name ASC
      LIMIT 50
    ''');
    final purchaseRows = await db.rawQuery('''
      SELECT COUNT(*) AS count, COALESCE(SUM(total_amount),0) AS total
      FROM purchases
      WHERE purchase_date >= ? AND purchase_date <= ?
    ''', [start, end]);
    final expenseRows = await db.rawQuery('''
      SELECT COALESCE(SUM(amount),0) AS total
      FROM expenses
      WHERE status='active' AND expense_date >= ? AND expense_date <= ?
    ''', [start, end]);

    return {
      'from': from,
      'to': to,
      'summary': summary,
      'topSelling': top,
      'stockAlerts': stockAlerts,
      'purchaseCount': (purchaseRows.first['count'] as num?)?.toInt() ?? 0,
      'purchaseTotal': Money.round((purchaseRows.first['total'] as num?)?.toDouble() ?? 0),
      'expenseTotal': Money.round((expenseRows.first['total'] as num?)?.toDouble() ?? 0),
    };
  }

  Future<String> buildTextReport({
    int? days,
    DateTime? from,
    DateTime? to,
  }) async {
    final end = to ?? DateTime.now();
    final start = from ?? end.subtract(Duration(days: days ?? 7));
    final report = await buildReport(from: start, to: end);
    final summary = report['summary'] as Map<String, double>;
    final top = report['topSelling'] as List<Map<String, dynamic>>;
    final alerts = report['stockAlerts'] as List<Map<String, dynamic>>;
    final fmt = NumberFormat('#,##0.00', 'en_US');
    String money(double value) => '${fmt.format(value)} دج';

    final lines = <String>[
      '📊 تقرير Jamal Phone Manager',
      'الفترة: ${DateFormat('yyyy-MM-dd').format(start)} → ${DateFormat('yyyy-MM-dd').format(end)}',
      '',
      '💰 المبيعات: ${money(summary['sales'] ?? 0)}',
      '📈 الربح الإجمالي: ${money(summary['grossProfit'] ?? 0)}',
      '💸 المصاريف: ${money(summary['expenses'] ?? 0)}',
      '✅ الربح الصافي: ${money(summary['netProfit'] ?? 0)}',
      '💵 السيولة في نهاية الفترة: ${money(summary['closingCash'] ?? 0)}',
      '🧾 ذمم العملاء: ${money(summary['receivables'] ?? 0)}',
      '🏭 مستحقات الموردين: ${money(summary['supplierPayables'] ?? 0)}',
      '📦 قيمة المخزون: ${money(summary['inventoryValue'] ?? 0)}',
      '🛒 مشتريات الفترة: ${money(summary['purchaseTotal'] ?? 0)}',
      '💳 مدفوعات الموردين في الفترة: ${money(summary['purchasePaid'] ?? 0)}',
      '🧾 عدد فواتير المبيعات: ${(summary['invoices'] ?? 0).toInt()}',
      '📦 عدد فواتير المشتريات: ${report['purchaseCount']}',
      '',
      '🏆 الأكثر مبيعًا:',
    ];
    if (top.isEmpty) lines.add('لا توجد مبيعات في الفترة.');
    for (final item in top) {
      lines.add('• ${item['product_name']} — ${item['total_qty']} وحدة');
    }
    lines.add('');
    lines.add('⚠️ تنبيهات المخزون: ${alerts.length}');
    for (final item in alerts.take(10)) {
      lines.add('• ${item['name']} — ${item['stock']} (حد ${item['min_stock']})');
    }
    return lines.join('\n');
  }
}
