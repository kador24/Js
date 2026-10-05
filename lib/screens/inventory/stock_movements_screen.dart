import 'package:flutter/material.dart';
import '../../models/product.dart';
import '../../models/stock_movement.dart';
import '../../services/product_service.dart';

class StockMovementsScreen extends StatefulWidget {
  const StockMovementsScreen({super.key});

  @override
  State<StockMovementsScreen> createState() => _StockMovementsScreenState();
}

class _StockMovementsScreenState extends State<StockMovementsScreen> {
  final _service = ProductService();
  List<StockMovement> _movements = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      _movements = await _service.getMovements();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _type(String value) => {
        'in': 'شراء / دخول',
        'out': 'بيع / خروج',
        'return': 'مرتجع',
        'opening': 'افتتاحي',
        'adjust': 'تسوية يدوية',
      }[value] ?? value;

  Future<void> _adjustStock() async {
    final products = await _service.getAll();
    if (!mounted) return;
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أضف منتجًا أولًا')),
      );
      return;
    }

    Product? selected;
    final target = TextEditingController();
    final note = TextEditingController();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: ListView(
            padding: const EdgeInsets.all(16),
            shrinkWrap: true,
            children: [
              const Text('تسوية المخزون', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              DropdownButtonFormField<Product>(
                value: selected,
                decoration: const InputDecoration(labelText: 'المنتج'),
                items: products
                    .where((p) => p.id != null)
                    .map((p) => DropdownMenuItem(value: p, child: Text('${p.name} (${p.stock})')))
                    .toList(),
                onChanged: (p) {
                  selected = p;
                  target.text = p?.stock.toString() ?? '';
                  setModal(() {});
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: target,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'الرصيد الصحيح بعد الجرد'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)'),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: selected == null ? null : () => Navigator.pop(ctx, true),
                child: const Text('حفظ التسوية'),
              ),
            ],
          ),
        ),
      ),
    );
    final value = int.tryParse(target.text.trim());
    if (saved == true && selected?.id != null && value != null && value >= 0) {
      try {
        await _service.setStock(selected!.id!, value, notes: note.text.trim().isEmpty ? null : note.text.trim());
        await _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تمت تسوية المخزون وتسجيل الحركة')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$e'), backgroundColor: Colors.red),
          );
        }
      }
    }
    target.dispose();
    note.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('حركة المخزون')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _adjustStock,
        icon: const Icon(Icons.fact_check),
        label: const Text('تسوية مخزون'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _movements.isEmpty
                  ? const ListView(
                      children: [
                        SizedBox(height: 250),
                        Center(child: Text('لا توجد حركات')),
                      ],
                    )
                  : ListView.builder(
                      itemCount: _movements.length,
                      itemBuilder: (_, i) {
                        final m = _movements[i];
                        final incoming = m.type == 'in' || m.type == 'return' || m.type == 'opening';
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Icon(incoming ? Icons.arrow_downward : Icons.arrow_upward),
                            ),
                            title: Text(m.productName ?? 'منتج #${m.productId}'),
                            subtitle: Text(
                              '${_type(m.type)} • ${m.createdAt.substring(0, 16).replaceAll('T', ' ')}',
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('${incoming ? '+' : '-'}${m.quantity}'),
                                Text('${m.previousStock} → ${m.newStock}', style: const TextStyle(fontSize: 11)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
