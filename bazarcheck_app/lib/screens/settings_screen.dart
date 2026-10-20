import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_strings.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import 'auth/login_screen.dart';
import 'favorites_screen.dart';

/// Settings — profile, language, regional market, theme.
///
/// Layout follows the mockup: account card, a two-button language toggle, the
/// eight divisions as a grid, then preferences.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppStrings.of(context);
    final theme = Theme.of(context);
    final bangla = ref.watch(isBanglaProvider);
    final user = ref.watch(currentUserProvider);
    final settings = ref.watch(settingsProvider);
    final regions = ref.watch(regionsProvider);
    final selectedRegion = ref.watch(selectedRegionProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t.appName)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // --- Account --------------------------------------------------
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: user != null
                  ? Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: AppTheme.primaryContainer,
                          child: Text(
                            (user.email?.isNotEmpty ?? false)
                                ? user.email![0].toUpperCase()
                                : 'U',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user.email ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              Text(t.signedIn, style: theme.textTheme.bodySmall),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.signInToSave,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(t.signInToSaveHint,
                            style: theme.textTheme.bodySmall),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const LoginScreen()),
                            ),
                            icon: const Icon(Icons.login),
                            label: Text(t.signIn),
                          ),
                        ),
                      ],
                    ),
            ),
          ),

          // --- Saved -----------------------------------------------------
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(Icons.favorite_border,
                  color: theme.colorScheme.onSurfaceVariant),
              title: Text(t.favorites),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FavoritesScreen()),
              ),
            ),
          ),

          // --- Language -------------------------------------------------
          _Label(t.interfaceLanguage),
          Row(
            children: [
              Expanded(
                child: _ToggleButton(
                  label: 'English',
                  selected: !bangla,
                  onTap: () => ref
                      .read(settingsProvider.notifier)
                      .setLocale(const Locale('en')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ToggleButton(
                  label: 'বাংলা',
                  selected: bangla,
                  onTap: () => ref
                      .read(settingsProvider.notifier)
                      .setLocale(const Locale('bn')),
                ),
              ),
            ],
          ),

          // --- Regional market ------------------------------------------
          _Label(t.regionalMarket),
          regions.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => Text(t.somethingWentWrong,
                style: theme.textTheme.bodySmall),
            data: (list) => GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 3.2,
              children: [
                for (final r in list)
                  _ToggleButton(
                    label: r.displayName(bangla: bangla),
                    selected: r.slug == selectedRegion,
                    icon: Icons.location_city_outlined,
                    onTap: () async {
                      ref.read(selectedRegionProvider.notifier).state = r.slug;
                      await ref
                          .read(sharedPreferencesProvider)
                          .setString('settings.region', r.slug);
                    },
                  ),
              ],
            ),
          ),

          // --- Appearance -----------------------------------------------
          // Uses the same toggle as language and division rather than
          // RadioListTile, whose groupValue/onChanged were deprecated in favour
          // of a RadioGroup ancestor. This is consistent with the rest of the
          // screen and carries no deprecated API.
          _Label(t.theme),
          Row(
            children: [
              for (final mode in ThemeMode.values) ...[
                Expanded(
                  child: _ToggleButton(
                    label: switch (mode) {
                      ThemeMode.system => t.themeSystem,
                      ThemeMode.light => t.themeLight,
                      ThemeMode.dark => t.themeDark,
                    },
                    selected: settings.themeMode == mode,
                    onTap: () =>
                        ref.read(settingsProvider.notifier).setThemeMode(mode),
                  ),
                ),
                if (mode != ThemeMode.values.last) const SizedBox(width: 10),
              ],
            ],
          ),

          if (user != null) ...[
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  ref.read(guestModeProvider.notifier).state = false;
                  await ref.read(authServiceProvider).signOut();
                },
                icon: const Icon(Icons.logout),
                label: Text(t.signOut),
                style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error),
              ),
            ),
          ],

          const SizedBox(height: 24),
          Center(
            child: Text(
              '${t.appName} · 1.0',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 24, 2, 10),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: 10,
              letterSpacing: 0.7,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

/// Bordered pill that fills with the brand colour when selected — the language
/// and division selectors in the mockup.
class _ToggleButton extends StatelessWidget {
  final String label;
  final bool selected;
  final IconData? icon;
  final VoidCallback onTap;

  const _ToggleButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? AppTheme.primaryContainer
          : theme.colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 52,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? AppTheme.primaryContainer
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 16,
                    color: selected
                        ? Colors.white
                        : theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: selected ? Colors.white : theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
