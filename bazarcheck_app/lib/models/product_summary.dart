import '../core/formatters.dart';

/// One row from the `search_products` RPC.
///
/// This is the list-view model: it carries the *price summary* (cheapest,
/// dearest, how many sellers, when last checked) rather than a single price,
/// which is what makes a comparison card possible.
class ProductSummary {
  final String id;
  final String name;
  final String? nameBn;
  final String? brand;
  final String? description;
  final String? imageUrl;
  final String? unit;
  final String? categoryId;
  final String? categoryName;

  /// Cheapest in-stock price. Null when no seller has listed one.
  final double? minPrice;

  /// Dearest in-stock price. Null when no seller has listed one.
  final double? maxPrice;

  /// How many sellers currently have this in stock.
  final int sellerCount;

  /// When the most recent of those prices was collected.
  final DateTime? lastUpdated;

  /// Total matching rows for the query, used for pagination.
  final int totalCount;

  const ProductSummary({
    required this.id,
    required this.name,
    this.nameBn,
    this.brand,
    this.description,
    this.imageUrl,
    this.unit,
    this.categoryId,
    this.categoryName,
    this.minPrice,
    this.maxPrice,
    this.sellerCount = 0,
    this.lastUpdated,
    this.totalCount = 0,
  });

  factory ProductSummary.fromJson(Map<String, dynamic> json) {
    return ProductSummary(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      nameBn: _str(json['name_bn']),
      brand: _str(json['brand']),
      description: _str(json['description']),
      imageUrl: _str(json['image_url']),
      unit: _str(json['unit']),
      categoryId: _str(json['category_id']),
      categoryName: _str(json['category_name']),
      minPrice: _num(json['min_price']),
      maxPrice: _num(json['max_price']),
      sellerCount: _int(json['seller_count']) ?? 0,
      lastUpdated: _date(json['last_updated']),
      totalCount: _int(json['total_count']) ?? 0,
    );
  }

  /// True when at least one seller has a price. Drives whether the card shows
  /// a price or an honest "price unavailable".
  bool get hasPrice => minPrice != null;

  /// True when different sellers charge different amounts — i.e. there is
  /// actually something to compare.
  bool get hasSpread =>
      minPrice != null && maxPrice != null && maxPrice! > minPrice!;

  /// Absolute saving between the dearest and cheapest seller.
  double? get savings => hasSpread ? maxPrice! - minPrice! : null;

  /// Saving as a percentage of the dearest price.
  double? get savingsPercent {
    if (!hasSpread || maxPrice == 0) return null;
    return ((maxPrice! - minPrice!) / maxPrice!) * 100;
  }

  Freshness get freshness => Freshness.of(lastUpdated);

  /// Name in the reader's language, falling back to whichever exists.
  String displayName({required bool bangla}) {
    if (bangla && nameBn != null && nameBn!.trim().isNotEmpty) return nameBn!;
    return name;
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

  static int? _int(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static DateTime? _date(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toLocal();
    return DateTime.tryParse(v.toString())?.toLocal();
  }
}
