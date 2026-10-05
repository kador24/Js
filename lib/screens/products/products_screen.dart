import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../../models/product.dart';
import '../../services/product_service.dart';
import '../../services/category_service.dart';
import '../../theme/app_theme.dart';
import 'product_form_screen.dart';
import '../barcode/barcode_scanner_screen.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _searchController = TextEditingController();
  final _productService = ProductService();
  List<Product> _products = [];
  bool _loading = true;
  int? _filterCategory;

  @override
  void initState() {
    super.initState();
    _load();
    context.read<AppProvider>().loadCategories();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _products = await _productService.getAll(
      search: _searchController.text.isEmpty ? null : _searchController.text,
      categoryId: _filterCategory,
    );
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final categories = app.categories;

    return Scaffold(
      appBar: AppBar(
        title: const Text('المنتجات'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
              );
              if (result != null && mounted) {
                final product = await _productService.getByBarcode(result);
                if (product != null) {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ProductFormScreen(product: product),
                  )).then((_) => _load());
                } else {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ProductFormScreen(initialBarcode: result),
                  )).then((_) => _load());
                }
              }
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(
            builder: (_) => const ProductFormScreen(),
          ));
          _load();
        },
        icon: const Icon(Icons.add),
        label: const Text('إضافة منتج'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'بحث بالاسم أو الباركود...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear), onPressed: () {
                        _searchController.clear();
                        _load();
                      })
                    : null,
              ),
              onChanged: (_) => _load(),
            ),
          ),
          if (categories.isNotEmpty)
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  FilterChip(
                    label: const Text('الكل'),
                    selected: _filterCategory == null,
                    onSelected: (_) {
                      setState(() => _filterCategory = null);
                      _load();
                    },
                  ),
                  const SizedBox(width: 8),
                  ...categories.map((c) => Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: FilterChip(
                      label: Text(c.nameAr),
                      selected: _filterCategory == c.id,
                      onSelected: (_) {
                        setState(() => _filterCategory = c.id);
                        _load();
                      },
                    ),
                  )),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _products.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text('لا توجد منتجات', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _products.length,
                        itemBuilder: (context, i) {
                          final p = _products[i];
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: p.isLowStock
                                    ? AppTheme.dangerColor.withOpacity(0.2)
                                    : AppTheme.successColor.withOpacity(0.2),
                                child: Text(
                                  '${p.stock}',
                                  style: TextStyle(
                                    color: p.isLowStock ? AppTheme.dangerColor : AppTheme.successColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                [
                                  if (p.brand != null) p.brand!,
                                  if (p.categoryName != null) p.categoryName!,
                                  if (p.barcode != null) p.barcode!,
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(app.formatMoney(p.sellPrice), style: const TextStyle(fontWeight: FontWeight.bold)),
                                  Text('تكلفة: ${app.formatMoney(p.costPrice)}', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                                ],
                              ),
                              onTap: () async {
                                await Navigator.push(context, MaterialPageRoute(
                                  builder: (_) => ProductFormScreen(product: p),
                                ));
                                _load();
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
