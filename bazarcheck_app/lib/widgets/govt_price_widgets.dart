import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../l10n/app_strings.dart';
import '../models/essential.dart';
import '../theme/app_theme.dart';
import 'app_image.dart';

/// SPIKE / STABLE / DROP pill.
class StatusPill extends StatelessWidget {
  final PriceStatus status;
  final double? gapPercent;
  final bool bangla;

  const StatusPill({
    super.key,
    required this.status,
    this.gapPercent,
    required this.bangla,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final theme = Theme.of(context);
    if (!status.isKnown) return const SizedBox.shrink();

    final (Color fg, Color bg, IconData icon, String label) = switch (status) {
      PriceStatus.spike => (
          AppTheme.spike,
          AppTheme.errorContainer,
          Icons.trending_up,
          t.statusSpike,
        ),
      PriceStatus.drop => (
          AppTheme.onSecondaryContainer,
          AppTheme.secondaryContainer,
          Icons.trending_down,
          t.statusDrop,
        ),
      _ => (
          AppTheme.onSurfaceVariant,
          AppTheme.surfaceContainerHigh,
          Icons.trending_flat,
          t.statusStable,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// The two-column price block: official rate beside the local market average.
///
/// This is the comparison BazarCheck is built on, so both figures get equal
/// visual weight and each is labelled with where it came from. When either is
/// missing the block says so rather than filling the gap with a guess.
class GovtVsLocalPrices extends StatelessWidget {
  final double? govtPrice;
  final double? localPrice;
  final String? unit;
  final bool bangla;
  final bool compact;

  const GovtVsLocalPrices({
    super.key,
    required this.govtPrice,
    required this.localPrice,
    this.unit,
    required this.bangla,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final theme = Theme.of(context);
    final unitSuffix = (unit == null || unit!.isEmpty) ? '' : '/$unit';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _PriceBlock(
            caption: t.govtFixed,
            value: Fmt.price(govtPrice, bangla: bangla),
            suffix: unitSuffix,
            valueColour: AppTheme.primary,
            background: theme.colorScheme.govtTint,
            emptyLabel: t.noOfficialRate,
            compact: compact,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _PriceBlock(
            caption: t.localMarket,
            value: Fmt.price(localPrice, bangla: bangla),
            suffix: unitSuffix,
            valueColour: theme.colorScheme.onSurface,
            background: theme.colorScheme.surfaceContainerLow,
            emptyLabel: t.noPrice,
            compact: compact,
          ),
        ),
      ],
    );
  }
}

class _PriceBlock extends StatelessWidget {
  final String caption;
  final String? value;
  final String suffix;
  final Color valueColour;
  final Color background;
  final String emptyLabel;
  final bool compact;

  const _PriceBlock({
    required this.caption,
    required this.value,
    required this.suffix,
    required this.valueColour,
    required this.background,
    required this.emptyLabel,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: compact ? 8 : 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            caption.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 9,
              letterSpacing: 0.5,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 3),
          if (value == null)
            Text(
              emptyLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: valueColour,
                      fontWeight: FontWeight.w700,
                      fontSize: compact ? 17 : 20,
                    ),
                  ),
                  TextSpan(
                    text: suffix,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// "৳8 higher" annotation showing how far the local market sits from the
/// official rate.
class PriceGapLabel extends StatelessWidget {
  final double? gap;
  final bool bangla;

  const PriceGapLabel({super.key, required this.gap, required this.bangla});

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final theme = Theme.of(context);
    final g = gap;
    if (g == null || g.abs() < 0.01) return const SizedBox.shrink();

    final over = g > 0;
    final colour = over ? AppTheme.spike : AppTheme.drop;
    final amount = Fmt.price(g.abs(), bangla: bangla) ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(over ? Icons.north_east : Icons.south_east,
                size: 12, color: colour),
            const SizedBox(width: 2),
            Text(
              over ? t.amountHigher(amount) : t.amountLower(amount),
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: colour, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        Text(
          t.priceGap,
          style: theme.textTheme.labelSmall?.copyWith(fontSize: 9),
        ),
      ],
    );
  }
}

/// The product row used on Home ("Daily Essentials") and Compare.
class EssentialCard extends StatelessWidget {
  final Essential item;
  final bool bangla;
  final VoidCallback onTap;
  final bool showStatus;

  const EssentialCard({
    super.key,
    required this.item,
    required this.bangla,
    required this.onTap,
    this.showStatus = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppImage(
                    url: item.imageUrl,
                    width: 64,
                    height: 64,
                    radius: 8,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.displayName(bangla: bangla),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (item.unit != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            Fmt.unitLabel(item.unit, bangla: bangla),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (showStatus)
                    StatusPill(
                      status: item.status,
                      gapPercent: item.gapPercent,
                      bangla: bangla,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              GovtVsLocalPrices(
                govtPrice: item.govtFixedPrice,
                localPrice: item.localAvgPrice,
                unit: item.unit,
                bangla: bangla,
                compact: true,
              ),
              if (item.hasComparison && (item.priceGap ?? 0).abs() >= 0.01) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: PriceGapLabel(gap: item.priceGap, bangla: bangla),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
