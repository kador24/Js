import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/sale.dart';
import '../../providers/app_provider.dart';
import '../../theme/app_theme.dart';
import 'new_sale_screen.dart';
import 'sale_detail_screen.dart';
import 'receivables_screen.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});
  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  List<Sale> _sales = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try { _sales = await context.read<AppProvider>().salesService.getAll(); } finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('المبيعات'), actions: [IconButton(tooltip: 'الذمم', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReceivablesScreen())).then((_) { _load(); app.refreshDashboard(); }), icon: const Icon(Icons.account_balance_wallet_outlined))]),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewSaleScreen())).then((_) { _load(); app.refreshDashboard(); }), icon: const Icon(Icons.add_shopping_cart), label: const Text('بيع جديد')),
      body: _loading ? const Center(child: CircularProgressIndicator()) : _sales.isEmpty ? const Center(child: Text('لا توجد مبيعات بعد')) : RefreshIndicator(
        onRefresh: _load,
        child: ListView.builder(
          itemCount: _sales.length,
          itemBuilder: (_, i) {
            final s = _sales[i];
            final returned = s.isReturned;
            return Card(child: ListTile(
              leading: CircleAvatar(backgroundColor: (returned ? Colors.grey : AppTheme.successColor).withAlpha(28), child: Icon(returned ? Icons.undo : Icons.receipt_long, color: returned ? Colors.grey : AppTheme.successColor)),
              title: Text(s.invoiceNumber ?? '#${s.id}'),
              subtitle: Text('${s.customerName ?? 'عميل'} • ${s.saleDate.substring(0, 16).replaceAll('T', ' ')}${s.isCredit ? ' • آجل' : ''}'),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [Text(app.formatMoney(s.total), style: TextStyle(fontWeight: FontWeight.bold, decoration: returned ? TextDecoration.lineThrough : null)), if (s.isCredit) Text('متبقي ${app.formatMoney(s.remainingAmount)}', style: const TextStyle(color: AppTheme.warningColor, fontSize: 11)) else Text(app.formatMoney(s.profit), style: const TextStyle(color: AppTheme.successColor, fontSize: 11))]),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SaleDetailScreen(saleId: s.id!))).then((_) { _load(); app.refreshDashboard(); }),
            ));
          },
        ),
      ),
    );
  }
}
