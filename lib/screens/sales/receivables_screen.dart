import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/sale.dart';
import '../../providers/app_provider.dart';
import '../../services/sale_service.dart';

class ReceivablesScreen extends StatefulWidget {
  const ReceivablesScreen({super.key});
  @override
  State<ReceivablesScreen> createState() => _ReceivablesScreenState();
}

class _ReceivablesScreenState extends State<ReceivablesScreen> {
  final _service = SaleService();
  List<Sale> _items = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async { setState(() => _loading = true); _items = await _service.getReceivables(); if (mounted) setState(() => _loading = false); }

  Future<void> _collect(Sale sale) async {
    final ctrl = TextEditingController();
    final note = TextEditingController();
    final amount = await showDialog<double>(context: context, builder: (ctx) => AlertDialog(
      title: Text('تحصيل ${sale.invoiceNumber ?? ''}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [Text('المتبقي: ${context.read<AppProvider>().formatMoney(sale.remainingAmount)}'), const SizedBox(height: 10), TextField(controller: ctrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'المبلغ')), const SizedBox(height: 10), TextField(controller: note, decoration: const InputDecoration(labelText: 'ملاحظة'))]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text.replaceAll(',', ''))), child: const Text('تحصيل'))],
    ));
    ctrl.dispose(); note.dispose();
    if (amount == null) return;
    try { await _service.recordReceivablePayment(sale.id!, amount); if (mounted) { await _load(); await context.read<AppProvider>().refreshDashboard(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تسجيل التحصيل'), backgroundColor: Colors.green)); } } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red)); }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    return Scaffold(appBar: AppBar(title: const Text('الذمم المستحقة')), body: _loading ? const Center(child: CircularProgressIndicator()) : _items.isEmpty ? const Center(child: Text('لا توجد ذمم مستحقة')) : RefreshIndicator(onRefresh: _load, child: ListView.builder(itemCount: _items.length, itemBuilder: (_, i) { final s = _items[i]; return Card(child: ListTile(title: Text(s.customerName?.isNotEmpty == true ? s.customerName! : s.invoiceNumber ?? 'عميل'), subtitle: Text('${s.invoiceNumber ?? ''} • ${s.customerPhone ?? ''}'), trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [Text(app.formatMoney(s.remainingAmount), style: const TextStyle(fontWeight: FontWeight.bold)), TextButton(onPressed: () => _collect(s), child: const Text('تحصيل'))])); })),
    );
  }
}
