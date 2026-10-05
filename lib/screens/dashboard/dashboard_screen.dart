import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../../theme/app_theme.dart';
import '../inventory/stock_movements_screen.dart';
import '../reports/reports_screen.dart';
import '../sales/new_sale_screen.dart';
import '../purchases/purchases_screen.dart';
import '../products/product_form_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<AppProvider>().refreshDashboard());
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    return Scaffold(
      appBar: AppBar(
        title: Text(app.storeName),
        actions: [IconButton(onPressed: app.refreshDashboard, icon: const Icon(Icons.refresh))],
      ),
      body: RefreshIndicator(
        onRefresh: app.refreshDashboard,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
          children: [
            Text('نظرة اليوم', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.45,
              children: [
                _StatCard('مبيعات اليوم', app.formatMoney(app.todayStats['sales'] ?? 0), Icons.point_of_sale, AppTheme.primaryColor),
                _StatCard('ربح اليوم', app.formatMoney(app.todayStats['profit'] ?? 0), Icons.trending_up, AppTheme.successColor),
                _StatCard('السيولة', app.formatMoney(app.cashBalance), Icons.account_balance_wallet, AppTheme.secondaryColor),
                _StatCard('الذمم', app.formatMoney(app.receivables), Icons.receipt_long, AppTheme.warningColor),
                _StatCard('رأس المال', app.formatMoney(app.currentCapital), Icons.business, AppTheme.primaryColor),
                _StatCard('قيمة المخزون', app.formatMoney(app.inventoryValue), Icons.inventory, AppTheme.successColor),
              ].asMap().entries.map((e) => e.value.animate().fadeIn(delay: (e.key * 50).ms)).toList(),
            ),
            const SizedBox(height: 8),
            _QuickActions(app: app),
            const SizedBox(height: 12),
            if (app.salesChart.isNotEmpty) _SalesChart(app.salesChart),
            const SizedBox(height: 12),
            if (app.lowStockProducts.isNotEmpty) _LowStockCard(app),
            const SizedBox(height: 12),
            if (app.topSelling.isNotEmpty) _TopSellingCard(app),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  const _StatCard(this.title, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(backgroundColor: color.withAlpha(28), child: Icon(icon, color: color)),
            const SizedBox(width: 10),
            Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 5),
              Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            ])),
          ],
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  final AppProvider app;
  const _QuickActions({required this.app});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewSaleScreen())).then((_) => app.refreshDashboard()), icon: const Icon(Icons.add_shopping_cart), label: const Text('بيع')),
            FilledButton.tonalIcon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchasesScreen())), icon: const Icon(Icons.add_business), label: const Text('شراء')),
            FilledButton.tonalIcon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductFormScreen())), icon: const Icon(Icons.add_box), label: const Text('منتج')),
            OutlinedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsScreen())), icon: const Icon(Icons.analytics), label: const Text('التقارير')),
            OutlinedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StockMovementsScreen())), icon: const Icon(Icons.swap_vert), label: const Text('حركة المخزون')),
          ],
        ),
      ),
    );
  }
}

class _SalesChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  const _SalesChart(this.data);
  @override
  Widget build(BuildContext context) {
    final maxValue = data.fold<double>(0, (m, e) => math.max(m, (e['total'] as num).toDouble()));
    final upper = maxValue <= 0 ? 100.0 : maxValue * 1.25;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('المبيعات — آخر 7 أيام', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          SizedBox(
            height: 210,
            child: BarChart(BarChartData(
              maxY: upper,
              alignment: BarChartAlignment.spaceAround,
              borderData: FlBorderData(show: false),
              gridData: const FlGridData(show: false),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= data.length) return const SizedBox.shrink();
                  return Padding(padding: const EdgeInsets.only(top: 6), child: Text(data[index]['date'].toString(), style: const TextStyle(fontSize: 10)));
                })),
              ),
              barGroups: List.generate(data.length, (i) {
                final value = (data[i]['total'] as num).toDouble();
                return BarChartGroupData(x: i, barRods: [BarChartRodData(toY: value, width: 20, borderRadius: BorderRadius.circular(5))]);
              }),
            )),
          ),
        ]),
      ),
    );
  }
}

class _LowStockCard extends StatelessWidget {
  final AppProvider app;
  const _LowStockCard(this.app);
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(children: [
        ListTile(leading: const Icon(Icons.warning_amber, color: AppTheme.warningColor), title: const Text('تنبيه المخزون'), subtitle: Text('${app.lowStockProducts.length} منتجات تحت حد التنبيه')),
        ...app.lowStockProducts.take(5).map((p) => ListTile( dense: true, title: Text(p.name), trailing: Text('${p.stock} وحدة', style: const TextStyle(color: AppTheme.dangerColor, fontWeight: FontWeight.bold)))),
      ]),
    );
  }
}

class _TopSellingCard extends StatelessWidget {
  final AppProvider app;
  const _TopSellingCard(this.app);
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(children: [
        const ListTile(leading: Icon(Icons.star, color: AppTheme.warningColor), title: Text('الأكثر مبيعًا')), 
        ...app.topSelling.map((p) => ListTile(dense: true, title: Text(p['product_name'].toString()), trailing: Text('${p['total_qty']} وحدة'))),
      ]),
    );
  }
}
