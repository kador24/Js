import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../../models/product.dart';
import '../../services/barcode_lookup_service.dart';
import '../../providers/app_provider.dart';
import '../barcode/barcode_scanner_screen.dart';

class ProductFormScreen extends StatefulWidget {
  final Product? product;
  final String? initialBarcode;
  const ProductFormScreen({super.key, this.product, this.initialBarcode});

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _brand = TextEditingController();
  final _barcode = TextEditingController();
  final _sell = TextEditingController();
  final _cost = TextEditingController();
  final _stock = TextEditingController();
  final _minStock = TextEditingController(text: '5');
  final _warranty = TextEditingController();
  final _description = TextEditingController();
  final _attributes = TextEditingController();
  final _lookupService = BarcodeLookupService();
  final _picker = ImagePicker();
  int? _categoryId;
  String? _imagePath;
  String? _newImagePath;
  bool _saved = false;
  bool _saving = false;
  bool _lookingUp = false;

  @override
  void initState() {
    super.initState();
    final item = widget.product;
    if (item != null) {
      _name.text = item.name;
      _brand.text = item.brand ?? '';
      _barcode.text = item.barcode ?? '';
      _sell.text = item.sellPrice.toStringAsFixed(0);
      _cost.text = item.costPrice.toStringAsFixed(0);
      _stock.text = item.stock.toString();
      _minStock.text = item.minStock.toString();
      _warranty.text = item.warranty ?? '';
      _description.text = item.description ?? '';
      _attributes.text = item.attributes ?? '';
      _categoryId = item.categoryId;
      _imagePath = item.imagePath;
    } else {
      _stock.text = '0';
      if (widget.initialBarcode != null) _barcode.text = widget.initialBarcode!;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<AppProvider>().loadCategories());
  }

  Future<void> _scan() async {
    final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()));
    if (code != null && mounted) {
      setState(() => _barcode.text = code);
      await _lookupBarcode(showMessage: true);
    }
  }

  Future<void> _lookupBarcode({bool showMessage = false}) async {
    final code = _barcode.text.trim();
    if (code.isEmpty) return;
    setState(() => _lookingUp = true);
    final suggestion = await _lookupService.lookup(code);
    if (!mounted) return;
    setState(() => _lookingUp = false);
    if (suggestion == null) {
      if (showMessage) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لم نجد بيانات عامة لهذا الباركود؛ أكمل يدويًا')));
      return;
    }
    if (_name.text.trim().isEmpty && suggestion.name != null) _name.text = suggestion.name!;
    if (_brand.text.trim().isEmpty && suggestion.brand != null) _brand.text = suggestion.brand!;
    if (_description.text.trim().isEmpty && suggestion.description != null) _description.text = suggestion.description!;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم ملء البيانات المتاحة من البحث الخارجي')));
  }

  Future<void> _pickImage() async {
    final image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 88, maxWidth: 1600);
    if (image == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final targetDir = Directory(p.join(dir.path, 'product_images'));
    await targetDir.create(recursive: true);
    final fileName = 'product_${DateTime.now().millisecondsSinceEpoch}${p.extension(image.path)}';
    final saved = await File(image.path).copy(p.join(targetDir.path, fileName));
    if (_newImagePath != null && _newImagePath != widget.product?.imagePath) {
      try { await File(_newImagePath!).delete(); } catch (_) {}
    }
    if (mounted) setState(() { _imagePath = saved.path; _newImagePath = saved.path; });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final now = DateTime.now().toIso8601String();
      final product = Product(
        id: widget.product?.id,
        name: _name.text.trim(),
        categoryId: _categoryId,
        brand: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
        barcode: _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
        sellPrice: double.tryParse(_sell.text.trim()) ?? 0,
        costPrice: double.tryParse(_cost.text.trim()) ?? 0,
        stock: widget.product == null ? int.tryParse(_stock.text.trim()) ?? 0 : widget.product!.stock,
        minStock: int.tryParse(_minStock.text.trim()) ?? 5,
        warranty: _warranty.text.trim().isEmpty ? null : _warranty.text.trim(),
        description: _description.text.trim().isEmpty ? null : _description.text.trim(),
        imagePath: _imagePath,
        attributes: _attributes.text.trim().isEmpty ? null : _attributes.text.trim(),
        createdAt: widget.product?.createdAt ?? now,
        updatedAt: now,
      );
      if (widget.product == null) {
        await context.read<AppProvider>().productsService.insert(product);
      } else {
        await context.read<AppProvider>().productsService.update(product);
      }
      _saved = true;
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (widget.product?.id == null) return;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('تعطيل المنتج'),
      content: const Text('سيختفي من المبيعات والقائمة، مع الحفاظ على سجله التاريخي.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تعطيل')),
      ],
    ));
    if (ok == true) {
      await context.read<AppProvider>().productsService.delete(widget.product!.id!);
      if (mounted) Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = context.watch<AppProvider>().categories;
    final edit = widget.product != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(edit ? 'تعديل منتج' : 'إضافة منتج'),
        actions: [if (edit) IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline))],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                height: 170,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: Theme.of(context).dividerColor)),
                clipBehavior: Clip.antiAlias,
                child: _imagePath != null && File(_imagePath!).existsSync()
                    ? Image.file(File(_imagePath!), fit: BoxFit.cover)
                    : const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add_a_photo, size: 42), SizedBox(height: 8), Text('صورة المنتج')])),
              ),
            ),
            if (_imagePath != null) Align(alignment: AlignmentDirectional.centerEnd, child: TextButton.icon(onPressed: () async { final old = _imagePath; setState(() => _imagePath = null); if (_newImagePath == old && old != widget.product?.imagePath) { try { await File(old!).delete(); } catch (_) {} } }, icon: const Icon(Icons.delete_outline), label: const Text('إزالة الصورة'))),
            const SizedBox(height: 8),
            TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'اسم المنتج *', prefixIcon: Icon(Icons.label)), validator: (v) => v == null || v.trim().isEmpty ? 'اسم المنتج مطلوب' : null),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _categoryId,
              decoration: const InputDecoration(labelText: 'التصنيف', prefixIcon: Icon(Icons.category)),
              items: categories.where((c) => c.id != null).map((c) => DropdownMenuItem(value: c.id, child: Text(c.nameAr))).toList(),
              onChanged: (v) => setState(() => _categoryId = v),
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _brand, decoration: const InputDecoration(labelText: 'الماركة', prefixIcon: Icon(Icons.branding_watermark))),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextFormField(controller: _barcode, decoration: const InputDecoration(labelText: 'الباركود', prefixIcon: Icon(Icons.qr_code)))),
              const SizedBox(width: 8),
              IconButton.filledTonal(onPressed: _scan, icon: const Icon(Icons.qr_code_scanner)),
              IconButton.filledTonal(onPressed: _lookingUp ? null : () => _lookupBarcode(showMessage: true), icon: _lookingUp ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.travel_explore)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextFormField(controller: _sell, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'سعر البيع *'), validator: (v) => double.tryParse(v ?? '') == null ? 'أدخل رقمًا صحيحًا' : null)),
              const SizedBox(width: 12),
              Expanded(child: TextFormField(controller: _cost, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'تكلفة الشراء'), validator: (v) => double.tryParse(v ?? '') == null ? 'أدخل رقمًا صحيحًا' : null)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextFormField(controller: _stock, readOnly: edit, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: edit ? 'المخزون الحالي' : 'الرصيد الافتتاحي', helperText: edit ? 'التعديل من المشتريات أو حركة المخزون' : 'سيسجل كحركة افتتاحية'))),
              const SizedBox(width: 12),
              Expanded(child: TextFormField(controller: _minStock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'حد التنبيه'))),
            ]),
            const SizedBox(height: 12),
            TextFormField(controller: _warranty, decoration: const InputDecoration(labelText: 'الضمان', prefixIcon: Icon(Icons.verified_user))),
            const SizedBox(height: 12),
            TextFormField(controller: _attributes, maxLines: 4, decoration: const InputDecoration(labelText: 'خصائص إضافية', hintText: 'مثال: RAM: 8GB\nStorage: 256GB\nColor: Black\nIMEI: ...', prefixIcon: Icon(Icons.tune))),
            const SizedBox(height: 12),
            TextFormField(controller: _description, maxLines: 3, decoration: const InputDecoration(labelText: 'الوصف', prefixIcon: Icon(Icons.description))),
            const SizedBox(height: 24),
            FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save), label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ المنتج')),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    if (!_saved && _newImagePath != null && _newImagePath != widget.product?.imagePath) {
      File(_newImagePath!).delete();
    }
    _name.dispose(); _brand.dispose(); _barcode.dispose(); _sell.dispose(); _cost.dispose(); _stock.dispose(); _minStock.dispose(); _warranty.dispose(); _description.dispose(); _attributes.dispose();
    super.dispose();
  }
}
