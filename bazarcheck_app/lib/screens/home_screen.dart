import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/formatters.dart';
import '../l10n/app_strings.dart';
import '../models/essential.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../widgets/govt_price_widgets.dart';
import '../widgets/status_views.dart';
import 'product_detail_screen.dart';

/// Home — the BazarCheck dashboard.
///
/// Order matches the Stitch mockup: location header, market pulse (what moved
/// today), daily essentials with govt-vs-local prices, then the biggest gaps.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppStrings.of(context);
    final theme = Theme.of(context);
    final bangla = ref.watch(isBanglaProvider);
    final essentials = ref.watch(essentialsProvider);
    final regionSlug = ref.watch(selectedRegionProvider);
    final regions = ref.watch(regionsProvider);

    final regionName = regions.maybeWhen(
      data: (list) {
        for (final r in list) {
          if (r.slug == regionSlug) return r.displayName(bangla: bangla);
        }
        return 'Dhaka';
      },
      orElse: () => 'Dhaka',
    );

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(essentialsProvider),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // --- Location + brand header ---------------------------------
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 18, color: AppTheme.primary),
                      const SizedBox(width: 6),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            t.currentLocation.toUpperCase(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 9,
                              letterSpacing: 0.6,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            regionName,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        t.appName,
                        style: theme.textTheme.headlineMedium
                            ?.copyWith(color: AppTheme.primary),
                      ),
                    ],
                  ),
                ),
              ),

              // --- Sample-data disclosure ----------------------------------
              // Government rates here are illustrative. Saying so once, plainly,
              // at the top is the difference between a demo and a lie.
              const SliverToBoxAdapter(child: _SampleDataBanner()),

              // --- Market pulse --------------------------------------------
              SliverToBoxAdapter(
                child: essentials.maybeWhen(
                  data: (list) => _MarketPulse(items: list, bangla: bangla),
                  orElse: () => const SizedBox.shrink(),
                ),
              ),

              // --- Daily essentials ----------------------------------------
              SliverToBoxAdapter(
                child: _SectionHeader(
                  title: t.dailyEssentials,
                  action: t.viewAll,
                  onAction: () =>
                      ref.read(selectedTabProvider.notifier).state = 1,
                ),
              ),

              essentials.when(
                loading: () => const SliverToBoxAdapter(
                  child: SizedBox(height: 320, child: ListSkeleton(count: 3)),
                ),
                error: (e, _) => SliverToBoxAdapter(
                  child: SizedBox(
                    height: 340,
                    child: ErrorView(
                      error: e,
                      onRetry: () => ref.invalidate(essentialsProvider),
                    ),
                  ),
                ),
                data: (list) {
                  if (list.isEmpty) {
                    return SliverToBoxAdapter(
                      child: SizedBox(
                        height: 260,
                        child: EmptyView(
                          icon: Icons.inventory_2_outlined,
                          message: t.nothingHere,
                          hint: 'Apply database/COMPLETE_SETUP.sql, '
                              'then pull to refresh.',
                        ),
                      ),
                    );
                  }
                  final top = list.take(6).toList();
                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    sliver: SliverList.separated(
                      itemCount: top.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => EssentialCard(
                        item: top[i],
                        bangla: bangla,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                ProductDetailScreen(productId: top[i].id),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Honest, permanent notice that the government rates are sample figures.
class _SampleDataBanner extends StatelessWidget {
  const _SampleDataBanner();

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.tertiaryFixed.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 16, color: AppTheme.tertiary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                t.sampleDataNotice,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppTheme.onTertiaryFixed,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal strip of the biggest movers against the official rate.
class _MarketPulse extends StatelessWidget {
  final List<Essential> items;
  final bool bangla;

  const _MarketPulse({required this.items, required this.bangla});

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final theme = Theme.of(context);

    // Only products where a real comparison exists.
    final movers = items
        .where((e) => e.hasComparison && (e.gapPercent ?? 0).abs() >= 1)
        .toList()
      ..sort((a, b) =>
          (b.gapPercent ?? 0).abs().compareTo((a.gapPercent ?? 0).abs()));

    if (movers.isEmpty) return const SizedBox.shrink();
    final top = movers.take(6).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Row(
            children: [
              Icon(Icons.bolt, size: 18, color: AppTheme.tertiary),
              const SizedBox(width: 6),
              Text(
                t.marketPulse,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: top.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final e = top[i];
              final up = (e.gapPercent ?? 0) > 0;
              final colour = up ? AppTheme.spike : AppTheme.drop;
              return Container(
                width: 168,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.55),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        StatusPill(
                          status: e.status,
                          gapPercent: e.gapPercent,
                          bangla: bangla,
                        ),
                        const Spacer(),
                        Icon(up ? Icons.trending_up : Icons.trending_down,
                            size: 16, color: colour),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      e.displayName(bangla: bangla),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${up ? '+' : ''}'
                      '${Fmt.percent(e.gapPercent!, bangla: bangla)}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colour,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      t.vsGovtRate,
                      style: theme.textTheme.labelSmall?.copyWith(fontSize: 9),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;

  const _SectionHeader({required this.title, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 8, 10),
      child: Row(
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}
