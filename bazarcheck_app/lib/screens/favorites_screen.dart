import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_strings.dart';
import '../providers.dart';
import '../widgets/product_card.dart';
import '../widgets/status_views.dart';
import 'auth/login_screen.dart';
import 'product_detail_screen.dart';

/// Saved products, with live prices.
///
/// This is the only place an account is actually required — browsing and
/// comparing stay anonymous.
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppStrings.of(context);
    final bangla = ref.watch(isBanglaProvider);
    final signedIn = ref.watch(isSignedInProvider);

    if (!signedIn) {
      return Scaffold(
        appBar: AppBar(title: Text(t.favorites)),
        body: Center(
          child: EmptyView(
            icon: Icons.favorite_border,
            message: t.signInToSave,
            hint: t.signInToSaveHint,
            action: FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              ),
              icon: const Icon(Icons.login),
              label: Text(t.signIn),
            ),
          ),
        ),
      );
    }

    final favorites = ref.watch(favoriteProductsProvider);
    final ids = ref.watch(favoritesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t.favorites)),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(favoriteProductsProvider),
        child: favorites.when(
          loading: () => const ListSkeleton(count: 3),
          error: (e, _) => RefreshableCenter(
            child: ErrorView(
              error: e,
              onRetry: () => ref.invalidate(favoriteProductsProvider),
            ),
          ),
          data: (items) {
            if (items.isEmpty) {
              return RefreshableCenter(
                child: EmptyView(
                  icon: Icons.favorite_border,
                  message: t.noFavorites,
                  hint: t.noFavoritesHint,
                ),
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final p = items[i];
                return ProductCard(
                  product: p,
                  bangla: bangla,
                  isFavorite: ids.contains(p.id),
                  onToggleFavorite: () =>
                      ref.read(favoritesProvider.notifier).toggle(p.id),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProductDetailScreen(productId: p.id),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
