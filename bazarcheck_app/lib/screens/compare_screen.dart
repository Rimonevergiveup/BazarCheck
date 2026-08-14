import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_strings.dart';
import '../models/essential.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../widgets/govt_price_widgets.dart';
import '../widgets/status_views.dart';
import 'product_detail_screen.dart';
import 'search_screen.dart';

/// Compare — every rate-controlled staple, official price against the market.
///
/// Search filters the list locally: the essentials set is small (tens of items,
/// not thousands) and already in memory, so a round trip per keystroke would be
/// slower and no more correct.
class CompareScreen extends ConsumerStatefulWidget {
  const CompareScreen({super.key});

  @override
  ConsumerState<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends ConsumerState<CompareScreen> {
  final _controller = TextEditingController();
  String _query = '';
  _StatusFilter _filter = _StatusFilter.all;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Essential> _apply(List<Essential> items) {
    final q = _query.trim().toLowerCase();
    return items.where((e) {
      final matchesQuery = q.isEmpty ||
          e.name.toLowerCase().contains(q) ||
          (e.nameBn?.contains(_query.trim()) ?? false);
      final matchesFilter = switch (_filter) {
        _StatusFilter.all => true,
        _StatusFilter.spike => e.status == PriceStatus.spike,
        _StatusFilter.stable => e.status == PriceStatus.stable,
        _StatusFilter.drop => e.status == PriceStatus.drop,
      };
      return matchesQuery && matchesFilter;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final theme = Theme.of(context);
    final bangla = ref.watch(isBanglaProvider);
    final essentials = ref.watch(essentialsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.appName),
        actions: [
          // Compare covers rate-controlled essentials only. Everything else in
          // the catalogue lives behind full search.
          IconButton(
            tooltip: t.searchProducts,
            icon: const Icon(Icons.manage_search),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: t.searchEssentials,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _controller.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),

          // Status filter chips
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              children: [
                for (final f in _StatusFilter.values) ...[
                  ChoiceChip(
                    label: Text(switch (f) {
                      _StatusFilter.all => t.allProducts,
                      _StatusFilter.spike => t.statusSpike,
                      _StatusFilter.stable => t.statusStable,
                      _StatusFilter.drop => t.statusDrop,
                    }),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                    selectedColor: AppTheme.primaryContainer,
                    labelStyle: theme.textTheme.labelLarge?.copyWith(
                      color: _filter == f
                          ? AppTheme.onPrimaryContainer
                          : theme.colorScheme.onSurface,
                    ),
                    showCheckmark: false,
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),

          Expanded(
            child: essentials.when(
              loading: () => const ListSkeleton(),
              error: (e, _) => ErrorView(
                error: e,
                onRetry: () => ref.invalidate(essentialsProvider),
              ),
              data: (all) {
                final items = _apply(all);
                if (items.isEmpty) {
                  return RefreshableCenter(
                    child: EmptyView(
                      icon: Icons.search_off,
                      message: _query.isEmpty ? t.nothingHere : t.noResults,
                      hint: _query.isEmpty ? null : t.noResultsHint,
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(essentialsProvider),
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: items.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      if (i == items.length) return const _GovtRatesFooter();
                      return EssentialCard(
                        item: items[i],
                        bangla: bangla,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                ProductDetailScreen(productId: items[i].id),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

enum _StatusFilter { all, spike, stable, drop }

class _GovtRatesFooter extends StatelessWidget {
  const _GovtRatesFooter();

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.govtTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_outlined, size: 18, color: AppTheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.governmentRates,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: AppTheme.primary),
                ),
                const SizedBox(height: 2),
                Text(t.sampleDataNotice, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
