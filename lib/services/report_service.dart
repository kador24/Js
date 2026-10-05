import 'package:intl/intl.dart';
import 'financial_service.dart';
import 'product_service.dart';
import 'sale_service.dart';
import 'expense_service.dart';
import 'purchase_service.dart';

class ReportService {
  final FinancialService _financial = FinancialService();
  final ProductService _products = ProductService();
  final SaleService _sales = SaleService();
  final ExpenseService _expenses = ExpenseService();
  final PurchaseService _purchases = PurchaseService();

  Future<String> buildTextReport({int days = 7}) async {
    final end = DateTime.now();
    final start = end.subtract(Duration(days: days));
    final summary = await _financial.getSummary(from: start, to: end);
    final top = await _products.getTopSelling(days: days, limit: 5);
    final sales = await _sales.getAll(from: start, to: end);
    final purchases = await _purchases.getAll(from: start, to: end);
    final expenseTotal = await _expenses.getTotal(from: start, to: end);
    final fmt = NumberFormat('#,##0', 'ar');

    final lines = <String>[
      '📊 تقرير Jamal Phone Manager',
      'الفترة: ${DateFormat('yyyy-MM-dd').format(start)} → ${DateFormat('yyyy-MM-dd').format(end)}',
      '',
      '💰 المبيعات: ${fmt.format(summary['sales'] ?? 0)} دج',
      '📈 الربح الإجمالي: ${fmt.format(summary['grossProfit'] ?? 0)} دج',
      '💸 المصاريف: ${fmt.format(expenseTotal)} دج',
      '✅ الربح الصافي: ${fmt.format(summary['netProfit'] ?? 0)} دج',
      '💵 النقد الحالي: ${fmt.format(summary['cashBalance'] ?? 0)} دج',
      '🧾 الذمم المستحقة: ${fmt.format(summary['receivables'] ?? 0)} دج',
      '📦 قيمة المخزون: ${fmt.format(summary['inventoryValue'] ?? 0)} دج',
      '🛒 المشتريات المدفوعة: ${fmt.format(summary['purchasePaid'] ?? 0)} دج',
      '🧾 عدد فواتير المبيعات: ${sales.where((s) => !s.isReturned).length}',
      '📦 عدد فواتير المشتريات: ${purchases.length}',
      '',
      '🏆 الأكثر مبيعًا:',
    ];
    for (final p in top) {
      lines.add('• ${p['product_name']} — ${p['total_qty']} وحدة');
    }
    return lines.join('\n');
  }
}
