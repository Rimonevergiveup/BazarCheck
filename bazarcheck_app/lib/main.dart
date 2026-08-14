import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n/app_strings.dart';
import 'providers.dart';
import 'screens/compare_screen.dart';
import 'screens/home_screen.dart';
import 'screens/map_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/trends_screen.dart';
import 'supabase_client.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initSupabase();
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const BazarCheckApp(),
    ),
  );
}

class BazarCheckApp extends ConsumerWidget {
  const BazarCheckApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return MaterialApp(
      title: 'BazarCheck',
      debugShowCheckedModeBanner: false,

      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeMode,

      locale: settings.locale,
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      // No AuthGate at the root any more. Browsing and price comparison are
      // fully anonymous; signing in is a pushed route reached from Favourites
      // or Account. That removes the funnel-killing login wall AND the bug
      // where replacing the root route stranded users on the login form.
      home: const AppShell(),
    );
  }
}

/// Bottom-navigation shell.
///
/// Uses an [IndexedStack] so each tab keeps its scroll position and provider
/// state when you switch away and back. The selected index lives in a provider
/// so the home screen can hand off to the search tab.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppStrings.of(context);
    final index = ref.watch(selectedTabProvider);

    return Scaffold(
      body: IndexedStack(
        index: index,
        children: const [
          HomeScreen(),
          CompareScreen(),
          MapScreen(),
          TrendsScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) =>
            ref.read(selectedTabProvider.notifier).state = i,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: t.tabHome,
          ),
          NavigationDestination(
            icon: const Icon(Icons.compare_arrows),
            selectedIcon: const Icon(Icons.compare_arrows),
            label: t.tabCompare,
          ),
          NavigationDestination(
            icon: const Icon(Icons.map_outlined),
            selectedIcon: const Icon(Icons.map),
            label: t.tabMap,
          ),
          NavigationDestination(
            icon: const Icon(Icons.trending_up),
            selectedIcon: const Icon(Icons.trending_up),
            label: t.tabTrends,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: t.tabSettings,
          ),
        ],
      ),
    );
  }
}
