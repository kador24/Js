import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/financial_service.dart';
import '../../services/product_service.dart';
import '../../services/report_service.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _financial = FinancialService();
  final _product = ProductService();
  final _report = ReportService();
  int _days = 7;
  Map<String, double> _summary = {};
  List<Map<String, dynamic>> _top = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() => _loading = true);
    final end = DateTime.now();
    final start = end.subtract(Duration(days: _days));
    _summary = await _financial.getSummary(from: start, to: end);
    _top = await _product.getTopSelling(days: _days, limit: 5);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _share() async {
    final text = await _report.buildTextReport(days: _days);
    await Share.share(text, subject: 'تقرير Jamal Phone');
  }

  @override
  Widget build(BuildContext context) {
    final money = (String key) => '${(_summary[key] ?? 0).toStringAsFixed(0)} دج';
    return Scaffold(
      appBar: AppBar(title: const Text('التقارير'), actions: [IconButton(onPressed: _share, icon: const Icon(Icons.share))]),
      body: _loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(12), children: [
          SegmentedButton<int>(segments: const [ButtonSegment(value: 7, label: Text('7 أيام')), ButtonSegment(value: 30, label: Text('30 يومًا')), ButtonSegment(value: 90, label: Text('90 يومًا'))], selected: {_days}, onSelectionChanged: (v) { setState(() => _days = v.first); _load(); }),
          const SizedBox(height: 10),
          GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), childAspectRatio: 1.45, children: [
            _Metric('المبيعات', money('sales'), Icons.point_of_sale),
            _Metric('الربح الإجمالي', money('grossProfit'), Icons.trending_up),
            _Metric('المصاريف', money('expenses'), Icons.money_off),
            _Metric('الربح الصافي', money('netProfit'), Icons.savings),
            _Metric('المشتريات المدفوعة', money('purchasePaid'), Icons.shopping_cart),
            _Metric('السيولة الحالية', money('cashBalance'), Icons.account_balance_wallet),
            _Metric('الذمم', money('receivables'), Icons.receipt_long),
            _Metric('المخزون', money('inventoryValue'), Icons.inventory_2),
          ]),
          const SizedBox(height: 12),
          if (_top.isNotEmpty) Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const ListTile(title: Text('الأكثر مبيعًا'), leading: Icon(Icons.star)), ..._top.map((e) => ListTile(title: Text(e['product_name'].toString()), trailing: Text('${e['total_qty']} وحدة')))])),
          const SizedBox(height: 12),
          _ProfitNotice(summary: _summary),
        ]),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String title; final String value; final IconData icon;
  const _Metric(this.title, this.value, this.icon);
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon), const SizedBox(height: 6), Text(title, style: Theme.of(context).textTheme.bodySmall), const SizedBox(height: 4), Text(value, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))])));
}

class _ProfitNotice extends StatelessWidget {
  final Map<String, double> summary;
  const _ProfitNotice({required this.summary});
  @override
  Widget build(BuildContext context) {
    final profit = summary['netProfit'] ?? 0;
    return Card(color: (profit >= 0 ? Colors.green : Colors.red).withAlpha(24), child: Padding(padding: const EdgeInsets.all(16), child: Text(profit >= 0 ? 'النتيجة جيدة: النشاط حقق ربحًا صافيًا خلال الفترة المحددة.' : 'تنبيه: النشاط سجل خسارة صافية خلال الفترة المحددة.', style: const TextStyle(fontWeight: FontWeight.bold))));
  }
}
