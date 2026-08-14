import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../l10n/app_strings.dart';
import '../models/price_offer.dart';
import '../theme/app_theme.dart';
import 'price_widgets.dart';

/// One seller's row in the price comparison table.
///
/// This is the screen element the whole app exists for: it makes "who is
/// cheapest, by how much, and how current is that" answerable at a glance.
class OfferTile extends StatelessWidget {
  final PriceOffer offer;
  final bool bangla;
  final VoidCallback? onVisit;

  const OfferTile({
    super.key,
    required this.offer,
    required this.bangla,
    this.onVisit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppStrings.of(context);
    final scheme = theme.colorScheme;
    final sellerName = offer.displaySellerName(bangla: bangla);
    final dimmed = !offer.inStock;

    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: offer.isCheapest
              ? scheme.savingsColor.withValues(alpha: 0.07)
              : Colors.transparent,
          border: Border(
            left: BorderSide(
              width: 3,
              color: offer.isCheapest ? scheme.savingsColor : Colors.transparent,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          sellerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (offer.isCheapest) ...[
                        const SizedBox(width: 8),
                        const CheapestBadge(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 10,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (offer.location != null)
                        _MetaText(
                          icon: Icons.place_outlined,
                          label: offer.location!,
                        ),
                      if (offer.rating != null)
                        _MetaText(
                          icon: Icons.star_rounded,
                          label: bangla
                              ? Fmt.toBanglaDigits(
                                  offer.rating!.toStringAsFixed(1))
                              : offer.rating!.toStringAsFixed(1),
                        ),
                      if (!offer.inStock)
                        _MetaText(
                          icon: Icons.remove_shopping_cart_outlined,
                          label: t.outOfStock,
                          color: scheme.error,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  FreshnessBadge(
                    collectedAt: offer.collectedAt,
                    bangla: bangla,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  Fmt.price(offer.price, bangla: bangla) ?? '',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: offer.isCheapest
                        ? scheme.savingsColor
                        : scheme.onSurface,
                  ),
                ),
                if (offer.unit != null)
                  Text(
                    Fmt.unitLabel(offer.unit, bangla: bangla),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                if (!offer.isCheapest &&
                    offer.pctAboveMin != null &&
                    offer.pctAboveMin! > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    t.percentMore(
                      Fmt.percent(offer.pctAboveMin!, bangla: bangla),
                    ),
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: scheme.premiumColor),
                  ),
                ],
                if (offer.productUrl != null && onVisit != null) ...[
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 32,
                    child: TextButton.icon(
                      onPressed: onVisit,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.open_in_new, size: 14),
                      label: Text(
                        t.visitSeller,
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaText extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _MetaText({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: c),
        const SizedBox(width: 3),
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: c)),
      ],
    );
  }
}
