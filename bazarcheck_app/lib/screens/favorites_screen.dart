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
class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        ref.read(favoritePaginationProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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

    final pagedResults = ref.watch(favoritePaginationProvider);
    final ids = ref.watch(favoritesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t.favorites)),
      body: RefreshIndicator(
        onRefresh: () async => ref.read(favoritePaginationProvider.notifier).refresh(),
        child: pagedResults.isLoadingFirstPage
            ? const ListSkeleton(count: 3)
            : pagedResults.error != null && pagedResults.items.isEmpty
                ? RefreshableCenter(
                    child: ErrorView(
                      error: pagedResults.error,
                      onRetry: () => ref.read(favoritePaginationProvider.notifier).refresh(),
                    ),
                  )
                : pagedResults.isEmpty
                    ? RefreshableCenter(
                        child: EmptyView(
                          icon: Icons.favorite_border,
                          message: t.noFavorites,
                          hint: t.noFavoritesHint,
                        ),
                      )
                    : ListView.separated(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(12),
                        itemCount: pagedResults.items.length + (pagedResults.isLoadingMore ? 1 : 0),
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          if (i >= pagedResults.items.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          final p = pagedResults.items[i];
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
                      ),
      ),
    );
  }
}
