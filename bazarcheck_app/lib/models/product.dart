/// A single product row.
///
/// Note: [price] is deliberately **nullable**. The original model coerced a
/// missing price to `0.0`, which rendered as a confident `৳0` — indistinguishable
/// from "this item is free". Null now means "no price", and the UI is required
/// to say so.
///
/// For anything price-facing prefer [ProductSummary] (from the `search_products`
/// RPC), which carries the full multi-seller price summary. This model is for
/// the plain catalogue rows.
class Product {
  final String id;
  final String name;
  final String? nameBn;
  final String? brand;
  final String description;

  /// Legacy single price. Superseded by the `prices` table; kept because the
  /// column still exists and older rows may only have this.
  final double? price;

  final String? imageUrl;
  final String? unit;
  final String categoryId;
  final DateTime? updatedAt;

  const Product({
    required this.id,
    required this.name,
    this.nameBn,
    this.brand,
    this.description = '',
    this.price,
    this.imageUrl,
    this.unit,
    this.categoryId = '',
    this.updatedAt,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      nameBn: _str(json['name_bn']),
      brand: _str(json['brand']),
      description: (json['description'] as String?) ?? '',
      price: _num(json['price']), // null stays null — never 0.0
      imageUrl: _str(json['image_url']),
      unit: _str(json['unit']),
      categoryId: (json['category_id'] as String?) ?? '',
      updatedAt: _date(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'name_bn': nameBn,
        'brand': brand,
        'description': description,
        'price': price,
        'image_url': imageUrl,
        'unit': unit,
        'category_id': categoryId,
      };

  bool get hasPrice => price != null;

  String displayName({required bool bangla}) {
    if (bangla && nameBn != null && nameBn!.trim().isNotEmpty) return nameBn!;
    return name;
  }

  Product copyWith({
    String? id,
    String? name,
    String? nameBn,
    String? brand,
    String? description,
    double? price,
    String? imageUrl,
    String? unit,
    String? categoryId,
    DateTime? updatedAt,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      nameBn: nameBn ?? this.nameBn,
      brand: brand ?? this.brand,
      description: description ?? this.description,
      price: price ?? this.price,
      imageUrl: imageUrl ?? this.imageUrl,
      unit: unit ?? this.unit,
      categoryId: categoryId ?? this.categoryId,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static String? _str(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static double? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static DateTime? _date(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toLocal();
    return DateTime.tryParse(v.toString())?.toLocal();
  }
}
