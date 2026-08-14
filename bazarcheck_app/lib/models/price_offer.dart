import '../core/formatters.dart';

/// One seller's offer for a product — a row from the `get_product_offers` RPC.
///
/// This is the unit of price comparison: the product detail screen renders a
/// list of these, cheapest first.
class PriceOffer {
  final String priceId;
  final String sellerId;
  final String sellerName;
  final String? sellerNameBn;
  final String? sellerType;
  final String? sellerLogo;
  final String? location;
  final double? rating;

  final double price;
  final String currency;
  final String? unit;
  final double unitQty;
  final bool inStock;
  final String? productUrl;

  /// Where this price came from: manual | scrape | api | import | user.
  final String source;

  /// When this price was actually observed. Never hide this from the user.
  final DateTime? collectedAt;

  /// True for the cheapest in-stock offer, computed server-side.
  final bool isCheapest;

  /// How much dearer this offer is than the cheapest, as a percentage.
  final double? pctAboveMin;

  const PriceOffer({
    required this.priceId,
    required this.sellerId,
    required this.sellerName,
    this.sellerNameBn,
    this.sellerType,
    this.sellerLogo,
    this.location,
    this.rating,
    required this.price,
    this.currency = 'BDT',
    this.unit,
    this.unitQty = 1,
    this.inStock = true,
    this.productUrl,
    this.source = 'manual',
    this.collectedAt,
    this.isCheapest = false,
    this.pctAboveMin,
  });

  factory PriceOffer.fromJson(Map<String, dynamic> json) {
    return PriceOffer(
      priceId: (json['price_id'] ?? '').toString(),
      sellerId: (json['seller_id'] ?? '').toString(),
      sellerName: (json['seller_name'] as String?) ?? '',
      sellerNameBn: _str(json['seller_name_bn']),
      sellerType: _str(json['seller_type']),
      sellerLogo: _str(json['seller_logo']),
      location: _str(json['location']),
      rating: _num(json['rating']),
      price: _num(json['price']) ?? 0,
      currency: (json['currency'] as String?)?.trim() ?? 'BDT',
      unit: _str(json['unit']),
      unitQty: _num(json['unit_qty']) ?? 1,
      inStock: json['in_stock'] as bool? ?? true,
      productUrl: _str(json['product_url']),
      source: (json['source'] as String?) ?? 'manual',
      collectedAt: _date(json['collected_at']),
      isCheapest: json['is_cheapest'] as bool? ?? false,
      pctAboveMin: _num(json['pct_above_min']),
    );
  }

  Freshness get freshness => Freshness.of(collectedAt);

  /// Price normalised to one unit, so 5kg at ৳400 compares fairly against
  /// 1kg at ৳85.
  double? get pricePerUnit => unitQty > 0 ? price / unitQty : null;

  String displaySellerName({required bool bangla}) {
    if (bangla && sellerNameBn != null && sellerNameBn!.trim().isNotEmpty) {
      return sellerNameBn!;
    }
    return sellerName;
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
