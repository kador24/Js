import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/product.dart';
import '../../models/purchase.dart';
import '../../providers/app_provider.dart';
import '../../services/product_service.dart';
import '../../services/purchase_service.dart';
import '../../theme/app_theme.dart';

class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key});
  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  final _service = PurchaseService();
  List<Purchase> _purchases = [];
  bool _loading = true;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async { setState(() => _loading = true); _purchases = await _service.getAll(); if (mounted) setState(() => _loading = false); }

  Future<void> _newPurchase() async {
    final products = await ProductService().getAll();
    if (!mounted) return;
    Product? selected;
    String payment = 'cash';
    DateTime? due;
    final qty = TextEditingController(text: '1');
    final cost = TextEditingController();
    final paid = TextEditingController();
    final note = TextEditingController();
    final ok = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (ctx) => StatefulBuilder(builder: (ctx, setModal) {
      return Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom), child: SizedBox(height: MediaQuery.of(ctx).size.height * .82, child: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('شراء جديد', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 14),
        DropdownButtonFormField<Product>(value: selected, decoration: const InputDecoration(labelText: 'المنتج'), items: products.where((p) => p.id != null).map((p) => DropdownMenuItem(value: p, child: Text(p.name))).toList(), onChanged: (p) { selected = p; cost.text = p?.costPrice.toStringAsFixed(0) ?? ''; setModal(() {}); }),
        const SizedBox(height: 10),
        Row(children: [Expanded(child: TextField(controller: qty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الكمية'))), const SizedBox(width: 10), Expanded(child: TextField(controller: cost, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'تكلفة الوحدة')))]),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(value: payment, decoration: const InputDecoration(labelText: 'الدفع للمورد'), items: const [DropdownMenuItem(value: 'cash', child: Text('نقدي')), DropdownMenuItem(value: 'transfer', child: Text('تحويل')), DropdownMenuItem(value: 'credit', child: Text('آجل'))], onChanged: (v) => setModal(() => payment = v ?? 'cash')),
        if (payment == 'credit') ...[
          const SizedBox(height: 10),
          TextField(controller: paid, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'المدفوع الآن')),
          const SizedBox(height: 10),
          OutlinedButton.icon(onPressed: () async { final d = await showDatePicker(context: ctx, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 3650)), initialDate: DateTime.now().add(const Duration(days: 30))); if (d != null) setModal(() => due = d); }, icon: const Icon(Icons.event), label: Text(due == null ? 'تاريخ استحقاق المورد' : '${due!.year}-${due!.month}-${due!.day}')),
        ],
        const SizedBox(height: 10), TextField(controller: note, decoration: const InputDecoration(labelText: 'ملاحظة')),
        const SizedBox(height: 20), FilledButton(onPressed: selected == null ? null : () => Navigator.pop(ctx, true), child: const Text('حفظ الشراء')),
      ]));
    }));
    final q = int.tryParse(qty.text) ?? 0;
    final c = double.tryParse(cost.text.replaceAll(',', '')) ?? -1;
    final p = payment == 'credit' ? double.tryParse(paid.text.replaceAll(',', '')) ?? 0 : q * c;
    if (ok == true && selected != null && q > 0 && c >= 0) {
      try {
        await _service.createPurchase(items: [{'productId': selected!.id, 'quantity': q, 'unitCost': c}], paymentMethod: payment, paidAmount: p, dueDate: due?.toIso8601String(), notes: note.text.trim().isEmpty ? null : note.text.trim());
        await _load();
        await context.read<AppProvider>().refreshDashboard();
      } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red)); }
    }
    qty.dispose(); cost.dispose(); paid.dispose(); note.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    return Scaffold(appBar: AppBar(title: const Text('المشتريات')), floatingActionButton: FloatingActionButton.extended(onPressed: _newPurchase, icon: const Icon(Icons.add), label: const Text('شراء جديد')), body: _loading ? const Center(child: CircularProgressIndicator()) : _purchases.isEmpty ? const Center(child: Text('لا توجد مشتريات')) : RefreshIndicator(onRefresh: _load, child: ListView.builder(itemCount: _purchases.length, itemBuilder: (_, i) { final p = _purchases[i]; final credit = p.remainingAmount > 0; return Card(child: ListTile(leading: CircleAvatar(backgroundColor: AppTheme.secondaryColor.withAlpha(28), child: const Icon(Icons.shopping_cart, color: AppTheme.secondaryColor)), title: Text(p.invoiceNumber ?? 'شراء #${p.id}'), subtitle: Text('${p.purchaseDate.substring(0,16).replaceAll('T',' ')}${credit ? ' • متبقي ${app.formatMoney(p.remainingAmount)}' : ''}'), trailing: Text(app.formatMoney(p.totalAmount), style: const TextStyle(fontWeight: FontWeight.bold)))); }));
  }
}
