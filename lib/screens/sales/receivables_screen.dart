import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/sale.dart';
import '../../providers/app_provider.dart';

class ReceivablesScreen extends StatefulWidget {
  const ReceivablesScreen({super.key});
  @override
  State<ReceivablesScreen> createState() => _ReceivablesScreenState();
}

class _ReceivablesScreenState extends State<ReceivablesScreen> {
  List<Sale> _items = const [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final service = context.read<AppProvider>().salesService;
      final items = await service.getReceivables();
      if (mounted) setState(() { _items = items; _loading = false; });
    } catch (e) {
      if (mounted) { setState(() => _loading = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red)); }
    }
  }

  Future<void> _collect(Sale sale) async {
    final ctrl = TextEditingController(text: sale.remainingAmount.toStringAsFixed(0));
    final note = TextEditingController();
    String method = 'cash';
    final result = await showDialog<Map<String, dynamic>>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) => AlertDialog(
      title: Text('تحصيل ${sale.invoiceNumber ?? ''}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('المتبقي: ${context.read<AppProvider>().formatMoney(sale.remainingAmount)}'),
        const SizedBox(height: 10),
        TextField(controller: ctrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'المبلغ')),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(value: method, decoration: const InputDecoration(labelText: 'طريقة التحصيل'), items: const [DropdownMenuItem(value: 'cash', child: Text('نقدي')), DropdownMenuItem(value: 'card', child: Text('بطاقة')), DropdownMenuItem(value: 'transfer', child: Text('تحويل'))], onChanged: (v) => setDialog(() => method = v ?? 'cash')),
        const SizedBox(height: 10),
        TextField(controller: note, decoration: const InputDecoration(labelText: 'ملاحظة')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, {'amount': double.tryParse(ctrl.text.replaceAll(',', '')), 'method': method, 'note': note.text}), child: const Text('تحصيل'))],
    )));
    ctrl.dispose(); note.dispose();
    if (result == null) return;
    final amount = (result['amount'] as num?)?.toDouble();
    if (amount == null) return;
    try {
      await context.read<AppProvider>().salesService.recordReceivablePayment(sale.id!, amount, paymentMethod: result['method'] as String, note: result['note'] as String);
      await _load();
      await context.read<AppProvider>().refreshDashboard();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تسجيل التحصيل'), backgroundColor: Colors.green));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red)); }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    return Scaffold(appBar: AppBar(title: const Text('الذمم المستحقة')), body: _loading ? const Center(child: CircularProgressIndicator()) : _items.isEmpty ? const Center(child: Text('لا توجد ذمم مستحقة')) : RefreshIndicator(onRefresh: _load, child: ListView.builder(padding: const EdgeInsets.all(8), itemCount: _items.length, itemBuilder: (_, i) { final s = _items[i]; return Card(child: ListTile(title: Text(s.customerName?.isNotEmpty == true ? s.customerName! : s.invoiceNumber ?? 'عميل'), subtitle: Text('${s.invoiceNumber ?? ''} • ${s.customerPhone ?? ''}'), trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [Text(app.formatMoney(s.remainingAmount), style: const TextStyle(fontWeight: FontWeight.bold)), TextButton(onPressed: () => _collect(s), child: const Text('تحصيل'))]))); })));
  }
}
