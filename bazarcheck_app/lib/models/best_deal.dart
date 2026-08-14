import '../core/formatters.dart';

/// A row from the `get_best_deals` RPC: products where the gap between the
/// cheapest and dearest seller is largest. This is the home screen's hook —
/// it shows the user, concretely, what comparing is worth.
class BestDeal {
  final String id;
  final String name;
  final String? nameBn;
  final String? imageUrl;
  final String? unit;
  final double minPrice;
  final double maxPrice;
  final double savings;
  final double savingsPercent;
  final int sellerCount;
  final DateTime? lastUpdated;

  const BestDeal({
    required this.id,
    required this.name,
    this.nameBn,
    this.imageUrl,
    this.unit,
    required this.minPrice,
    required this.maxPrice,
    required this.savings,
    required this.savingsPercent,
    required this.sellerCount,
    this.lastUpdated,
  });

  factory BestDeal.fromJson(Map<String, dynamic> json) {
    return BestDeal(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      nameBn: _str(json['name_bn']),
      imageUrl: _str(json['image_url']),
      unit: _str(json['unit']),
      minPrice: _num(json['min_price']) ?? 0,
      maxPrice: _num(json['max_price']) ?? 0,
      savings: _num(json['savings']) ?? 0,
      savingsPercent: _num(json['savings_pct']) ?? 0,
      sellerCount: (_num(json['seller_count']) ?? 0).toInt(),
      lastUpdated: _date(json['last_updated']),
    );
  }

  Freshness get freshness => Freshness.of(lastUpdated);

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

  static DateTime? _date(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toLocal();
    return DateTime.tryParse(v.toString())?.toLocal();
  }
}

/// One day of aggregated price history, from `get_price_history`.
class PricePoint {
  final DateTime day;
  final double minPrice;
  final double avgPrice;
  final double maxPrice;

  const PricePoint({
    required this.day,
    required this.minPrice,
    required this.avgPrice,
    required this.maxPrice,
  });

  factory PricePoint.fromJson(Map<String, dynamic> json) {
    return PricePoint(
      day: DateTime.tryParse((json['day'] ?? '').toString())?.toLocal() ??
          DateTime.now(),
      minPrice: _num(json['min_price']) ?? 0,
      avgPrice: _num(json['avg_price']) ?? 0,
      maxPrice: _num(json['max_price']) ?? 0,
    );
  }

  static double? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}
