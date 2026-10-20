import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n/app_strings.dart';
import 'providers.dart';
import 'screens/auth/login_screen.dart';
import 'screens/compare_screen.dart';
import 'screens/home_screen.dart';
import 'screens/map_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/trends_screen.dart';
import 'supabase_client.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  ErrorWidget.builder = (FlutterErrorDetails details) {
    debugPrint('FLUTTER ERROR CAUGHT: ${details.exception}');
    debugPrint('STACK TRACE:\n${details.stack}');
    return const Scaffold(
      body: Center(
        child: Text('Error rendering widget! Check logs.'),
      ),
    );
  };

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

    final isBangla = settings.locale.languageCode == 'bn';

    return MaterialApp(
      title: 'BazarCheck',
      debugShowCheckedModeBanner: false,

      theme: AppTheme.light(isBangla: isBangla),
      darkTheme: AppTheme.dark(isBangla: isBangla),
      themeMode: settings.themeMode,

      locale: settings.locale,
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      // The first interface is Login/Signup. Once authenticated, or if the
      // user taps "Continue without an account", they enter AppShell.
      home: const RootGate(),
    );
  }
}

/// Initial gate: presents LoginScreen as the entry interface, transitioning to
/// AppShell once the user signs in, signs up, or chooses guest mode.
class RootGate extends ConsumerWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final isGuest = ref.watch(guestModeProvider);

    if (user != null || isGuest) {
      return const AppShell();
    }

    return const LoginScreen(isRoot: true);
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
          SearchScreen(),
          CompareScreen(),
          MapScreen(),
          TrendsScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Theme.of(context).brightness == Brightness.light
                  ? const Color(0xFFE2E8F0)
                  : const Color(0xFF262E3B),
              width: 1,
            ),
          ),
        ),
        child: NavigationBar(
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
              icon: const Icon(Icons.search),
              selectedIcon: const Icon(Icons.search),
              label: t.tabSearch,
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
      ),
    );
  }
}
