import 'package:bazarcheck_app/l10n/app_strings.dart';
import 'package:bazarcheck_app/models/product_summary.dart';
import 'package:bazarcheck_app/theme/app_theme.dart';
import 'package:bazarcheck_app/widgets/price_widgets.dart';
import 'package:bazarcheck_app/widgets/product_card.dart';
import 'package:bazarcheck_app/widgets/status_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wraps a widget in the minimum app scaffolding its lookups need.
Widget wrap(Widget child, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    locale: locale,
    theme: AppTheme.light(),
    supportedLocales: AppStrings.supportedLocales,
    localizationsDelegates: const [
      AppStrings.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: child),
  );
}

ProductSummary product({
  double? min,
  double? max,
  int sellers = 0,
  DateTime? updated,
  String name = 'Miniket Rice',
  String? nameBn = 'মিনিকেট চাল',
}) {
  return ProductSummary(
    id: 'p1',
    name: name,
    nameBn: nameBn,
    minPrice: min,
    maxPrice: max,
    sellerCount: sellers,
    lastUpdated: updated,
    unit: 'kg',
  );
}

void main() {
  group('PriceDisplay', () {
    testWidgets('shows "Price unavailable" instead of ৳0 when there is no price',
        (tester) async {
      await tester.pumpWidget(
          wrap(const PriceDisplay(minPrice: null, bangla: false)));

      expect(find.text('Price unavailable'), findsOneWidget);
      expect(find.textContaining('৳0'), findsNothing);
    });

    testWidgets('shows a single price when sellers agree', (tester) async {
      await tester.pumpWidget(
          wrap(const PriceDisplay(minPrice: 72, maxPrice: 72, bangla: false)));

      expect(find.text('৳72'), findsOneWidget);
      expect(find.text('from'), findsNothing);
    });

    testWidgets('prefixes "from" when there is a spread', (tester) async {
      await tester.pumpWidget(
          wrap(const PriceDisplay(minPrice: 72, maxPrice: 90, bangla: false)));

      expect(find.text('from'), findsOneWidget);
      expect(find.text('৳72'), findsOneWidget);
    });

    testWidgets('renders Bangla digits in Bangla mode', (tester) async {
      await tester.pumpWidget(wrap(
        const PriceDisplay(minPrice: 1234, bangla: true),
        locale: const Locale('bn'),
      ));

      expect(find.text('৳১,২৩৪'), findsOneWidget);
    });
  });

  group('FreshnessBadge', () {
    testWidgets('shows how old the price is', (tester) async {
      await tester.pumpWidget(wrap(FreshnessBadge(
        collectedAt: DateTime.now().subtract(const Duration(hours: 3)),
        bangla: false,
      )));

      expect(find.textContaining('3h ago'), findsOneWidget);
    });

    testWidgets('says unknown rather than implying freshness', (tester) async {
      await tester
          .pumpWidget(wrap(const FreshnessBadge(collectedAt: null, bangla: false)));

      expect(find.textContaining('unknown'), findsOneWidget);
    });
  });

  group('ProductCard', () {
    testWidgets('shows name, price, seller count and freshness', (tester) async {
      await tester.pumpWidget(wrap(ProductCard(
        product: product(
          min: 72,
          max: 90,
          sellers: 3,
          updated: DateTime.now().subtract(const Duration(hours: 2)),
        ),
        bangla: false,
        onTap: () {},
      )));

      expect(find.text('Miniket Rice'), findsOneWidget);
      expect(find.text('৳72'), findsOneWidget);
      expect(find.text('3 sellers'), findsOneWidget);
      expect(find.textContaining('2h ago'), findsOneWidget);
      expect(find.textContaining('Save'), findsOneWidget); // ৳18 spread
    });

    testWidgets('uses the Bangla name in Bangla mode', (tester) async {
      await tester.pumpWidget(wrap(
        ProductCard(
          product: product(min: 72, sellers: 1),
          bangla: true,
          onTap: () {},
        ),
        locale: const Locale('bn'),
      ));

      expect(find.text('মিনিকেট চাল'), findsOneWidget);
    });

    testWidgets('falls back to English when no Bangla name exists',
        (tester) async {
      await tester.pumpWidget(wrap(
        ProductCard(
          product: product(min: 72, nameBn: null),
          bangla: true,
          onTap: () {},
        ),
        locale: const Locale('bn'),
      ));

      expect(find.text('Miniket Rice'), findsOneWidget);
    });

    testWidgets('does not show a savings badge with a single seller',
        (tester) async {
      await tester.pumpWidget(wrap(ProductCard(
        product: product(min: 72, max: 72, sellers: 1),
        bangla: false,
        onTap: () {},
      )));

      expect(find.textContaining('Save'), findsNothing);
      expect(find.text('1 seller'), findsOneWidget);
    });

    testWidgets('is tappable', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(ProductCard(
        product: product(min: 72),
        bangla: false,
        onTap: () => tapped = true,
      )));

      await tester.tap(find.byType(ProductCard));
      expect(tapped, isTrue);
    });

    testWidgets('hides the favourite button when signed out', (tester) async {
      await tester.pumpWidget(wrap(ProductCard(
        product: product(min: 72),
        bangla: false,
        onTap: () {},
        // onToggleFavorite omitted => anonymous user
      )));

      expect(find.byIcon(Icons.favorite_border), findsNothing);
    });

    testWidgets('shows the favourite button when signed in', (tester) async {
      await tester.pumpWidget(wrap(ProductCard(
        product: product(min: 72),
        bangla: false,
        onTap: () {},
        onToggleFavorite: () {},
      )));

      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    });
  });

  group('ErrorView', () {
    testWidgets('never leaks the raw exception to the user', (tester) async {
      await tester.pumpWidget(wrap(ErrorView(
        error: Exception('PostgrestException: relation "prices" does not exist'),
        onRetry: () {},
      )));

      expect(find.textContaining('PostgrestException'), findsNothing);
      expect(find.textContaining('relation'), findsNothing);
      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('recognises a network failure', (tester) async {
      await tester.pumpWidget(wrap(
          ErrorView(error: Exception('SocketException: Failed host lookup'))));

      expect(find.text('Connection problem'), findsOneWidget);
    });

    testWidgets('retry callback fires', (tester) async {
      var retried = false;
      await tester
          .pumpWidget(wrap(ErrorView(error: 'x', onRetry: () => retried = true)));

      await tester.tap(find.text('Retry'));
      expect(retried, isTrue);
    });
  });

  group('AppStrings', () {
    testWidgets('resolves English by default', (tester) async {
      late AppStrings t;
      await tester.pumpWidget(wrap(Builder(builder: (context) {
        t = AppStrings.of(context);
        return const SizedBox();
      })));

      expect(t.isBangla, isFalse);
      expect(t.search, 'Search');
      expect(t.sellerCount(3), '3 sellers');
      expect(t.sellerCount(1), '1 seller');
    });

    testWidgets('resolves Bangla and pluralises with Bangla digits',
        (tester) async {
      late AppStrings t;
      await tester.pumpWidget(wrap(
        Builder(builder: (context) {
          t = AppStrings.of(context);
          return const SizedBox();
        }),
        locale: const Locale('bn'),
      ));

      expect(t.isBangla, isTrue);
      expect(t.search, 'খুঁজুন');
      expect(t.sellerCount(3), '৩ টি দোকান');
    });
  });

  group('EmptyView', () {
    testWidgets('renders message, hint and an optional action', (tester) async {
      await tester.pumpWidget(wrap(EmptyView(
        message: 'No products found',
        hint: 'Try a shorter word',
        action: FilledButton(onPressed: () {}, child: const Text('Reset')),
      )));

      expect(find.text('No products found'), findsOneWidget);
      expect(find.text('Try a shorter word'), findsOneWidget);
      expect(find.text('Reset'), findsOneWidget);
    });
  });
}
