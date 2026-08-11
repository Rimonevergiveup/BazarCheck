import 'package:bazaedam_app/models/best_deal.dart';
import 'package:bazaedam_app/models/price_offer.dart';
import 'package:bazaedam_app/models/product.dart';
import 'package:bazaedam_app/models/product_summary.dart';
import 'package:bazaedam_app/repositories/catalog_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Product', () {
    test('a null price stays null instead of becoming 0.0', () {
      final p = Product.fromJson({'id': 'a', 'name': 'Rice', 'price': null});
      expect(p.price, isNull);
      expect(p.hasPrice, isFalse);
    });

    test('parses a real price', () {
      final p = Product.fromJson({'id': 'a', 'name': 'Rice', 'price': 72.5});
      expect(p.price, 72.5);
      expect(p.hasPrice, isTrue);
    });

    test('blank strings normalise to null, not empty noise', () {
      final p = Product.fromJson(
          {'id': 'a', 'name': 'Rice', 'brand': '   ', 'image_url': ''});
      expect(p.brand, isNull);
      expect(p.imageUrl, isNull);
    });

    test('falls back to the English name when Bangla is missing', () {
      final p = Product.fromJson({'id': 'a', 'name': 'Rice'});
      expect(p.displayName(bangla: true), 'Rice');
    });

    test('prefers the Bangla name when present', () {
      final p =
          Product.fromJson({'id': 'a', 'name': 'Rice', 'name_bn': 'চাল'});
      expect(p.displayName(bangla: true), 'চাল');
      expect(p.displayName(bangla: false), 'Rice');
    });
  });

  group('ProductSummary', () {
    ProductSummary make({
      double? min,
      double? max,
      int sellers = 0,
      DateTime? updated,
    }) =>
        ProductSummary.fromJson({
          'id': 'p1',
          'name': 'Miniket Rice',
          'name_bn': 'মিনিকেট চাল',
          'min_price': min,
          'max_price': max,
          'seller_count': sellers,
          'last_updated': updated?.toIso8601String(),
          'total_count': 1,
        });

    test('reports no price when no seller has listed one', () {
      final s = make();
      expect(s.hasPrice, isFalse);
      expect(s.savings, isNull);
      expect(s.savingsPercent, isNull);
    });

    test('detects a spread and computes the saving', () {
      final s = make(min: 72, max: 90, sellers: 3);
      expect(s.hasSpread, isTrue);
      expect(s.savings, 18);
      expect(s.savingsPercent, closeTo(20.0, 0.01)); // 18/90
    });

    test('no spread when every seller agrees', () {
      final s = make(min: 80, max: 80, sellers: 3);
      expect(s.hasSpread, isFalse);
      expect(s.savings, isNull);
    });

    test('carries total_count through for pagination', () {
      expect(make(min: 1).totalCount, 1);
    });

    test('parses timestamps into local time', () {
      final s = make(min: 1, updated: DateTime.utc(2026, 8, 10, 6));
      expect(s.lastUpdated, isNotNull);
      expect(s.lastUpdated!.isUtc, isFalse);
    });
  });

  group('PriceOffer', () {
    test('parses the RPC shape including the cheapest flag', () {
      final o = PriceOffer.fromJson({
        'price_id': 'x',
        'seller_id': 's1',
        'seller_name': 'Chaldal',
        'seller_name_bn': 'চালডাল',
        'price': 72.0,
        'currency': 'BDT',
        'unit': 'kg',
        'unit_qty': 1,
        'in_stock': true,
        'is_cheapest': true,
        'pct_above_min': 0,
        'collected_at': '2026-08-11T06:00:00Z',
      });
      expect(o.sellerName, 'Chaldal');
      expect(o.isCheapest, isTrue);
      expect(o.price, 72.0);
      expect(o.displaySellerName(bangla: true), 'চালডাল');
      expect(o.collectedAt, isNotNull);
    });

    test('normalises price per unit so bulk packs compare fairly', () {
      final o = PriceOffer.fromJson({
        'price_id': 'x', 'seller_id': 's', 'seller_name': 'S',
        'price': 400.0, 'unit': 'kg', 'unit_qty': 5,
      });
      expect(o.pricePerUnit, 80.0);
    });

    test('defaults sensibly when optional fields are absent', () {
      final o = PriceOffer.fromJson(
          {'price_id': 'x', 'seller_id': 's', 'seller_name': 'S', 'price': 10});
      expect(o.currency, 'BDT');
      expect(o.inStock, isTrue);
      expect(o.isCheapest, isFalse);
      expect(o.unitQty, 1);
    });
  });

  group('BestDeal', () {
    test('parses savings fields from the RPC', () {
      final d = BestDeal.fromJson({
        'id': 'p1',
        'name': 'Rice',
        'min_price': 72.0,
        'max_price': 85.5,
        'savings': 13.5,
        'savings_pct': 15.8,
        'seller_count': 3,
      });
      expect(d.savings, 13.5);
      expect(d.savingsPercent, 15.8);
      expect(d.sellerCount, 3);
    });
  });

  group('SearchQuery', () {
    test('equal queries are equal, so provider caching works', () {
      const a = SearchQuery(query: 'rice', sort: ProductSort.priceAsc);
      const b = SearchQuery(query: 'rice', sort: ProductSort.priceAsc);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different queries are not equal', () {
      const a = SearchQuery(query: 'rice');
      const b = SearchQuery(query: 'oil');
      expect(a, isNot(equals(b)));
    });

    test('copyWith can clear a nullable filter back to null', () {
      // The usual copyWith(x ?? this.x) idiom cannot express "set to null";
      // the sentinel makes clearing a category possible.
      const withCat = SearchQuery(categoryId: 'abc');
      expect(withCat.copyWith(categoryId: null).categoryId, isNull);
    });

    test('copyWith leaves unmentioned fields untouched', () {
      const q = SearchQuery(categoryId: 'abc', minPrice: 10);
      final next = q.copyWith(query: 'rice');
      expect(next.categoryId, 'abc');
      expect(next.minPrice, 10);
      expect(next.query, 'rice');
    });

    test('hasFilters reflects only real filters, not the text', () {
      expect(const SearchQuery(query: 'rice').hasFilters, isFalse);
      expect(const SearchQuery(minPrice: 10).hasFilters, isTrue);
      expect(const SearchQuery(categoryId: 'x').hasFilters, isTrue);
    });

    test('sort values match the SQL function contract', () {
      expect(ProductSort.priceAsc.value, 'price_asc');
      expect(ProductSort.priceDesc.value, 'price_desc');
      expect(ProductSort.relevance.value, 'relevance');
      expect(ProductSort.newest.value, 'newest');
      expect(ProductSort.name.value, 'name');
    });
  });

  group('SearchResult', () {
    test('knows when more pages remain', () {
      final r = SearchResult(
        items: List.generate(20, (i) => ProductSummary(id: '$i', name: '$i')),
        totalCount: 55,
      );
      expect(r.hasMore(0), isTrue);
      expect(r.hasMore(40), isFalse);
    });
  });
}
