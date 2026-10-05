import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/product.dart';
import '../../providers/app_provider.dart';
import '../../services/product_service.dart';
import '../../services/sale_service.dart';
import '../barcode/barcode_scanner_screen.dart';

class NewSaleScreen extends StatefulWidget {
  const NewSaleScreen({super.key});
  @override
  State<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends State<NewSaleScreen> {
  final _productService = ProductService();
  final _saleService = SaleService();
  final _customerName = TextEditingController();
  final _customerPhone = TextEditingController();
  final _discount = TextEditingController(text: '0');
  final _paid = TextEditingController(text: '0');
  final List<Map<String, dynamic>> _cart = [];
  String _paymentMethod = 'cash';
  DateTime? _dueDate;
  bool _saving = false;

  double get subtotal => _cart.fold(0, (sum, item) => sum + (item['unitPrice'] as double) * (item['quantity'] as int));
  double get discount => double.tryParse(_discount.text.replaceAll(',', '')) ?? 0;
  double get total => (subtotal - discount).clamp(0, double.infinity).toDouble();

  Future<void> _addProduct(Product product) async {
    if (product.stock <= 0) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('المخزون نفد')));
      return;
    }
    final index = _cart.indexWhere((e) => e['productId'] == product.id);
    if (index >= 0) {
      final current = _cart[index]['quantity'] as int;
      if (current >= product.stock) return;
      setState(() => _cart[index]['quantity'] = current + 1);
      return;
    }
    setState(() => _cart.add({
      'productId': product.id,
      'name': product.name,
      'unitPrice': product.sellPrice,
      'quantity': 1,
      'maxStock': product.stock,
    }));
  }

  Future<void> _scan() async {
    final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()));
    if (code == null) return;
    final product = await _productService.getByBarcode(code);
    if (product == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الباركود غير مرتبط بمنتج')));
      return;
    }
    await _addProduct(product);
  }

  Future<void> _chooseProduct() async {
    final searchCtrl = TextEditingController();
    List<Product> items = await _productService.getAll();
    if (!mounted) return;
    final selected = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setModalState) {
        Future<void> search(String value) async {
          items = await _productService.getAll(search: value);
          setModalState(() {});
        }
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * .78,
            child: Column(children: [
              Padding(padding: const EdgeInsets.all(16), child: TextField(controller: searchCtrl, autofocus: true, onChanged: search, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'ابحث عن المنتج'))),
              Expanded(child: items.isEmpty ? const Center(child: Text('لا توجد نتائج')) : ListView.builder(itemCount: items.length, itemBuilder: (_, i) {
                final p = items[i];
                return ListTile(title: Text(p.name), subtitle: Text('المخزون: ${p.stock}'), trailing: Text(context.read<AppProvider>().formatMoney(p.sellPrice)), enabled: p.stock > 0, onTap: () => Navigator.pop(ctx, p));
              })),
            ]),
          ),
        );
      }),
    );
    searchCtrl.dispose();
    if (selected != null) await _addProduct(selected);
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 3650)), initialDate: _dueDate ?? DateTime.now().add(const Duration(days: 30)));
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('السلة فارغة')));
      return;
    }
    final paid = _paymentMethod == 'credit' ? double.tryParse(_paid.text.replaceAll(',', '')) ?? 0 : total;
    if (_paymentMethod == 'credit' && paid > total) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('المدفوع أكبر من الإجمالي')));
      return;
    }
    if (_paymentMethod == 'credit' && paid < total && _dueDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حدد تاريخ الاستحقاق')));
      return;
    }
    setState(() => _saving = true);
    try {
      await _saleService.createSale(
        items: _cart,
        customerName: _customerName.text,
        customerPhone: _customerPhone.text,
        discount: discount,
        paymentMethod: _paymentMethod,
        initialPayment: paid,
        dueDate: _dueDate?.toIso8601String(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ البيع والمخزون والحسابات'), backgroundColor: Colors.green));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر الحفظ: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('بيع جديد'), actions: [IconButton(onPressed: _scan, icon: const Icon(Icons.qr_code_scanner)), IconButton(onPressed: _chooseProduct, icon: const Icon(Icons.search))]),
      body: Column(children: [
        Expanded(child: _cart.isEmpty ? _EmptyCart(onScan: _scan, onSearch: _chooseProduct) : ListView.builder(itemCount: _cart.length, padding: const EdgeInsets.all(8), itemBuilder: (_, i) {
          final item = _cart[i];
          return Card(child: ListTile(
            title: Text(item['name'].toString()),
            subtitle: Text(app.formatMoney(item['unitPrice'] as double)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(onPressed: () => setState(() { if ((item['quantity'] as int) > 1) { item['quantity'] = (item['quantity'] as int) - 1; } else { _cart.removeAt(i); }}), icon: const Icon(Icons.remove_circle_outline)),
              Text('${item['quantity']}'),
              IconButton(onPressed: () { if ((item['quantity'] as int) < (item['maxStock'] as int)) setState(() => item['quantity'] = (item['quantity'] as int) + 1); }, icon: const Icon(Icons.add_circle_outline)),
              IconButton(onPressed: () => setState(() => _cart.removeAt(i)), icon: const Icon(Icons.delete_outline)),
            ]),
          ));
        })),
        Container(
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, boxShadow: const [BoxShadow(blurRadius: 8, offset: Offset(0, -2))]),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(children: [
            TextField(controller: _customerName, decoration: const InputDecoration(labelText: 'اسم العميل (اختياري)', prefixIcon: Icon(Icons.person))),
            const SizedBox(height: 8),
            TextField(controller: _customerPhone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'هاتف العميل (اختياري)', prefixIcon: Icon(Icons.phone))),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: DropdownButtonFormField<String>(value: _paymentMethod, decoration: const InputDecoration(labelText: 'طريقة الدفع'), items: const [
                DropdownMenuItem(value: 'cash', child: Text('نقدي')),
                DropdownMenuItem(value: 'card', child: Text('بطاقة')),
                DropdownMenuItem(value: 'transfer', child: Text('تحويل')),
                DropdownMenuItem(value: 'credit', child: Text('آجل')),
              ], onChanged: (v) => setState(() { _paymentMethod = v ?? 'cash'; if (_paymentMethod != 'credit') _paid.text = total.toStringAsFixed(0); }))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _discount, onChanged: (_) => setState(() {}), keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'خصم'))),
            ]),
            if (_paymentMethod == 'credit') ...[
              const SizedBox(height: 8),
              Row(children: [Expanded(child: TextField(controller: _paid, onChanged: (_) => setState(() {}), keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'الدفعة الآن'))), const SizedBox(width: 8), Expanded(child: OutlinedButton.icon(onPressed: _pickDueDate, icon: const Icon(Icons.event), label: Text(_dueDate == null ? 'تاريخ الاستحقاق' : '${_dueDate!.year}-${_dueDate!.month.toString().padLeft(2, '0')}-${_dueDate!.day.toString().padLeft(2, '0')}')))],),
            ],
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('الإجمالي', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)), Text(app.formatMoney(total), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20))]),
            if (_paymentMethod == 'credit') Align(alignment: Alignment.centerRight, child: Text('متبقي: ${app.formatMoney((total - (double.tryParse(_paid.text) ?? 0)).clamp(0, double.infinity).toDouble())}')),
            const SizedBox(height: 10),
            FilledButton.icon(onPressed: _saving ? null : _checkout, icon: const Icon(Icons.check_circle), label: Text(_saving ? 'جارٍ الحفظ...' : 'تأكيد البيع')),
          ]),
        ),
      ]),
    );
  }

  @override
  void dispose() { _customerName.dispose(); _customerPhone.dispose(); _discount.dispose(); _paid.dispose(); super.dispose(); }
}

class _EmptyCart extends StatelessWidget {
  final VoidCallback onScan;
  final VoidCallback onSearch;
  const _EmptyCart({required this.onScan, required this.onSearch});
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.shopping_cart_outlined, size: 72), const SizedBox(height: 14), const Text('السلة فارغة'), const SizedBox(height: 16), Wrap(spacing: 8, children: [FilledButton.icon(onPressed: onScan, icon: const Icon(Icons.qr_code_scanner), label: const Text('مسح')), OutlinedButton.icon(onPressed: onSearch, icon: const Icon(Icons.search), label: const Text('بحث'))])]));
}
