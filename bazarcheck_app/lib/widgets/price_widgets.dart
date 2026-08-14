import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../l10n/app_strings.dart';
import '../theme/app_theme.dart';

/// The price on a product card.
///
/// Shows a range (`৳72 – ৳85`) when sellers disagree, a single figure when they
/// don't, and an explicit "price unavailable" when nobody has listed one —
/// never a fabricated ৳0.
class PriceDisplay extends StatelessWidget {
  final double? minPrice;
  final double? maxPrice;
  final String? unit;
  final bool bangla;
  final bool large;

  const PriceDisplay({
    super.key,
    required this.minPrice,
    this.maxPrice,
    this.unit,
    required this.bangla,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppStrings.of(context);

    if (minPrice == null) {
      return Text(
        t.noPrice,
        style: (large ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium)
            ?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    final hasRange = maxPrice != null && maxPrice! > minPrice!;
    final main = Fmt.price(minPrice, bangla: bangla)!;
    final unitText = Fmt.unitLabel(unit, bangla: bangla);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            if (hasRange) ...[
              Text(
                t.from,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              main,
              style: (large
                      ? theme.textTheme.headlineMedium
                      : theme.textTheme.titleMedium)
                  ?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.savingsColor,
              ),
            ),
          ],
        ),
        if (unitText.isNotEmpty)
          Text(
            unitText,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
      ],
    );
  }
}

/// "Updated 3h ago", tinted by how stale the price is.
///
/// This is the trust signal the original app was missing entirely: `updated_at`
/// existed in the database but was never shown, so every price looked current.
class FreshnessBadge extends StatelessWidget {
  final DateTime? collectedAt;
  final bool bangla;
  final bool compact;

  const FreshnessBadge({
    super.key,
    required this.collectedAt,
    required this.bangla,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppStrings.of(context);
    final freshness = Freshness.of(collectedAt);
    final style = FreshnessStyle.of(freshness, theme.colorScheme);
    final rel = Fmt.relativeTime(collectedAt, bangla: bangla);

    final label = compact ? rel : t.updatedAgo(rel);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(style.icon, size: 13, color: style.color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: style.color,
              fontWeight:
                  freshness.isTrustworthy ? FontWeight.w400 : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// "3 sellers" pill.
class SellerCountChip extends StatelessWidget {
  final int count;
  final bool bangla;

  const SellerCountChip({super.key, required this.count, required this.bangla});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppStrings.of(context);
    if (count <= 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.storefront_outlined,
              size: 12, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            t.sellerCount(count),
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Green "Save ৳13" pill shown when sellers disagree enough to matter.
class SavingsBadge extends StatelessWidget {
  final double savings;
  final double? percent;
  final bool bangla;

  const SavingsBadge({
    super.key,
    required this.savings,
    this.percent,
    required this.bangla,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppStrings.of(context);
    if (savings <= 0) return const SizedBox.shrink();

    final amount = Fmt.price(savings, bangla: bangla) ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.savingsColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.trending_down,
              size: 13, color: theme.colorScheme.savingsColor),
          const SizedBox(width: 4),
          Text(
            t.youSave(amount),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.savingsColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Cheapest" ribbon on the winning offer.
class CheapestBadge extends StatelessWidget {
  const CheapestBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppStrings.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.savingsColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified, size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            t.bestPrice,
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
