import 'package:flutter/material.dart';

import '../models/product_summary.dart';
import 'app_image.dart';
import 'price_widgets.dart';

/// The core list item.
///
/// Answers the three questions a price-comparison user actually has, in one
/// glance: **what does it cost**, **across how many sellers**, and **how old is
/// that number**. The original card showed only a name, a description and a
/// single price in the least prominent corner.
class ProductCard extends StatelessWidget {
  final ProductSummary product;
  final bool bangla;
  final VoidCallback onTap;
  final bool isFavorite;
  final VoidCallback? onToggleFavorite;

  const ProductCard({
    super.key,
    required this.product,
    required this.bangla,
    required this.onTap,
    this.isFavorite = false,
    this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = product.displayName(bangla: bangla);

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppImage(
                url: product.imageUrl,
                width: 76,
                height: 76,
                radius: 10,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (onToggleFavorite != null)
                          _FavoriteButton(
                            isFavorite: isFavorite,
                            onPressed: onToggleFavorite!,
                          ),
                      ],
                    ),
                    if (product.brand != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        product.brand!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: 8),
                    PriceDisplay(
                      minPrice: product.minPrice,
                      maxPrice: product.maxPrice,
                      unit: product.unit,
                      bangla: bangla,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (product.sellerCount > 0)
                          SellerCountChip(
                            count: product.sellerCount,
                            bangla: bangla,
                          ),
                        if (product.savings != null)
                          SavingsBadge(
                            savings: product.savings!,
                            percent: product.savingsPercent,
                            bangla: bangla,
                          ),
                      ],
                    ),
                    if (product.hasPrice) ...[
                      const SizedBox(height: 6),
                      FreshnessBadge(
                        collectedAt: product.lastUpdated,
                        bangla: bangla,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FavoriteButton extends StatelessWidget {
  final bool isFavorite;
  final VoidCallback onPressed;

  const _FavoriteButton({required this.isFavorite, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton(
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        iconSize: 20,
        onPressed: onPressed,
        icon: Icon(
          isFavorite ? Icons.favorite : Icons.favorite_border,
          color: isFavorite ? scheme.error : scheme.onSurfaceVariant,
        ),
        tooltip: isFavorite ? 'Remove from favourites' : 'Add to favourites',
      ),
    );
  }
}

/// Compact horizontal card used in the "Biggest savings" carousel.
class DealCard extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final double minPrice;
  final double maxPrice;
  final double savings;
  final int sellerCount;
  final DateTime? lastUpdated;
  final String? unit;
  final bool bangla;
  final VoidCallback onTap;

  const DealCard({
    super.key,
    required this.name,
    this.imageUrl,
    required this.minPrice,
    required this.maxPrice,
    required this.savings,
    required this.sellerCount,
    this.lastUpdated,
    this.unit,
    required this.bangla,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 168,
      child: Card(
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppImage(url: imageUrl, height: 96, width: double.infinity),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 36,
                      child: Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 6),
                    PriceDisplay(
                      minPrice: minPrice,
                      maxPrice: maxPrice,
                      unit: unit,
                      bangla: bangla,
                    ),
                    const SizedBox(height: 6),
                    SavingsBadge(savings: savings, bangla: bangla),
                    const SizedBox(height: 6),
                    FreshnessBadge(
                      collectedAt: lastUpdated,
                      bangla: bangla,
                      compact: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
