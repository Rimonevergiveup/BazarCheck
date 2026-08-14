import '../core/formatters.dart';

/// How the local market price compares with the official government rate.
enum PriceStatus {
  /// More than 10% above the official rate.
  spike,

  /// Within 10% above.
  stable,

  /// At or below the official rate.
  drop,

  /// No official rate, or no local price to compare against.
  unknown;

  static PriceStatus parse(String? v) => switch (v) {
        'spike' => PriceStatus.spike,
        'stable' => PriceStatus.stable,
        'drop' => PriceStatus.drop,
        _ => PriceStatus.unknown,
      };

  bool get isKnown => this != PriceStatus.unknown;
}

/// A rate-controlled staple: the official price beside what shops actually
/// charge. One row from the `get_essentials` RPC.
///
/// Both prices are nullable and stay that way. Most products have no official
/// rate, and showing an invented one would be worse than showing none.
class Essential {
  final String id;
  final String name;
  final String? nameBn;
  final String? imageUrl;
  final String? unit;

  /// Officially published rate (TCB / DNCRP). Null when not rate-controlled.
  final double? govtFixedPrice;

  /// Mean of current in-stock local prices.
  final double? localAvgPrice;

  /// Cheapest current local price.
  final double? localMinPrice;

  /// localAvg − govtFixed. Positive means shops charge over the official rate.
  final double? priceGap;

  /// The same gap as a percentage of the official rate.
  final double? gapPercent;

  final PriceStatus status;
  final int sellerCount;
  final DateTime? lastUpdated;

  const Essential({
    required this.id,
    required this.name,
    this.nameBn,
    this.imageUrl,
    this.unit,
    this.govtFixedPrice,
    this.localAvgPrice,
    this.localMinPrice,
    this.priceGap,
    this.gapPercent,
    this.status = PriceStatus.unknown,
    this.sellerCount = 0,
    this.lastUpdated,
  });

  factory Essential.fromJson(Map<String, dynamic> json) {
    return Essential(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      nameBn: _str(json['name_bn']),
      imageUrl: _str(json['image_url']),
      unit: _str(json['unit']),
      govtFixedPrice: _num(json['govt_fixed_price']),
      localAvgPrice: _num(json['local_avg_price']),
      localMinPrice: _num(json['local_min_price']),
      priceGap: _num(json['price_gap']),
      gapPercent: _num(json['gap_percent']),
      status: PriceStatus.parse(json['status'] as String?),
      sellerCount: (_num(json['seller_count']) ?? 0).toInt(),
      lastUpdated: _date(json['last_updated']),
    );
  }

  bool get hasGovtPrice => govtFixedPrice != null;
  bool get hasLocalPrice => localAvgPrice != null;

  /// True when both figures exist, so a gap can honestly be shown.
  bool get hasComparison => hasGovtPrice && hasLocalPrice;

  /// True when shops charge more than the official rate.
  bool get isOverGovtRate => (priceGap ?? 0) > 0;

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

/// One row of the regional price table on the product page.
class RegionalPrice {
  final String regionId;
  final String regionName;
  final String? regionNameBn;
  final double? avgPrice;
  final double? minPrice;
  final int sellerCount;
  final DateTime? lastUpdated;

  /// Change against the average a week ago. Null when there is no history.
  final double? trendPercent;

  const RegionalPrice({
    required this.regionId,
    required this.regionName,
    this.regionNameBn,
    this.avgPrice,
    this.minPrice,
    this.sellerCount = 0,
    this.lastUpdated,
    this.trendPercent,
  });

  factory RegionalPrice.fromJson(Map<String, dynamic> json) {
    return RegionalPrice(
      regionId: (json['region_id'] ?? '').toString(),
      regionName: (json['region_name'] as String?) ?? '',
      regionNameBn: Essential._str(json['region_name_bn']),
      avgPrice: Essential._num(json['avg_price']),
      minPrice: Essential._num(json['min_price']),
      sellerCount: (Essential._num(json['seller_count']) ?? 0).toInt(),
      lastUpdated: Essential._date(json['last_updated']),
      trendPercent: Essential._num(json['trend_percent']),
    );
  }

  bool get isRising => (trendPercent ?? 0) > 0.5;
  bool get isFalling => (trendPercent ?? 0) < -0.5;

  String displayName({required bool bangla}) {
    if (bangla && regionNameBn != null && regionNameBn!.trim().isNotEmpty) {
      return regionNameBn!;
    }
    return regionName;
  }
}

/// A Bangladesh administrative division, used for the region picker.
class Region {
  final String id;
  final String name;
  final String? nameBn;
  final String slug;

  const Region({
    required this.id,
    required this.name,
    this.nameBn,
    required this.slug,
  });

  factory Region.fromJson(Map<String, dynamic> json) => Region(
        id: json['id'] as String,
        name: (json['name'] as String?) ?? '',
        nameBn: Essential._str(json['name_bn']),
        slug: (json['slug'] as String?) ?? '',
      );

  String displayName({required bool bangla}) {
    if (bangla && nameBn != null && nameBn!.trim().isNotEmpty) return nameBn!;
    return name;
  }
}
