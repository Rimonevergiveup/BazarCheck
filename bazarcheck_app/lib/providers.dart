import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/best_deal.dart';
import 'models/category.dart';
import 'models/division.dart';
import 'models/essential.dart';
import 'models/price_offer.dart';
import 'models/product_summary.dart';
import 'repositories/catalog_repository.dart';
import 'services/auth_service.dart';
import 'services/price_insights_service.dart';
import 'supabase_client.dart';

// ---------------------------------------------------------------------------
// Core singletons
// ---------------------------------------------------------------------------

final supabaseProvider = Provider<SupabaseClient>((ref) => supabase);

final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(supabase: ref.watch(supabaseProvider)),
);

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => CatalogRepository(supabase: ref.watch(supabaseProvider)),
);

final priceInsightsServiceProvider = Provider<PriceInsightsService>((ref) {
  final service = PriceInsightsService();
  ref.onDispose(service.dispose);
  return service;
});

/// Overridden in `main()` once SharedPreferences has loaded.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider not overridden'),
);

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

/// Emits the signed-in user, or null when browsing anonymously.
///
/// Seeded with the current session so the very first frame already knows
/// whether someone is signed in — no flash of the logged-out state.
final authStateProvider = StreamProvider<User?>((ref) {
  final client = ref.watch(supabaseProvider);
  return client.auth.onAuthStateChange
      .map((event) => event.session?.user)
      .distinct();
});

/// Convenience: the current user, or null. Never throws, never suspends.
final currentUserProvider = Provider<User?>((ref) {
  final async = ref.watch(authStateProvider);
  return async.valueOrNull ?? ref.watch(supabaseProvider).auth.currentUser;
});

final isSignedInProvider = Provider<bool>((ref) => ref.watch(currentUserProvider) != null);

/// Tracks whether an unauthenticated user has elected to browse as a guest.
final guestModeProvider = StateProvider<bool>((ref) => false);

// ---------------------------------------------------------------------------
// Settings: language + theme, persisted across launches
// ---------------------------------------------------------------------------

@immutable
class AppSettings {
  final Locale locale;
  final ThemeMode themeMode;

  const AppSettings({
    this.locale = const Locale('en'),
    this.themeMode = ThemeMode.system,
  });

  bool get isBangla => locale.languageCode == 'bn';

  AppSettings copyWith({Locale? locale, ThemeMode? themeMode}) => AppSettings(
        locale: locale ?? this.locale,
        themeMode: themeMode ?? this.themeMode,
      );
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  static const _kLocale = 'settings.locale';
  static const _kTheme = 'settings.themeMode';

  final SharedPreferences _prefs;

  SettingsNotifier(this._prefs) : super(const AppSettings()) {
    _load();
  }

  void _load() {
    final lang = _prefs.getString(_kLocale);
    final theme = _prefs.getString(_kTheme);
    state = AppSettings(
      locale: Locale(lang == 'bn' ? 'bn' : 'en'),
      themeMode: switch (theme) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
    );
  }

  Future<void> setLocale(Locale locale) async {
    state = state.copyWith(locale: locale);
    await _prefs.setString(_kLocale, locale.languageCode);
  }

  Future<void> toggleLanguage() =>
      setLocale(Locale(state.isBangla ? 'en' : 'bn'));

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _prefs.setString(_kTheme, mode.name);
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier(ref.watch(sharedPreferencesProvider));
});

/// Shorthand used all over the UI for digit/wording selection.
final isBanglaProvider =
    Provider<bool>((ref) => ref.watch(settingsProvider).isBangla);

// ---------------------------------------------------------------------------
// Catalogue
// ---------------------------------------------------------------------------

final divisionsProvider = FutureProvider<List<Division>>((ref) {
  return ref.watch(catalogRepositoryProvider).getDivisions();
});

final categoriesProvider = FutureProvider<List<Category>>((ref) {
  return ref.watch(catalogRepositoryProvider).getCategories();
});

final categoriesByDivisionProvider =
    FutureProvider.family<List<Category>, String>((ref, divisionId) {
  return ref.watch(catalogRepositoryProvider).getCategoriesByDivision(divisionId);
});

// ---------------------------------------------------------------------------
// Search
// ---------------------------------------------------------------------------

/// Search text, debounced.
///
/// The UI calls [SearchTextNotifier.update] on every keystroke; the exposed
/// state only changes once typing pauses for 350ms. That turns "chaldal" into
/// one query instead of seven.
class SearchTextNotifier extends StateNotifier<String> {
  static const _debounce = Duration(milliseconds: 350);

  SearchTextNotifier() : super('');

  Timer? _timer;

  void update(String text) {
    _timer?.cancel();
    if (text.trim().isEmpty) {
      state = ''; // clearing should feel instant
      return;
    }
    _timer = Timer(_debounce, () {
      if (mounted) state = text;
    });
  }

  /// Skip the debounce — used when the user presses enter or taps a suggestion.
  void submit(String text) {
    _timer?.cancel();
    if (mounted) state = text;
  }

  void clear() {
    _timer?.cancel();
    if (mounted) state = '';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Watch this for the debounced value; call `.notifier.update()` to type.
final searchTextProvider =
    StateNotifierProvider<SearchTextNotifier, String>((ref) => SearchTextNotifier());

/// Filters and sort, held separately from the text so changing a filter
/// applies immediately without waiting for the debounce.
final searchFiltersProvider =
    StateProvider<SearchQuery>((ref) => const SearchQuery());

/// Which bottom-navigation tab is showing. Lets the home screen hand off to
/// the search tab instead of pushing a second, competing SearchScreen.
final selectedTabProvider = StateProvider<int>((ref) => 0);

/// One-shot request to focus the search field.
///
/// Needed because every tab lives in an IndexedStack and is therefore built at
/// launch — an `autofocus` on the search field would pop the keyboard as soon
/// as the app opened, before the user had gone anywhere near search.
final searchAutofocusProvider = StateProvider<bool>((ref) => false);

/// The fully assembled query the results provider actually runs.
final effectiveSearchQueryProvider = Provider<SearchQuery>((ref) {
  final text = ref.watch(searchTextProvider);
  final filters = ref.watch(searchFiltersProvider);
  return filters.copyWith(
    query: text,
    // With no search text, "relevance" is meaningless — fall back to name.
    sort: text.trim().isEmpty && filters.sort == ProductSort.relevance
        ? ProductSort.name
        : filters.sort,
  );
});

/// One-shot search for a specific query. Used where a single page is enough;
/// the search screen itself uses [searchPaginationProvider] instead.
final searchResultsProvider =
    FutureProvider.autoDispose.family<SearchResult, SearchQuery>((ref, query) {
  // Hold the result briefly so flicking between tabs doesn't refetch.
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 2), link.close);
  ref.onDispose(timer.cancel);

  return ref.watch(catalogRepositoryProvider).searchProducts(query);
});

// ---------------------------------------------------------------------------
// Paginated search
// ---------------------------------------------------------------------------

/// Accumulated search results across pages.
@immutable
class PagedResults {
  final List<ProductSummary> items;
  final int totalCount;
  final bool isLoadingFirstPage;
  final bool isLoadingMore;
  final Object? error;

  const PagedResults({
    this.items = const [],
    this.totalCount = 0,
    this.isLoadingFirstPage = true,
    this.isLoadingMore = false,
    this.error,
  });

  bool get hasMore => items.length < totalCount;
  bool get isEmpty => items.isEmpty && !isLoadingFirstPage && error == null;

  PagedResults copyWith({
    List<ProductSummary>? items,
    int? totalCount,
    bool? isLoadingFirstPage,
    bool? isLoadingMore,
    Object? error = _noError,
  }) {
    return PagedResults(
      items: items ?? this.items,
      totalCount: totalCount ?? this.totalCount,
      isLoadingFirstPage: isLoadingFirstPage ?? this.isLoadingFirstPage,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: identical(error, _noError) ? this.error : error,
    );
  }

  static const Object _noError = Object();
}

/// Loads search results page by page and appends them.
///
/// Without this the app could only ever show the first page — `limit` defaults
/// to 20, so product 21 was unreachable through search no matter how much the
/// user scrolled.
class SearchPaginationNotifier extends StateNotifier<PagedResults> {
  static const int pageSize = 20;

  final CatalogRepository _repo;
  final SearchQuery _query;

  /// Guards against overlapping loads when scroll events arrive in bursts.
  bool _busy = false;

  SearchPaginationNotifier(this._repo, this._query)
      : super(const PagedResults()) {
    _loadFirstPage();
  }

  Future<void> _loadFirstPage() async {
    _busy = true;
    try {
      final page = await _repo.searchProducts(
        _query.copyWith(limit: pageSize, offset: 0),
      );
      if (!mounted) return;
      state = PagedResults(
        items: page.items,
        totalCount: page.totalCount,
        isLoadingFirstPage: false,
      );
    } catch (e) {
      if (!mounted) return;
      state = PagedResults(isLoadingFirstPage: false, error: e);
    } finally {
      _busy = false;
    }
  }

  Future<void> loadMore() async {
    if (_busy || !state.hasMore || state.isLoadingFirstPage) return;
    _busy = true;
    state = state.copyWith(isLoadingMore: true);
    try {
      final page = await _repo.searchProducts(
        _query.copyWith(limit: pageSize, offset: state.items.length),
      );
      if (!mounted) return;
      state = state.copyWith(
        items: [...state.items, ...page.items],
        totalCount: page.totalCount,
        isLoadingMore: false,
      );
    } catch (e) {
      if (!mounted) return;
      // Keep what we already have; surface the error without wiping the list.
      state = state.copyWith(isLoadingMore: false, error: e);
    } finally {
      _busy = false;
    }
  }

  Future<void> refresh() async {
    state = const PagedResults();
    await _loadFirstPage();
  }
}

/// Paginated results for the current query. Rebuilds from scratch whenever the
/// query changes, which is what you want — a new search starts at page one.
final searchPaginationProvider = StateNotifierProvider.autoDispose<
    SearchPaginationNotifier, PagedResults>((ref) {
  final query = ref.watch(effectiveSearchQueryProvider);
  return SearchPaginationNotifier(ref.watch(catalogRepositoryProvider), query);
});

// ---------------------------------------------------------------------------
// Prices
// ---------------------------------------------------------------------------

final bestDealsProvider = FutureProvider<List<BestDeal>>((ref) {
  return ref.watch(catalogRepositoryProvider).getBestDeals(limit: 10);
});

// ---------------------------------------------------------------------------
// Government rates + regions
// ---------------------------------------------------------------------------

/// Rate-controlled staples: official price vs local market average.
final essentialsProvider = FutureProvider<List<Essential>>((ref) {
  return ref.watch(catalogRepositoryProvider).getEssentials(limit: 30);
});

/// Average price per administrative division for one product.
final regionalPricesProvider =
    FutureProvider.family<List<RegionalPrice>, String>((ref, productId) {
  return ref.watch(catalogRepositoryProvider).getRegionalPrices(productId);
});

final regionsProvider = FutureProvider<List<Region>>((ref) {
  return ref.watch(catalogRepositoryProvider).getRegions();
});

/// The division the user is browsing, persisted like language and theme.
/// Defaults to Dhaka.
final selectedRegionProvider = StateProvider<String>((ref) {
  return ref.watch(sharedPreferencesProvider).getString('settings.region') ??
      'dhaka';
});

/// All seller offers for a product, cheapest first. The comparison view.
final productOffersProvider =
    FutureProvider.family<List<PriceOffer>, String>((ref, productId) {
  return ref.watch(catalogRepositoryProvider).getOffers(productId);
});

final priceHistoryProvider =
    FutureProvider.family<List<PricePoint>, String>((ref, productId) {
  return ref.watch(catalogRepositoryProvider).getPriceHistory(productId);
});

/// Statistical read from the Python price service.
///
/// Returns null when the service is unreachable or unconfigured — insights are
/// an enhancement, never a dependency, so the product page must render fine
/// without them.
final productInsightProvider =
    FutureProvider.family<PriceInsight?, String>((ref, productId) async {
  final session = ref.watch(supabaseProvider).auth.currentSession;
  return ref.watch(priceInsightsServiceProvider).getInsight(
        productId,
        accessToken: session?.accessToken,
      );
});

// ---------------------------------------------------------------------------
// Favourites (signed-in only)
// ---------------------------------------------------------------------------

class FavoritesNotifier extends StateNotifier<Set<String>> {
  final CatalogRepository _repo;
  final String? _userId;

  FavoritesNotifier(this._repo, this._userId) : super(const {}) {
    if (_userId != null) _load();
  }

  Future<void> _load() async {
    try {
      state = await _repo.getFavoriteIds(_userId!);
    } catch (_) {
      state = const {};
    }
  }

  bool contains(String productId) => state.contains(productId);

  /// Optimistically flips the local state, then persists. Rolls back if the
  /// write fails, so the heart icon never lies about what was saved.
  Future<bool> toggle(String productId) async {
    if (_userId == null) return false;
    final wasFavorite = state.contains(productId);
    state = wasFavorite
        ? ({...state}..remove(productId))
        : {...state, productId};
    try {
      if (wasFavorite) {
        await _repo.removeFavorite(_userId, productId);
      } else {
        await _repo.addFavorite(_userId, productId);
      }
      return !wasFavorite;
    } catch (_) {
      state = wasFavorite
          ? {...state, productId}
          : ({...state}..remove(productId));
      rethrow;
    }
  }
}

final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier, Set<String>>((ref) {
  return FavoritesNotifier(
    ref.watch(catalogRepositoryProvider),
    ref.watch(currentUserProvider)?.id,
  );
});

class FavoritesPaginationNotifier extends StateNotifier<PagedResults> {
  static const int pageSize = 20;

  final CatalogRepository _repo;
  final bool _signedIn;
  bool _busy = false;

  FavoritesPaginationNotifier(this._repo, this._signedIn) : super(const PagedResults()) {
    _loadFirstPage();
  }

  Future<void> _loadFirstPage() async {
    if (!_signedIn) {
      state = const PagedResults(isLoadingFirstPage: false);
      return;
    }
    _busy = true;
    try {
      final items = await _repo.getFavorites(limit: pageSize, offset: 0);
      if (!mounted) return;
      final totalCount = items.isEmpty ? 0 : items.first.totalCount;
      state = PagedResults(
        items: items,
        totalCount: totalCount,
        isLoadingFirstPage: false,
      );
    } catch (e) {
      if (!mounted) return;
      state = PagedResults(isLoadingFirstPage: false, error: e);
    } finally {
      _busy = false;
    }
  }

  Future<void> loadMore() async {
    if (!_signedIn || _busy || !state.hasMore || state.isLoadingFirstPage) return;
    _busy = true;
    state = state.copyWith(isLoadingMore: true);
    try {
      final items = await _repo.getFavorites(
        limit: pageSize,
        offset: state.items.length,
      );
      if (!mounted) return;
      final totalCount = items.isEmpty ? state.totalCount : items.first.totalCount;
      state = state.copyWith(
        items: [...state.items, ...items],
        totalCount: totalCount,
        isLoadingMore: false,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoadingMore: false, error: e);
    } finally {
      _busy = false;
    }
  }

  Future<void> refresh() async {
    state = const PagedResults();
    await _loadFirstPage();
  }
}

final favoritePaginationProvider = StateNotifierProvider<FavoritesPaginationNotifier, PagedResults>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user != null) {
    // Re-run whenever the set of favourites changes
    ref.watch(favoritesProvider);
  }
  return FavoritesPaginationNotifier(ref.watch(catalogRepositoryProvider), user != null);
});
