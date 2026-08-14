import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_strings.dart';
import '../models/price_offer.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_image.dart';
import '../widgets/insight_card.dart';
import '../widgets/offer_tile.dart';
import '../widgets/price_history_chart.dart';
import '../widgets/price_widgets.dart';
import '../widgets/regional_price_table.dart';
import '../widgets/status_views.dart';

/// Product detail — and, more importantly, the price comparison.
///
/// The old version showed one price and then a large fabricated "AI Analysis"
/// panel that claimed "Category: Electronics, excellent camera" for every
/// product including a T-shirt. That is gone. What replaces it is the thing the
/// app is actually for: every seller's price, cheapest first, each stamped with
/// when it was last checked.
class ProductDetailScreen extends ConsumerWidget {
  final String productId;

  const ProductDetailScreen({super.key, required this.productId});

  Future<void> _openSeller(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    final messenger = ScaffoldMessenger.of(context);
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open that link')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppStrings.of(context);
    final theme = Theme.of(context);
    final bangla = ref.watch(isBanglaProvider);
    final offersAsync = ref.watch(productOffersProvider(productId));
    final productAsync = ref.watch(productByIdProvider(productId));
    final favorites = ref.watch(favoritesProvider);
    final signedIn = ref.watch(isSignedInProvider);
    final isFavorite = favorites.contains(productId);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.productDetails),
        actions: [
          IconButton(
            tooltip: isFavorite ? t.removeFromFavorites : t.addToFavorites,
            icon: Icon(
              isFavorite ? Icons.favorite : Icons.favorite_border,
              color: isFavorite ? theme.colorScheme.error : null,
            ),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              if (!signedIn) {
                messenger.showSnackBar(
                  SnackBar(content: Text(t.signInToSave)),
                );
                return;
              }
              try {
                final added = await ref
                    .read(favoritesProvider.notifier)
                    .toggle(productId);
                messenger.showSnackBar(SnackBar(
                  content: Text(
                    added ? t.savedToFavorites : t.removedFromFavorites,
                  ),
                  duration: const Duration(seconds: 1),
                ));
              } catch (_) {
                messenger.showSnackBar(
                  SnackBar(content: Text(t.somethingWentWrong)),
                );
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(productOffersProvider(productId));
          ref.invalidate(productByIdProvider(productId));
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            // --- Product header ------------------------------------------
            productAsync.when(
              loading: () => const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => SizedBox(
                height: 220,
                child: ErrorView(
                  error: e,
                  onRetry: () => ref.invalidate(productByIdProvider(productId)),
                ),
              ),
              data: (product) {
                if (product == null) {
                  return SizedBox(
                    height: 220,
                    child: EmptyView(message: t.nothingHere),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: AppImage(
                        url: product.imageUrl,
                        width: double.infinity,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.displayName(bangla: bangla),
                            style: theme.textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          if (product.brand != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              product.brand!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                          if (product.description.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              product.description,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),

            const Divider(height: 24),

            // --- Price comparison ----------------------------------------
            offersAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: ErrorView(
                  error: e,
                  onRetry: () =>
                      ref.invalidate(productOffersProvider(productId)),
                ),
              ),
              data: (offers) => _ComparisonSection(
                offers: offers,
                bangla: bangla,
                onVisit: (url) => _openSeller(context, url),
              ),
            ),

            // --- Statistical analysis (Python service; optional) ----------
            // Renders nothing when the service is offline or has nothing
            // meaningful to report.
            ref.watch(productInsightProvider(productId)).maybeWhen(
                  data: (insight) => Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: InsightCard(insight: insight, bangla: bangla),
                  ),
                  orElse: () => const SizedBox.shrink(),
                ),

            // --- Regional prices -------------------------------------------
            ref.watch(regionalPricesProvider(productId)).maybeWhen(
                  data: (rows) {
                    if (rows.length < 2) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                      child: RegionalPriceTable(rows: rows, bangla: bangla),
                    );
                  },
                  orElse: () => const SizedBox.shrink(),
                ),

            // --- Price history --------------------------------------------
            ref.watch(priceHistoryProvider(productId)).maybeWhen(
                  data: (points) {
                    if (points.length < 2) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.show_chart,
                                      size: 18,
                                      color: theme.colorScheme.primary),
                                  const SizedBox(width: 8),
                                  Text(
                                    t.priceHistory,
                                    style: theme.textTheme.titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const Spacer(),
                                  Text(
                                    t.last30Days,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              PriceHistoryChart(
                                points: points,
                                bangla: bangla,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  orElse: () => const SizedBox.shrink(),
                ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _ComparisonSection extends StatelessWidget {
  final List<PriceOffer> offers;
  final bool bangla;
  final void Function(String url) onVisit;

  const _ComparisonSection({
    required this.offers,
    required this.bangla,
    required this.onVisit,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final theme = Theme.of(context);

    if (offers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: EmptyView(
          icon: Icons.sell_outlined,
          message: t.noPrice,
          hint: t.noPriceHint,
        ),
      );
    }

    final inStock = offers.where((o) => o.inStock).toList();
    final cheapest = inStock.isEmpty ? null : inStock.first;
    final dearest = inStock.isEmpty ? null : inStock.last;
    final savings = (cheapest != null && dearest != null)
        ? dearest.price - cheapest.price
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Headline: the answer, before the table.
        if (cheapest != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.savingsColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: theme.colorScheme.savingsColor.withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.bestPrice,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.savingsColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: PriceDisplay(
                          minPrice: cheapest.price,
                          unit: cheapest.unit,
                          bangla: bangla,
                          large: true,
                        ),
                      ),
                      Flexible(
                        child: Text(
                          cheapest.displaySellerName(bangla: bangla),
                          textAlign: TextAlign.right,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  if (savings > 0) ...[
                    const SizedBox(height: 10),
                    SavingsBadge(savings: savings, bangla: bangla),
                  ],
                  const SizedBox(height: 10),
                  FreshnessBadge(
                    collectedAt: cheapest.collectedAt,
                    bangla: bangla,
                  ),
                ],
              ),
            ),
          ),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(
            children: [
              Text(
                t.comparePrices,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              Text(
                t.sellerCount(offers.length),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const Spacer(),
              IconButton(
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                tooltip: t.freshnessExplainer,
                icon: const Icon(Icons.info_outline),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text(t.priceHistory),
                    content: Text(t.freshnessExplainer),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(t.close),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              for (var i = 0; i < offers.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                OfferTile(
                  offer: offers[i],
                  bangla: bangla,
                  onVisit: offers[i].productUrl != null
                      ? () => onVisit(offers[i].productUrl!)
                      : null,
                ),
              ],
            ],
          ),
        ),

        // Honest footer about how current this data is.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Text(
            t.freshnessExplainer,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }
}

/// Fetches a single product by id, so the detail screen can be opened from a
/// deal card, a favourite, or a deep link without passing the whole object.
final productByIdProvider =
    FutureProvider.family<ProductLike?, String>((ref, id) async {
  final product = await ref.watch(catalogRepositoryProvider).getProduct(id);
  if (product == null) return null;
  return ProductLike(
    id: product.id,
    name: product.name,
    nameBn: product.nameBn,
    brand: product.brand,
    description: product.description,
    imageUrl: product.imageUrl,
    unit: product.unit,
  );
});

/// Minimal view model for the detail header. Keeps the screen independent of
/// which model it was navigated from.
class ProductLike {
  final String id;
  final String name;
  final String? nameBn;
  final String? brand;
  final String description;
  final String? imageUrl;
  final String? unit;

  const ProductLike({
    required this.id,
    required this.name,
    this.nameBn,
    this.brand,
    this.description = '',
    this.imageUrl,
    this.unit,
  });

  String displayName({required bool bangla}) {
    if (bangla && nameBn != null && nameBn!.trim().isNotEmpty) return nameBn!;
    return name;
  }
}
