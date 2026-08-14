import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../l10n/app_strings.dart';
import '../models/essential.dart';
import '../theme/app_theme.dart';

/// Average price per administrative division, cheapest first.
///
/// Matches the "Regional Prices" table in the mockup: DIVISION · PRICE · TREND.
/// The trend column compares against the average a week ago; where there is no
/// history it shows a dash rather than implying stability.
class RegionalPriceTable extends StatelessWidget {
  final List<RegionalPrice> rows;
  final bool bangla;

  const RegionalPriceTable({
    super.key,
    required this.rows,
    required this.bangla,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final theme = Theme.of(context);
    if (rows.isEmpty) return const SizedBox.shrink();

    final cheapest = rows.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.public, size: 18, color: AppTheme.primary),
            const SizedBox(width: 8),
            Text(
              t.regionalPrices,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Card(
          child: Column(
            children: [
              // Header
              Container(
                color: theme.colorScheme.surfaceContainer,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text(t.division.toUpperCase(),
                          style: _head(theme)),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(t.price.toUpperCase(),
                          textAlign: TextAlign.right, style: _head(theme)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(t.trend.toUpperCase(),
                          textAlign: TextAlign.right, style: _head(theme)),
                    ),
                  ],
                ),
              ),
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _Row(
                  row: rows[i],
                  bangla: bangla,
                  isCheapest: rows[i].regionId == cheapest.regionId,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static TextStyle? _head(ThemeData theme) => theme.textTheme.labelSmall
      ?.copyWith(fontSize: 10, letterSpacing: 0.5, fontWeight: FontWeight.w700);
}

class _Row extends StatelessWidget {
  final RegionalPrice row;
  final bool bangla;
  final bool isCheapest;

  const _Row({
    required this.row,
    required this.bangla,
    required this.isCheapest,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trend = row.trendPercent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      color: isCheapest
          ? AppTheme.secondaryContainer.withValues(alpha: 0.25)
          : null,
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    row.displayName(bangla: bangla),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (isCheapest) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.verified,
                      size: 13, color: AppTheme.onSecondaryContainer),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              Fmt.price(row.avgPrice, bangla: bangla) ?? '—',
              textAlign: TextAlign.right,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: isCheapest
                    ? AppTheme.onSecondaryContainer
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: trend == null
                ? Text('—',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodySmall)
                : Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Icon(
                        row.isRising
                            ? Icons.north_east
                            : row.isFalling
                                ? Icons.south_east
                                : Icons.remove,
                        size: 12,
                        color: row.isRising
                            ? AppTheme.spike
                            : row.isFalling
                                ? AppTheme.drop
                                : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        Fmt.percent(trend.abs(), bangla: bangla),
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: row.isRising
                              ? AppTheme.spike
                              : row.isFalling
                                  ? AppTheme.drop
                                  : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
