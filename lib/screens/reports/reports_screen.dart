import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../providers/app_provider.dart';
import '../../theme/app_theme.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  int _presetDays = 7;
  DateTime? _from;
  DateTime? _to;
  Map<String, dynamic> _report = const {};
  bool _loading = true;

  DateTime get _end => _to ?? DateTime.now();
  DateTime get _start {
    if (_from != null) return _from!;
    final today = DateTime(_end.year, _end.month, _end.day);
    return today.subtract(Duration(days: _presetDays - 1));
  }

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final report = await context.read<AppProvider>().reportsService.buildReport(from: _start, to: _end);
      if (mounted) setState(() { _report = report; _loading = false; });
    } catch (e) {
      if (mounted) { setState(() => _loading = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red)); }
    }
  }

  Future<void> _customRange() async {
    final range = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now(), initialDateRange: DateTimeRange(start: _start, end: _end));
    if (range == null) return;
    setState(() { _from = DateTime(range.start.year, range.start.month, range.start.day); _to = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59, 999); });
    await _load();
  }

  Future<void> _share() async {
    final text = await context.read<AppProvider>().reportsService.buildTextReport(from: _start, to: _end);
    await Share.share(text, subject: 'تقرير Jamal Phone');
  }

  @override
  Widget build(BuildContext context) {
    final summary = (_report['summary'] as Map<String, double>?) ?? const <String, double>{};
    final top = (_report['topSelling'] as List<Map<String, dynamic>>?) ?? const [];
    final alerts = (_report['stockAlerts'] as List<Map<String, dynamic>>?) ?? const [];
    String money(String key) => context.read<AppProvider>().formatMoney(summary[key] ?? 0);
    return Scaffold(
      appBar: AppBar(title: const Text('التقارير'), actions: [IconButton(onPressed: _share, icon: const Icon(Icons.share))]),
      body: _loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(12), children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          ChoiceChip(label: const Text('اليوم'), selected: _from == null && _presetDays == 1, onSelected: (_) { setState(() { _presetDays = 1; _from = null; _to = null; }); _load(); }),
          ChoiceChip(label: const Text('7 أيام'), selected: _from == null && _presetDays == 7, onSelected: (_) { setState(() { _presetDays = 7; _from = null; _to = null; }); _load(); }),
          ChoiceChip(label: const Text('30 يومًا'), selected: _from == null && _presetDays == 30, onSelected: (_) { setState(() { _presetDays = 30; _from = null; _to = null; }); _load(); }),
          ActionChip(avatar: const Icon(Icons.date_range, size: 18), label: Text(_from == null ? 'مخصص' : '${_from!.day}/${_from!.month} → ${_to!.day}/${_to!.month}'), onPressed: _customRange),
        ]),
        const SizedBox(height: 8),
        Text('من ${_start.year}-${_start.month.toString().padLeft(2, '0')}-${_start.day.toString().padLeft(2, '0')} إلى ${_end.year}-${_end.month.toString().padLeft(2, '0')}-${_end.day.toString().padLeft(2, '0')}', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), childAspectRatio: 1.45, children: [
          _Metric('المبيعات', money('sales'), Icons.point_of_sale),
          _Metric('الربح الإجمالي', money('grossProfit'), Icons.trending_up),
          _Metric('المصاريف', money('expenses'), Icons.money_off),
          _Metric('الربح الصافي', money('netProfit'), Icons.savings),
          _Metric('مدفوعات الموردين', money('purchasePaid'), Icons.shopping_cart_checkout),
          _Metric('السيولة نهاية الفترة', money('closingCash'), Icons.account_balance_wallet),
          _Metric('ذمم العملاء', money('receivables'), Icons.receipt_long),
          _Metric('مستحقات الموردين', money('supplierPayables'), Icons.storefront),
          _Metric('قيمة المخزون الحالية', money('inventoryValue'), Icons.inventory_2),
          _Metric('صافي حركة النقد', money('cashMovement'), Icons.swap_horiz),
        ]),
        const SizedBox(height: 12),
        if (top.isNotEmpty) Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const ListTile(title: Text('الأكثر مبيعًا'), leading: Icon(Icons.star)), ...top.take(10).map((e) => ListTile(title: Text(e['product_name'].toString()), trailing: Text('${e['total_qty']} وحدة')))])),
        const SizedBox(height: 12),
        if (alerts.isNotEmpty) Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const ListTile(title: Text('تنبيهات المخزون'), leading: Icon(Icons.warning_amber)), ...alerts.take(10).map((e) => ListTile(title: Text(e['name'].toString()), trailing: Text('${e['stock']} / ${e['min_stock']}')))])),
        const SizedBox(height: 12),
        Card(color: ((summary['netProfit'] ?? 0) >= 0 ? AppTheme.successColor : AppTheme.dangerColor).withAlpha(24), child: Padding(padding: const EdgeInsets.all(16), child: Text((summary['netProfit'] ?? 0) >= 0 ? 'النتيجة: ربح صافي خلال الفترة المحددة.' : 'النتيجة: خسارة صافية خلال الفترة المحددة.', style: const TextStyle(fontWeight: FontWeight.bold)))),
      ])),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.title, this.value, this.icon);
  final String title; final String value; final IconData icon;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon), const SizedBox(height: 6), Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall), const SizedBox(height: 4), Text(value, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))])));
}
