import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_strings.dart';
import '../models/category.dart';
import '../providers.dart';
import '../repositories/catalog_repository.dart';
import '../widgets/product_card.dart';
import '../widgets/status_views.dart';
import 'product_detail_screen.dart';

/// Bilingual product search.
///
/// Typing "চাল" or "rice" finds the same product, because `search_products`
/// matches against a generated column covering the English name, the Bangla
/// name, the brand and the description.
class SearchScreen extends ConsumerStatefulWidget {
  final String? initialQuery;
  final String? categoryId;
  final String? categoryName;

  const SearchScreen({
    super.key,
    this.initialQuery,
    this.categoryId,
    this.categoryName,
  });

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();

  /// True when this instance was pushed for a specific category, rather than
  /// being the persistent search tab. Those two need different lifecycles.
  bool get _isScoped => widget.categoryId != null;

  SearchQuery? _previousFilters;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery ?? '');

    // Fetch the next page when the user gets within ~600px of the bottom, so
    // more results are already arriving before they reach the end.
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (position.pixels >= position.maxScrollExtent - 600) {
        ref.read(searchPaginationProvider.notifier).loadMore();
      }
    });

    // Mutate provider state after the first frame — never during a build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_isScoped) {
        // Remember what the search tab had, so popping back doesn't leave the
        // user silently filtered to a category they've navigated away from.
        _previousFilters = ref.read(searchFiltersProvider);
        ref.read(searchFiltersProvider.notifier).state =
            SearchQuery(categoryId: widget.categoryId, sort: ProductSort.priceAsc);
        ref.read(searchTextProvider.notifier).clear();
      }
      final initial = widget.initialQuery;
      if (initial != null && initial.isNotEmpty) {
        ref.read(searchTextProvider.notifier).submit(initial);
      }
    });
  }

  @override
  void dispose() {
    if (_isScoped && _previousFilters != null) {
      // Restore in a microtask: dispose() runs during teardown, when mutating
      // another provider synchronously is unsafe.
      final previous = _previousFilters!;
      final container = ProviderScope.containerOf(context, listen: false);
      Future.microtask(() {
        try {
          container.read(searchFiltersProvider.notifier).state = previous;
        } catch (_) {
          // Container already gone (app shutting down) — nothing to restore.
        }
      });
    }
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final theme = Theme.of(context);
    final bangla = ref.watch(isBanglaProvider);
    final results = ref.watch(searchPaginationProvider);
    final filters = ref.watch(searchFiltersProvider);
    final query = ref.watch(searchTextProvider);
    final favorites = ref.watch(favoritesProvider);
    final signedIn = ref.watch(isSignedInProvider);

    // Focus only when the home screen explicitly asks for it. Consumed
    // immediately so it fires once, not on every rebuild.
    ref.listen<bool>(searchAutofocusProvider, (_, wants) {
      if (wants && mounted && !_isScoped) {
        _focusNode.requestFocus();
        ref.read(searchAutofocusProvider.notifier).state = false;
      }
    });

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: _isScoped,
        titleSpacing: 8,
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          textInputAction: TextInputAction.search,
          autocorrect: false,
          decoration: InputDecoration(
            hintText: widget.categoryName ?? t.searchHint,
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: t.clear,
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      _controller.clear();
                      ref.read(searchTextProvider.notifier).clear();
                      setState(() {});
                    },
                  ),
          ),
          onChanged: (v) {
            ref.read(searchTextProvider.notifier).update(v);
            setState(() {}); // refresh the clear button
          },
          onSubmitted: (v) => ref.read(searchTextProvider.notifier).submit(v),
        ),
      ),
      body: Column(
        children: [
          _FilterBar(
            filters: filters,
            onChanged: (q) =>
                ref.read(searchFiltersProvider.notifier).state = q,
          ),
          Expanded(child: Builder(builder: (context) {
            if (results.isLoadingFirstPage) return const ListSkeleton();

            if (results.error != null && results.items.isEmpty) {
              return ErrorView(
                error: results.error,
                onRetry: () =>
                    ref.read(searchPaginationProvider.notifier).refresh(),
              );
            }

            if (results.isEmpty) {
              return RefreshableCenter(
                child: query.trim().isEmpty
                    ? EmptyView(
                        icon: Icons.search,
                        message: t.startSearching,
                        hint: t.searchHint,
                      )
                    : EmptyView(
                        icon: Icons.search_off,
                        message: t.noResultsFor(query),
                        hint: t.noResultsHint,
                        action: filters.hasFilters
                            ? OutlinedButton.icon(
                                onPressed: () => ref
                                    .read(searchFiltersProvider.notifier)
                                    .state = const SearchQuery(),
                                icon: const Icon(Icons.filter_alt_off),
                                label: Text(t.reset),
                              )
                            : null,
                      ),
              );
            }

            return RefreshIndicator(
              onRefresh: () =>
                  ref.read(searchPaginationProvider.notifier).refresh(),
              child: ListView.separated(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                // +1 header, +1 footer (spinner / end-of-list marker)
                itemCount: results.items.length + 2,
                separatorBuilder: (_, i) =>
                    SizedBox(height: i == 0 ? 4 : 10),
                itemBuilder: (context, i) {
                  // Header: how many results in total, not just how many loaded
                  if (i == 0) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
                      child: Text(
                        t.resultsCount(results.totalCount),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  }

                  // Footer
                  if (i == results.items.length + 1) {
                    return _ListFooter(
                      isLoading: results.isLoadingMore,
                      hasMore: results.hasMore,
                      failed: results.error != null,
                      onRetry: () => ref
                          .read(searchPaginationProvider.notifier)
                          .loadMore(),
                    );
                  }

                  final p = results.items[i - 1];
                  return ProductCard(
                    product: p,
                    bangla: bangla,
                    isFavorite: favorites.contains(p.id),
                    onToggleFavorite: signedIn
                        ? () =>
                            ref.read(favoritesProvider.notifier).toggle(p.id)
                        : null,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ProductDetailScreen(productId: p.id),
                      ),
                    ),
                  );
                },
              ),
            );
          })),
        ],
      ),
    );
  }
}

/// Footer row: loading spinner, retry, or "that's everything".
class _ListFooter extends StatelessWidget {
  final bool isLoading;
  final bool hasMore;
  final bool failed;
  final VoidCallback onRetry;

  const _ListFooter({
    required this.isLoading,
    required this.hasMore,
    required this.failed,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final theme = Theme.of(context);

    if (isLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Text(t.loadingMore, style: theme.textTheme.bodySmall),
          ],
        ),
      );
    }

    // A page failed but earlier results are still on screen — offer a retry
    // rather than replacing everything with an error.
    if (failed && hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: Text(t.retry),
          ),
        ),
      );
    }

    if (hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: TextButton(onPressed: onRetry, child: Text(t.loadMore)),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          t.endOfResults,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// Horizontal row of category, sort and price filters.
class _FilterBar extends ConsumerWidget {
  final SearchQuery filters;
  final ValueChanged<SearchQuery> onChanged;

  const _FilterBar({required this.filters, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppStrings.of(context);
    final theme = Theme.of(context);
    final categories = ref.watch(categoriesProvider);

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          _SortChip(
            current: filters.sort,
            onChanged: (s) => onChanged(filters.copyWith(sort: s)),
          ),
          const SizedBox(width: 8),
          categories.maybeWhen(
            data: (list) => _CategoryChip(
              categories: list,
              selectedId: filters.categoryId,
              onChanged: (id) => onChanged(filters.copyWith(categoryId: id)),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(width: 8),
          _PriceChip(
            min: filters.minPrice,
            max: filters.maxPrice,
            onChanged: (lo, hi) =>
                onChanged(filters.copyWith(minPrice: lo, maxPrice: hi)),
          ),
          if (filters.hasFilters) ...[
            const SizedBox(width: 8),
            ActionChip(
              avatar: const Icon(Icons.filter_alt_off, size: 16),
              label: Text(t.reset),
              onPressed: () => onChanged(SearchQuery(sort: filters.sort)),
              backgroundColor: theme.colorScheme.errorContainer,
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final List<Category> categories;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  const _CategoryChip({
    required this.categories,
    required this.selectedId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    if (categories.isEmpty) return const SizedBox.shrink();

    // Deliberately not `firstOrNull` — that is an extension from
    // package:collection, not dart:core, and this project doesn't depend on it.
    Category? selected;
    if (selectedId != null) {
      for (final c in categories) {
        if (c.id == selectedId) {
          selected = c;
          break;
        }
      }
    }

    return PopupMenuButton<String?>(
      initialValue: selectedId,
      onSelected: onChanged,
      itemBuilder: (_) => [
        PopupMenuItem<String?>(value: null, child: Text(t.allCategories)),
        const PopupMenuDivider(),
        ...categories.map(
          (c) => PopupMenuItem<String?>(value: c.id, child: Text(c.name)),
        ),
      ],
      child: Chip(
        avatar: const Icon(Icons.category_outlined, size: 16),
        label: Text(selected?.name ?? t.allCategories),
        backgroundColor: selected != null
            ? Theme.of(context).colorScheme.primaryContainer
            : null,
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  final ProductSort current;
  final ValueChanged<ProductSort> onChanged;

  const _SortChip({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);

    String label(ProductSort s) => switch (s) {
          ProductSort.relevance => t.sortRelevance,
          ProductSort.priceAsc => t.sortPriceLow,
          ProductSort.priceDesc => t.sortPriceHigh,
          ProductSort.name => t.sortName,
          ProductSort.newest => t.sortNewest,
        };

    return PopupMenuButton<ProductSort>(
      initialValue: current,
      onSelected: onChanged,
      itemBuilder: (_) => ProductSort.values
          .map((s) => PopupMenuItem(value: s, child: Text(label(s))))
          .toList(),
      child: Chip(
        avatar: const Icon(Icons.swap_vert, size: 16),
        label: Text(label(current)),
      ),
    );
  }
}

class _PriceChip extends StatelessWidget {
  final double? min;
  final double? max;
  final void Function(double? min, double? max) onChanged;

  const _PriceChip({
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final active = min != null || max != null;

    return ActionChip(
      avatar: const Icon(Icons.payments_outlined, size: 16),
      label: Text(active ? '${min?.round() ?? ''}–${max?.round() ?? ''}' : t.priceRange),
      backgroundColor:
          active ? Theme.of(context).colorScheme.primaryContainer : null,
      onPressed: () async {
        final result = await showDialog<(double?, double?)>(
          context: context,
          builder: (_) => _PriceRangeDialog(min: min, max: max),
        );
        if (result != null) onChanged(result.$1, result.$2);
      },
    );
  }
}

class _PriceRangeDialog extends StatefulWidget {
  final double? min;
  final double? max;
  const _PriceRangeDialog({this.min, this.max});

  @override
  State<_PriceRangeDialog> createState() => _PriceRangeDialogState();
}

class _PriceRangeDialogState extends State<_PriceRangeDialog> {
  late final TextEditingController _minCtrl =
      TextEditingController(text: widget.min?.round().toString() ?? '');
  late final TextEditingController _maxCtrl =
      TextEditingController(text: widget.max?.round().toString() ?? '');

  @override
  void dispose() {
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    return AlertDialog(
      title: Text(t.priceRange),
      content: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _minCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: t.minPrice, prefixText: '৳'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _maxCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: t.maxPrice, prefixText: '৳'),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, (null, null)),
          child: Text(t.reset),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            (
              double.tryParse(_minCtrl.text.trim()),
              double.tryParse(_maxCtrl.text.trim()),
            ),
          ),
          child: Text(t.apply),
        ),
      ],
    );
  }
}
