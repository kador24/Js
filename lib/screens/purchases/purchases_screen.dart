import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/product.dart';
import '../../models/purchase.dart';
import '../../models/supplier.dart';
import '../../providers/app_provider.dart';
import '../../theme/app_theme.dart';

class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key});
  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchaseLine {
  _PurchaseLine({required this.product, required this.quantity, required this.unitCost});
  final Product product;
  int quantity;
  double unitCost;
  double get total => quantity * unitCost;
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  List<Purchase> _purchases = const [];
  Map<String, double> _payables = const {};
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final app = context.read<AppProvider>();
      final purchases = await app.purchasesService.getAll();
      final payables = await app.purchasesService.getPayables();
      if (mounted) setState(() { _purchases = purchases; _payables = payables; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<Supplier?> _chooseOrCreateSupplier(List<Supplier> suppliers) async {
    return showModalBottomSheet<Supplier>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          const Text('المورد', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ListTile(leading: const Icon(Icons.person_add), title: const Text('إضافة مورد جديد'), onTap: () async {
            final name = TextEditingController();
            final phone = TextEditingController();
            final ok = await showDialog<bool>(context: ctx, builder: (dialog) => AlertDialog(
              title: const Text('مورد جديد'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم المورد *')), TextField(controller: phone, decoration: const InputDecoration(labelText: 'الهاتف'))]),
              actions: [TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(dialog, name.text.trim().isNotEmpty), child: const Text('حفظ'))],
            ));
            if (ok == true) {
              try {
                final id = await context.read<AppProvider>().suppliersService.create(name: name.text, phone: phone.text);
                final created = (await context.read<AppProvider>().suppliersService.getAll()).firstWhere((s) => s.id == id);
                if (ctx.mounted) Navigator.pop(ctx, created);
              } catch (e) { if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$e'))); }
            }
            name.dispose(); phone.dispose();
          }),
          if (suppliers.isNotEmpty) ...[
            const Divider(),
            for (final supplier in suppliers) ListTile(leading: const Icon(Icons.storefront), title: Text(supplier.name), subtitle: Text(supplier.phone ?? ''), onTap: () => Navigator.pop(ctx, supplier)),
          ],
        ],
      ),
    );
  }

  Future<void> _newPurchase() async {
    final app = context.read<AppProvider>();
    final products = await app.productsService.getAll();
    final suppliers = await app.suppliersService.getAll();
    if (!mounted) return;
    final lines = <_PurchaseLine>[];
    Supplier? supplier;
    String payment = 'cash';
    String initialPaymentMethod = 'cash';
    DateTime? due;
    final invoice = TextEditingController();
    final note = TextEditingController();
    final paid = TextEditingController();

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setModal) {
        double total() => lines.fold(0, (sum, line) => sum + line.total);
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * .92,
            child: Column(children: [
              Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 8), child: Row(children: [
                const Expanded(child: Text('شراء جديد', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                IconButton(onPressed: () => Navigator.pop(ctx, false), icon: const Icon(Icons.close)),
              ])),
              Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
                OutlinedButton.icon(
                  onPressed: () async { final s = await _chooseOrCreateSupplier(suppliers); if (s != null) setModal(() => supplier = s); },
                  icon: const Icon(Icons.storefront),
                  label: Text(supplier == null ? 'اختيار المورد (اختياري)' : supplier!.name),
                ),
                const SizedBox(height: 10),
                TextField(controller: invoice, decoration: const InputDecoration(labelText: 'رقم الفاتورة (اختياري)', prefixIcon: Icon(Icons.receipt_long))),
                const SizedBox(height: 14),
                Card(child: Padding(padding: const EdgeInsets.all(8), child: Column(children: [
                  Row(children: [const Expanded(child: Text('منتجات الفاتورة', style: TextStyle(fontWeight: FontWeight.bold))), Text('${lines.length} صنف')]),
                  const SizedBox(height: 8),
                  if (lines.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('أضف أكثر من منتج إلى نفس فاتورة الشراء.')),
                  for (var i = 0; i < lines.length; i++) _PurchaseLineTile(line: lines[i], onChanged: () => setModal(() {}), onDelete: () => setModal(() => lines.removeAt(i))),
                  FilledButton.tonalIcon(onPressed: products.isEmpty ? null : () async {
                    final selected = await showDialog<Product>(context: ctx, builder: (dialog) => SimpleDialog(title: const Text('اختر منتجًا'), children: [for (final p in products) SimpleDialogOption(onPressed: () => Navigator.pop(dialog, p), child: Text(p.name))]));
                    if (selected != null) setModal(() => lines.add(_PurchaseLine(product: selected, quantity: 1, unitCost: selected.costPrice)));
                  }, icon: const Icon(Icons.add), label: const Text('إضافة منتج')),
                ]))),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(value: payment, decoration: const InputDecoration(labelText: 'طريقة الدفع'), items: const [DropdownMenuItem(value: 'cash', child: Text('نقدي')), DropdownMenuItem(value: 'transfer', child: Text('تحويل')), DropdownMenuItem(value: 'credit', child: Text('آجل'))], onChanged: (v) => setModal(() { payment = v ?? 'cash'; if (payment != 'credit') paid.text = total().toStringAsFixed(0); })),
                if (payment == 'credit') ...[
                  const SizedBox(height: 10),
                  TextField(controller: paid, onChanged: (_) => setModal(() {}), keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'المدفوع الآن')),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(value: initialPaymentMethod, decoration: const InputDecoration(labelText: 'طريقة الدفعة الأولى'), items: const [
                    DropdownMenuItem(value: 'cash', child: Text('نقدي')),
                    DropdownMenuItem(value: 'transfer', child: Text('تحويل')),
                  ], onChanged: (v) => setModal(() => initialPaymentMethod = v ?? 'cash')),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(onPressed: () async { final d = await showDatePicker(context: ctx, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 3650)), initialDate: due ?? DateTime.now().add(const Duration(days: 30))); if (d != null) setModal(() => due = d); }, icon: const Icon(Icons.event), label: Text(due == null ? 'تاريخ استحقاق المورد' : '${due!.year}-${due!.month.toString().padLeft(2, '0')}-${due!.day.toString().padLeft(2, '0')}')),
                ],
                const SizedBox(height: 10),
                TextField(controller: note, decoration: const InputDecoration(labelText: 'ملاحظة')),
                const SizedBox(height: 14),
                ListTile(title: const Text('الإجمالي'), trailing: Text(app.formatMoney(total()), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                if (payment == 'credit') ListTile(title: const Text('المتبقي'), trailing: Text(app.formatMoney((total() - (double.tryParse(paid.text.replaceAll(',', '')) ?? 0)).clamp(0, double.infinity).toDouble()))),
                FilledButton.icon(onPressed: lines.isEmpty ? null : () => Navigator.pop(ctx, true), icon: const Icon(Icons.save), label: const Text('حفظ الفاتورة')),
              ])),
            ]),
          ),
        );
      }),
    );

    final total = lines.fold<double>(0, (sum, line) => sum + line.total);
    final paidNow = payment == 'credit' ? double.tryParse(paid.text.replaceAll(',', '')) ?? 0 : total;
    if (saved != true) { invoice.dispose(); note.dispose(); paid.dispose(); return; }
    try {
      await app.purchasesService.createPurchase(
        supplierId: supplier?.id,
        invoiceNumber: invoice.text,
        notes: note.text,
        paymentMethod: payment,
        initialPaymentMethod: initialPaymentMethod,
        paidAmount: paidNow,
        dueDate: due?.toIso8601String(),
        items: [for (final line in lines) {'productId': line.product.id, 'quantity': line.quantity, 'unitCost': line.unitCost}],
      );
      await _load();
      await app.refreshDashboard();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ الشراء والمخزون والدفعة'), backgroundColor: Colors.green));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red)); }
    invoice.dispose(); note.dispose(); paid.dispose();
  }

  Future<void> _pay(Purchase purchase) async {
    final ctrl = TextEditingController();
    final note = TextEditingController();
    String method = 'cash';
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) => AlertDialog(
      title: Text('دفع للمورد • ${purchase.invoiceNumber ?? '#${purchase.id}'}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('المتبقي: ${context.read<AppProvider>().formatMoney(purchase.remainingAmount)}'),
        const SizedBox(height: 10),
        TextField(controller: ctrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'المبلغ')),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(value: method, items: const [DropdownMenuItem(value: 'cash', child: Text('نقدي')), DropdownMenuItem(value: 'transfer', child: Text('تحويل'))], onChanged: (v) => setDialog(() => method = v ?? 'cash'), decoration: const InputDecoration(labelText: 'طريقة الدفع')),
        const SizedBox(height: 10),
        TextField(controller: note, decoration: const InputDecoration(labelText: 'ملاحظة')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تسجيل الدفع'))],
    )));
    if (ok != true) { ctrl.dispose(); note.dispose(); return; }
    try {
      await context.read<AppProvider>().purchasesService.recordSupplierPayment(purchase.id!, double.tryParse(ctrl.text.replaceAll(',', '')) ?? 0, paymentMethod: method, note: note.text);
      await _load();
      await context.read<AppProvider>().refreshDashboard();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red)); }
    ctrl.dispose(); note.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('المشتريات')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _newPurchase, icon: const Icon(Icons.add_shopping_cart), label: const Text('شراء جديد')),
      body: _loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
        Card(child: ListTile(leading: const Icon(Icons.account_balance), title: const Text('إجمالي مستحقات الموردين'), trailing: Text(app.formatMoney(_payables['payable'] ?? 0), style: const TextStyle(fontWeight: FontWeight.bold)))),
        const SizedBox(height: 8),
        if (_purchases.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('لا توجد مشتريات'))),
        for (final purchase in _purchases) Card(child: ListTile(
          leading: CircleAvatar(backgroundColor: AppTheme.secondaryColor.withAlpha(28), child: const Icon(Icons.shopping_cart, color: AppTheme.secondaryColor)),
          title: Text(purchase.invoiceNumber ?? 'شراء #${purchase.id}'),
          subtitle: Text('${purchase.supplierName ?? 'بدون مورد'} • ${purchase.items.length} صنف • ${purchase.purchaseDate.substring(0, 16).replaceAll('T', ' ')}'),
          trailing: purchase.remainingAmount > 0 ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(app.formatMoney(purchase.remainingAmount), style: const TextStyle(fontWeight: FontWeight.bold)), TextButton(onPressed: () => _pay(purchase), child: const Text('دفع'))]) : Text(app.formatMoney(purchase.totalAmount), style: const TextStyle(fontWeight: FontWeight.bold)),
        )),
      ])),
    );
  }
}

class _PurchaseLineTile extends StatelessWidget {
  const _PurchaseLineTile({required this.line, required this.onChanged, required this.onDelete});
  final _PurchaseLine line;
  final VoidCallback onChanged;
  final VoidCallback onDelete;
  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(line.product.name),
    subtitle: Text('${line.quantity} × ${line.unitCost.toStringAsFixed(0)} = ${line.total.toStringAsFixed(0)}'),
    trailing: Wrap(spacing: 0, children: [
      IconButton(onPressed: () { if (line.quantity > 1) { line.quantity--; onChanged(); } }, icon: const Icon(Icons.remove_circle_outline)),
      IconButton(onPressed: () { line.quantity++; onChanged(); }, icon: const Icon(Icons.add_circle_outline)),
      IconButton(onPressed: onDelete, icon: const Icon(Icons.delete_outline)),
    ]),
  );
}
