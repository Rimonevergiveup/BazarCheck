import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/formatters.dart';
import '../l10n/app_strings.dart';
import '../models/essential.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_image.dart';
import '../widgets/price_history_chart.dart';
import '../widgets/status_views.dart';

/// Trends — price history for one product at a time.
///
/// The mockup includes an "AI PREDICTION" panel ("prices expected to drop by
/// 5%, high confidence"). That is deliberately not built: a forecast needs
/// months of real observations, and this database holds thirty days of sample
/// data. A confident-looking prediction drawn from that would be fiction, which
/// is exactly the failure this app was rebuilt to remove.
///
/// What IS shown is measured: the recorded low, high, average and spread.
class TrendsScreen extends ConsumerStatefulWidget {
  const TrendsScreen({super.key});

  @override
  ConsumerState<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends ConsumerState<TrendsScreen> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final theme = Theme.of(context);
    final bangla = ref.watch(isBanglaProvider);
    final essentials = ref.watch(essentialsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t.priceAnalytics)),
      body: essentials.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(essentialsProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return EmptyView(icon: Icons.show_chart, message: t.nothingHere);
          }

          final selected = list.firstWhere(
            (e) => e.id == _selectedId,
            orElse: () => list.first,
          );
          final history = ref.watch(priceHistoryProvider(selected.id));

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Text(
                t.priceAnalyticsHint,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),

              // --- Product picker ------------------------------------------
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      AppImage(
                        url: selected.imageUrl,
                        width: 44,
                        height: 44,
                        radius: 8,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.selectedProduct.toUpperCase(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontSize: 9,
                                letterSpacing: 0.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              selected.displayName(bangla: bangla),
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.expand_more),
                        onSelected: (id) => setState(() => _selectedId = id),
                        itemBuilder: (_) => list
                            .map((e) => PopupMenuItem(
                                  value: e.id,
                                  child: Text(e.displayName(bangla: bangla)),
                                ))
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0, duration: 400.ms, curve: Curves.easeOutBack),

              const SizedBox(height: 16),

              // --- Chart ----------------------------------------------------
              history.when(
                loading: () => const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => SizedBox(
                  height: 200,
                  child: ErrorView(
                    error: e,
                    onRetry: () =>
                        ref.invalidate(priceHistoryProvider(selected.id)),
                  ),
                ),
                data: (points) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              t.last30Days.toUpperCase(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontSize: 9,
                                letterSpacing: 0.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            if (selected.localAvgPrice != null)
                              Text(
                                Fmt.price(selected.localAvgPrice,
                                        bangla: bangla) ??
                                    '',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primary,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        PriceHistoryChart(points: points, bangla: bangla),
                      ],
                    ),
                  ),
                ).animate().fadeIn(duration: 400.ms, delay: 100.ms).slideY(begin: 0.1, end: 0, duration: 400.ms, curve: Curves.easeOutBack),
              ),

              const SizedBox(height: 16),
              _StatsGrid(item: selected, bangla: bangla).animate().fadeIn(duration: 400.ms, delay: 200.ms).slideY(begin: 0.1, end: 0, duration: 400.ms, curve: Curves.easeOutBack),

              const SizedBox(height: 16),
              // Replaces the mockup's "AI PREDICTION" panel with the reason it
              // isn't here.
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.science_outlined,
                        size: 18, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.forecastUnavailable,
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            t.forecastUnavailableHint,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 400.ms, delay: 300.ms).slideY(begin: 0.1, end: 0, duration: 400.ms, curve: Curves.easeOutBack),
            ],
          );
        },
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final Essential item;
  final bool bangla;

  const _StatsGrid({required this.item, required this.bangla});

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: t.govtFixed,
            value: Fmt.price(item.govtFixedPrice, bangla: bangla) ??
                t.noOfficialRate,
            accent: AppTheme.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            label: t.localAverage,
            value: Fmt.price(item.localAvgPrice, bangla: bangla) ?? '—',
            accent: AppTheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            label: t.cheapest,
            value: Fmt.price(item.localMinPrice, bangla: bangla) ?? '—',
            accent: AppTheme.drop,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;

  const _StatCard({
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(
          left: BorderSide(color: accent, width: 3),
          top: BorderSide(color: theme.colorScheme.outlineVariant),
          right: BorderSide(color: theme.colorScheme.outlineVariant),
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall
                ?.copyWith(fontSize: 9, letterSpacing: 0.4),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
