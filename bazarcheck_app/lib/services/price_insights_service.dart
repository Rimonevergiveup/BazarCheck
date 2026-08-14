import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// Statistical read on a product's prices, from the Python price service.
///
/// Every field here is derived from real rows in the `prices` and
/// `price_history` tables. Nothing is invented — the previous AI service
/// returned the same hardcoded "excellent camera, 95% confidence" blob for
/// every product, including clothing.
class PriceInsight {
  final String productId;
  final int sellerCount;

  /// Cheapest current in-stock price.
  final double? cheapest;

  /// Mean of current in-stock prices.
  final double? average;

  /// Median — more honest than the mean when one seller is a wild outlier.
  final double? median;

  /// Spread between cheapest and dearest, as a percentage of the dearest.
  final double? spreadPercent;

  /// 'falling' | 'rising' | 'stable' | 'unknown', from price_history.
  final String trend;

  /// Change vs the average over the comparison window, as a percentage.
  final double? trendPercent;

  /// True when the cheapest price is at or near its recorded low.
  final bool isGoodTimeToBuy;

  /// Sellers whose price has not been re-checked recently.
  final int staleSellerCount;

  /// Age in hours of the freshest price. Null when there are no prices.
  final double? freshestHours;

  /// Plain-language notes, already localisable on the server side.
  final List<String> notes;

  const PriceInsight({
    required this.productId,
    this.sellerCount = 0,
    this.cheapest,
    this.average,
    this.median,
    this.spreadPercent,
    this.trend = 'unknown',
    this.trendPercent,
    this.isGoodTimeToBuy = false,
    this.staleSellerCount = 0,
    this.freshestHours,
    this.notes = const [],
  });

  factory PriceInsight.fromJson(Map<String, dynamic> json) {
    return PriceInsight(
      productId: (json['product_id'] ?? '').toString(),
      sellerCount: _int(json['seller_count']) ?? 0,
      cheapest: _num(json['cheapest']),
      average: _num(json['average']),
      median: _num(json['median']),
      spreadPercent: _num(json['spread_percent']),
      trend: (json['trend'] ?? 'unknown').toString(),
      trendPercent: _num(json['trend_percent']),
      isGoodTimeToBuy: json['is_good_time_to_buy'] as bool? ?? false,
      staleSellerCount: _int(json['stale_seller_count']) ?? 0,
      freshestHours: _num(json['freshest_hours']),
      notes: (json['notes'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }

  bool get isFalling => trend == 'falling';
  bool get isRising => trend == 'rising';

  static double? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int? _int(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }
}

/// Client for the Python price service (`ai_service/main.py`).
///
/// Every call is optional: the app is fully usable when this service is down,
/// because all the price comparison itself happens in Postgres. This service
/// only adds analysis on top.
class PriceInsightsService {
  final http.Client _client;
  final Duration timeout;

  PriceInsightsService({http.Client? client, this.timeout = const Duration(seconds: 8)})
      : _client = client ?? http.Client();

  String get _base => AppConfig.priceServiceBaseUrl;

  /// Returns null rather than throwing when the service is unreachable —
  /// insights are a bonus, not a dependency.
  Future<PriceInsight?> getInsight(String productId, {String? accessToken}) async {
    try {
      final res = await _client
          .get(
            Uri.parse('$_base/api/v1/products/$productId/insights'),
            headers: {
              'Accept': 'application/json',
              if (accessToken != null) 'Authorization': 'Bearer $accessToken',
            },
          )
          .timeout(timeout);

      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return PriceInsight.fromJson(body);
    } catch (_) {
      return null;
    }
  }

  Future<bool> isHealthy() async {
    try {
      final res =
          await _client.get(Uri.parse('$_base/health')).timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void dispose() => _client.close();
}
