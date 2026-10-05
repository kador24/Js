class Product {
  final int? id;
  final String name;
  final int? categoryId;
  final String? brand;
  final String? barcode;
  final double sellPrice;
  final double costPrice;
  final int stock;
  final int minStock;
  final String? warranty;
  final String? description;
  final String? imagePath;
  final String? attributes;
  final bool isActive;
  final String createdAt;
  final String updatedAt;

  // Joined
  final String? categoryName;

  Product({
    this.id,
    required this.name,
    this.categoryId,
    this.brand,
    this.barcode,
    required this.sellPrice,
    required this.costPrice,
    this.stock = 0,
    this.minStock = 5,
    this.warranty,
    this.description,
    this.imagePath,
    this.attributes,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    this.categoryName,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'category_id': categoryId,
      'brand': brand,
      'barcode': barcode,
      'sell_price': sellPrice,
      'cost_price': costPrice,
      'stock': stock,
      'min_stock': minStock,
      'warranty': warranty,
      'description': description,
      'image_path': imagePath,
      'attributes': attributes,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] as int?,
      name: map['name'] as String,
      categoryId: map['category_id'] as int?,
      brand: map['brand'] as String?,
      barcode: map['barcode'] as String?,
      sellPrice: (map['sell_price'] as num).toDouble(),
      costPrice: (map['cost_price'] as num).toDouble(),
      stock: map['stock'] as int? ?? 0,
      minStock: map['min_stock'] as int? ?? 5,
      warranty: map['warranty'] as String?,
      description: map['description'] as String?,
      imagePath: map['image_path'] as String?,
      attributes: map['attributes'] as String?,
      isActive: (map['is_active'] as int? ?? 1) == 1,
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String,
      categoryName: map['category_name'] as String?,
    );
  }

  Product copyWith({
    int? id,
    String? name,
    int? categoryId,
    String? brand,
    String? barcode,
    double? sellPrice,
    double? costPrice,
    int? stock,
    int? minStock,
    String? warranty,
    String? description,
    String? imagePath,
    String? attributes,
    bool? isActive,
    String? createdAt,
    String? updatedAt,
    String? categoryName,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      categoryId: categoryId ?? this.categoryId,
      brand: brand ?? this.brand,
      barcode: barcode ?? this.barcode,
      sellPrice: sellPrice ?? this.sellPrice,
      costPrice: costPrice ?? this.costPrice,
      stock: stock ?? this.stock,
      minStock: minStock ?? this.minStock,
      warranty: warranty ?? this.warranty,
      description: description ?? this.description,
      imagePath: imagePath ?? this.imagePath,
      attributes: attributes ?? this.attributes,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      categoryName: categoryName ?? this.categoryName,
    );
  }

  double get profitMargin => sellPrice > 0 ? ((sellPrice - costPrice) / sellPrice * 100) : 0;
  bool get isLowStock => stock <= minStock;
}
