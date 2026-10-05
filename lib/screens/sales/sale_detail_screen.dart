import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/sale.dart';
import '../../providers/app_provider.dart';
import '../../services/sale_service.dart';
import '../../theme/app_theme.dart';

class SaleDetailScreen extends StatefulWidget {
  final int saleId;
  const SaleDetailScreen({super.key, required this.saleId});
  @override
  State<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends State<SaleDetailScreen> {
  final _service = SaleService();
  Sale? _sale;
  bool _loading = true;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async { _sale = await _service.getById(widget.saleId); if (mounted) setState(() => _loading = false); }

  Future<void> _return() async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('إرجاع الفاتورة'), content: const Text('سيعاد كامل المخزون وتعتبر الفاتورة مرتجعة في التقارير. هل أنت متأكد؟'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إرجاع'))]));
    if (ok != true) return;
    try { await _service.returnSale(widget.saleId); if (mounted) { await context.read<AppProvider>().refreshDashboard(); Navigator.pop(context, true); } } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red)); }
  }

  Future<void> _collect() async {
    final sale = _sale!;
    final ctrl = TextEditingController(text: sale.remainingAmount.toStringAsFixed(0));
    final amount = await showDialog<double>(context: context, builder: (ctx) => AlertDialog(title: const Text('تحصيل دفعة'), content: TextField(controller: ctrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'المبلغ', helperText: 'المتبقي ${context.read<AppProvider>().formatMoney(sale.remainingAmount)}')), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text.replaceAll(',', ''))), child: const Text('حفظ'))]));
    ctrl.dispose();
    if (amount == null) return;
    try { await _service.recordReceivablePayment(widget.saleId, amount); await _load(); await context.read<AppProvider>().refreshDashboard(); if (mounted) setState(() {}); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red)); }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final sale = _sale;
    if (sale == null) return const Scaffold(body: Center(child: Text('الفاتورة غير موجودة')));
    return Scaffold(
      appBar: AppBar(title: Text(sale.invoiceNumber ?? 'فاتورة'), actions: [if (!sale.isReturned) IconButton(onPressed: _return, icon: const Icon(Icons.undo))]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (sale.isReturned) Card(color: Colors.orange.withAlpha(25), child: const ListTile(leading: Icon(Icons.info_outline, color: Colors.orange), title: Text('الفاتورة مرتجعة'))),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
          _row('التاريخ', sale.saleDate.substring(0, 16).replaceAll('T', ' ')),
          if (sale.customerName != null) _row('العميل', sale.customerName!),
          if (sale.customerPhone != null) _row('الهاتف', sale.customerPhone!),
          _row('الدفع', _paymentLabel(sale.paymentMethod)),
          _row('المدفوع', app.formatMoney(sale.paidAmount)),
          if (sale.remainingAmount > 0) _row('المتبقي', app.formatMoney(sale.remainingAmount), color: AppTheme.warningColor, bold: true),
          if (sale.dueDate != null) _row('الاستحقاق', sale.dueDate!.substring(0, 10)),
        ]))),
        if (sale.isCredit && !sale.isReturned) Padding(padding: const EdgeInsets.only(top: 10), child: FilledButton.icon(onPressed: _collect, icon: const Icon(Icons.payments), label: const Text('تحصيل دفعة'))),
        const SizedBox(height: 12),
        const Text('المنتجات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        ...sale.items.map((item) => Card(child: ListTile(title: Text(item.productName), subtitle: Text('${item.quantity} × ${app.formatMoney(item.unitPrice)}'), trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [Text(app.formatMoney(item.totalPrice), style: const TextStyle(fontWeight: FontWeight.bold)), Text('ربح ${app.formatMoney(item.profit)}', style: const TextStyle(fontSize: 11, color: AppTheme.successColor))]))),
        const SizedBox(height: 10),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [_row('المجموع', app.formatMoney(sale.subtotal)), if (sale.discount > 0) _row('الخصم', '- ${app.formatMoney(sale.discount)}'), const Divider(), _row('الإجمالي', app.formatMoney(sale.total), bold: true), _row('الربح', app.formatMoney(sale.profit), color: AppTheme.successColor, bold: true)]))),
      ]),
    );
  }

  static String _paymentLabel(String value) => {'cash': 'نقدي', 'card': 'بطاقة', 'transfer': 'تحويل', 'credit': 'آجل'}[value] ?? value;
  Widget _row(String label, String value, {bool bold = false, Color? color}) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: TextStyle(color: Colors.grey[600])), Text(value, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: color))]));
}
