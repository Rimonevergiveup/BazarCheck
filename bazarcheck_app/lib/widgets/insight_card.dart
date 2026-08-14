import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../l10n/app_strings.dart';
import '../services/price_insights_service.dart';
import '../theme/app_theme.dart';

/// Statistical summary from the Python price service.
///
/// Every figure here is computed from real rows in `prices` and `price_history`.
/// Where the data can't support a conclusion the service says so, and this card
/// renders nothing rather than filling space with something invented — which is
/// exactly what the original "AI Analysis" panel did.
///
/// Renders nothing at all when [insight] is null (service offline or
/// unconfigured), because the product page must work without it.
class InsightCard extends StatelessWidget {
  final PriceInsight? insight;
  final bool bangla;

  const InsightCard({super.key, required this.insight, required this.bangla});

  @override
  Widget build(BuildContext context) {
    final data = insight;
    if (data == null || data.sellerCount == 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final t = AppStrings.of(context);

    // Nothing worth saying? Then don't take up the space.
    final hasStats = data.median != null || data.spreadPercent != null;
    if (!hasStats && data.notes.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.insights_outlined,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  t.insights,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),

            if (data.isGoodTimeToBuy) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.savingsColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.thumb_up_outlined,
                        size: 16, color: theme.colorScheme.savingsColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.goodTimeToBuy,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.savingsColor,
                            ),
                          ),
                          Text(
                            t.goodTimeHint,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),
            Wrap(
              spacing: 20,
              runSpacing: 12,
              children: [
                if (data.median != null)
                  _Stat(
                    label: t.medianPrice,
                    value: Fmt.price(data.median, bangla: bangla) ?? '—',
                  ),
                if (data.spreadPercent != null && data.spreadPercent! > 0)
                  _Stat(
                    label: t.priceSpread,
                    value: Fmt.percent(data.spreadPercent!, bangla: bangla),
                    colour: theme.colorScheme.savingsColor,
                  ),
                _Stat(
                  label: t.allOffers,
                  value: bangla
                      ? Fmt.toBanglaDigits('${data.sellerCount}')
                      : '${data.sellerCount}',
                ),
              ],
            ),

            if (data.staleSellerCount > 0) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.warning_amber_outlined,
                      size: 14, color: theme.colorScheme.warningColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      t.staleSellers(data.staleSellerCount),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.warningColor),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color? colour;

  const _Stat({required this.label, required this.value, this.colour});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: colour,
          ),
        ),
      ],
    );
  }
}
