import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_strings.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../widgets/status_views.dart';

/// Map tab.
///
/// The mockup shows a live map with market pins, TCB truck positions and a
/// price-intensity overlay. Two things are missing before that can be truthful:
///
///   1. a maps SDK and API key (google_maps_flutter / MapLibre)
///   2. a live TCB truck feed — no public API for this exists as far as I know
///
/// Rather than draw a fake map with invented pins, this shows what the database
/// genuinely knows: which markets exist, where, and in which division. That is
/// real, and it is the foundation the map will sit on.
class MapScreen extends ConsumerWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppStrings.of(context);
    final theme = Theme.of(context);
    final bangla = ref.watch(isBanglaProvider);
    final regions = ref.watch(regionsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t.tabMap)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // Honest placeholder instead of a decorative fake map.
          Container(
            height: 180,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.map_outlined,
                    size: 40, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(height: 12),
                Text(
                  t.mapComingSoon,
                  style: theme.textTheme.titleSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    t.mapComingSoonHint,
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          Text(
            t.nearbyMarkets,
            style:
                theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(t.marketsByDivision, style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),

          regions.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => ErrorView(
              error: e,
              onRetry: () => ref.invalidate(regionsProvider),
            ),
            data: (list) {
              if (list.isEmpty) {
                return EmptyView(message: t.nothingHere);
              }
              final selected = ref.watch(selectedRegionProvider);
              return Column(
                children: [
                  for (final r in list) ...[
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: r.slug == selected
                              ? AppTheme.primaryContainer
                              : theme.colorScheme.surfaceContainerHigh,
                          child: Icon(
                            Icons.storefront_outlined,
                            size: 18,
                            color: r.slug == selected
                                ? Colors.white
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        title: Text(
                          r.displayName(bangla: bangla),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        trailing: r.slug == selected
                            ? Chip(
                                label: Text(t.active),
                                backgroundColor: AppTheme.secondaryContainer,
                                labelStyle: theme.textTheme.labelSmall?.copyWith(
                                  color: AppTheme.onSecondaryContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                                side: BorderSide.none,
                              )
                            : const Icon(Icons.chevron_right),
                        onTap: () => ref
                            .read(selectedRegionProvider.notifier)
                            .state = r.slug,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
