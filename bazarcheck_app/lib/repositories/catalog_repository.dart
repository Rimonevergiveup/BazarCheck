import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/best_deal.dart';
import '../models/category.dart';
import '../models/division.dart';
import '../models/essential.dart';
import '../models/price_offer.dart';
import '../models/product.dart';
import '../models/product_summary.dart';

/// How search results should be ordered. Values match the `p_sort` argument
/// accepted by the `search_products` RPC.
enum ProductSort {
  relevance('relevance'),
  priceAsc('price_asc'),
  priceDesc('price_desc'),
  name('name'),
  newest('newest');

  final String value;
  const ProductSort(this.value);
}

/// Query parameters for a product search. Immutable so it can be used as a
/// Riverpod family key.
class SearchQuery {
  final String query;
  final String? categoryId;
  final String? divisionId;
  final double? minPrice;
  final double? maxPrice;
  final ProductSort sort;
  final int limit;
  final int offset;

  const SearchQuery({
    this.query = '',
    this.categoryId,
    this.divisionId,
    this.minPrice,
    this.maxPrice,
    this.sort = ProductSort.relevance,
    this.limit = 20,
    this.offset = 0,
  });

  bool get hasFilters =>
      categoryId != null ||
      divisionId != null ||
      minPrice != null ||
      maxPrice != null;

  SearchQuery copyWith({
    String? query,
    Object? categoryId = _unset,
    Object? divisionId = _unset,
    Object? minPrice = _unset,
    Object? maxPrice = _unset,
    ProductSort? sort,
    int? limit,
    int? offset,
  }) {
    return SearchQuery(
      query: query ?? this.query,
      categoryId:
          categoryId == _unset ? this.categoryId : categoryId as String?,
      divisionId:
          divisionId == _unset ? this.divisionId : divisionId as String?,
      minPrice: minPrice == _unset ? this.minPrice : minPrice as double?,
      maxPrice: maxPrice == _unset ? this.maxPrice : maxPrice as double?,
      sort: sort ?? this.sort,
      limit: limit ?? this.limit,
      offset: offset ?? this.offset,
    );
  }

  static const Object _unset = Object();

  @override
  bool operator ==(Object other) =>
      other is SearchQuery &&
      other.query == query &&
      other.categoryId == categoryId &&
      other.divisionId == divisionId &&
      other.minPrice == minPrice &&
      other.maxPrice == maxPrice &&
      other.sort == sort &&
      other.limit == limit &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(
        query, categoryId, divisionId, minPrice, maxPrice, sort, limit, offset,
      );
}

/// A page of search results plus the total count, so the UI can paginate and
/// show "N results" without a second round trip.
class SearchResult {
  final List<ProductSummary> items;
  final int totalCount;

  const SearchResult({required this.items, required this.totalCount});

  bool get isEmpty => items.isEmpty;
  bool hasMore(int offset) => offset + items.length < totalCount;

  static const empty = SearchResult(items: [], totalCount: 0);
}

/// Reads catalogue and price data from Supabase.
///
/// Price-related reads go through Postgres functions (`search_products`,
/// `get_product_offers`, …) rather than client-side joins: the comparison maths
/// happens next to the data, in one round trip, and the same logic is reused by
/// the Python price service.
class CatalogRepository {
  final SupabaseClient supabase;

  CatalogRepository({required this.supabase});

  // --- Search ---------------------------------------------------------------

  /// Bilingual product search with filters, sorting and pagination.
  ///
  /// An empty [SearchQuery.query] means "browse everything", so this powers both
  /// the search screen and category listings.
  Future<SearchResult> searchProducts(SearchQuery q) async {
    final rows = await supabase.rpc('search_products', params: {
      'p_query': q.query.trim().isEmpty ? null : q.query.trim(),
      'p_category': q.categoryId,
      'p_division': q.divisionId,
      'p_min_price': q.minPrice,
      'p_max_price': q.maxPrice,
      'p_sort': q.sort.value,
      'p_limit': q.limit,
      'p_offset': q.offset,
    }) as List<dynamic>;

    final items = rows
        .map((r) => ProductSummary.fromJson(r as Map<String, dynamic>))
        .toList();

    return SearchResult(
      items: items,
      totalCount: items.isEmpty ? 0 : items.first.totalCount,
    );
  }

  /// Every seller's offer for one product, cheapest first.
  Future<List<PriceOffer>> getOffers(String productId) async {
    final rows = await supabase.rpc('get_product_offers', params: {
      'p_product_id': productId,
    }) as List<dynamic>;

    return rows
        .map((r) => PriceOffer.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Products with the biggest gap between cheapest and dearest seller.
  Future<List<BestDeal>> getBestDeals({int limit = 10}) async {
    final rows = await supabase.rpc('get_best_deals', params: {
      'p_limit': limit,
    }) as List<dynamic>;

    return rows
        .map((r) => BestDeal.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  // --- Government rates and regions ----------------------------------------

  /// Rate-controlled staples: official price beside the local market average.
  /// Powers "Daily Essentials" on the home screen and the Compare tab.
  Future<List<Essential>> getEssentials({int limit = 20}) async {
    final rows = await supabase.rpc('get_essentials', params: {
      'p_limit': limit,
    }) as List<dynamic>;

    return rows
        .map((r) => Essential.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Average price per administrative division, cheapest first.
  Future<List<RegionalPrice>> getRegionalPrices(String productId) async {
    final rows = await supabase.rpc('get_regional_prices', params: {
      'p_product_id': productId,
    }) as List<dynamic>;

    return rows
        .map((r) => RegionalPrice.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<Region>> getRegions() async {
    final rows = await supabase
        .from('regions')
        .select('id,name,name_bn,slug')
        .eq('is_active', true)
        .order('name');
    return (rows as List<dynamic>)
        .map((j) => Region.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Daily min/avg/max for a product over the last [days].
  Future<List<PricePoint>> getPriceHistory(String productId,
      {int days = 90}) async {
    final rows = await supabase.rpc('get_price_history', params: {
      'p_product_id': productId,
      'p_days': days,
    }) as List<dynamic>;

    return rows
        .map((r) => PricePoint.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  // --- Catalogue ------------------------------------------------------------

  Future<List<Division>> getDivisions() async {
    final rows = await supabase.from('divisions').select('id,name,description').order('name');
    return (rows as List<dynamic>)
        .map((j) => Division.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<List<Category>> getCategories() async {
    final rows = await supabase
        .from('categories')
        .select('id,name,description,division_id')
        .order('name');
    return (rows as List<dynamic>)
        .map((j) => Category.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<List<Category>> getCategoriesByDivision(String divisionId) async {
    final rows = await supabase
        .from('categories')
        .select('id,name,description,division_id')
        .eq('division_id', divisionId)
        .order('name');
    return (rows as List<dynamic>)
        .map((j) => Category.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Single product row. Used when arriving at a detail screen by id (e.g.
  /// from a favourite) rather than from a list that already has the data.
  Future<Product?> getProduct(String id) async {
    final row = await supabase
        .from('products')
        .select('id,name,name_bn,brand,description,price,image_url,unit,category_id,updated_at')
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    return Product.fromJson(row);
  }

  // --- Favourites (requires a signed-in user) --------------------------------

  Future<Set<String>> getFavoriteIds(String userId) async {
    final rows = await supabase
        .from('favorites')
        .select('product_id')
        .eq('user_id', userId);
    return (rows as List<dynamic>)
        .map((r) => (r as Map<String, dynamic>)['product_id'].toString())
        .toSet();
  }

  /// Favourited products with their live price summary, most recently saved
  /// first.
  ///
  /// Goes through the `get_favorite_products` RPC rather than fetching a page
  /// of products and filtering client-side — the old approach only looked at
  /// the first 100 products, so a favourite ranked 101st silently disappeared.
  /// The RPC scopes on `auth.uid()` server-side, so it cannot return anyone
  /// else's favourites.
  Future<List<ProductSummary>> getFavorites({int limit = 100, int offset = 0}) async {
    final rows = await supabase.rpc('get_favorite_products', params: {
      'p_limit': limit,
      'p_offset': offset,
    }) as List<dynamic>;

    return rows
        .map((r) => ProductSummary.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> addFavorite(String userId, String productId) async {
    await supabase.from('favorites').upsert(
      {'user_id': userId, 'product_id': productId},
      onConflict: 'user_id,product_id',
    );
  }

  Future<void> removeFavorite(String userId, String productId) async {
    await supabase
        .from('favorites')
        .delete()
        .eq('user_id', userId)
        .eq('product_id', productId);
  }
}
