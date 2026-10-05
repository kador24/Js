class Category {
  final int? id;
  final String nameAr;
  final String? nameEn;
  final String? icon;
  final String? color;
  final String createdAt;

  Category({
    this.id,
    required this.nameAr,
    this.nameEn,
    this.icon,
    this.color,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name_ar': nameAr,
      'name_en': nameEn,
      'icon': icon,
      'color': color,
      'created_at': createdAt,
    };
  }

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'] as int?,
      nameAr: map['name_ar'] as String,
      nameEn: map['name_en'] as String?,
      icon: map['icon'] as String?,
      color: map['color'] as String?,
      createdAt: map['created_at'] as String,
    );
  }
}
