import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Bilingual strings for BazarCheck (English + Bangla).
///
/// Hand-rolled rather than ARB/codegen on purpose: it is type-safe, needs no
/// build step, and cannot get out of sync with generated output. To add a
/// string, add a getter here and a value in both maps below — the compiler
/// will point at anything you miss.
///
/// Usage:  `final t = AppStrings.of(context);  Text(t.search)`
class AppStrings {
  final Locale locale;
  const AppStrings(this.locale);

  static const supportedLocales = [Locale('en'), Locale('bn')];

  static AppStrings of(BuildContext context) =>
      Localizations.of<AppStrings>(context, AppStrings) ??
      const AppStrings(Locale('en'));

  static const LocalizationsDelegate<AppStrings> delegate = _AppStringsDelegate();

  /// True when the UI should render Bangla digits and wording.
  bool get isBangla => locale.languageCode == 'bn';

  String _s(String en, String bn) => isBangla ? bn : en;

  // --- App / navigation ----------------------------------------------------
  String get appName        => _s('BazarCheck', 'বাজারচেক');

  // --- Government rates vs local market ------------------------------------
  String get govtFixed      => _s('Govt fixed', 'সরকারি দর');
  String get localMarket    => _s('Local market', 'বাজার দর');
  String get localAverage   => _s('Local avg', 'গড় দর');
  String get priceGap       => _s('Price gap', 'দামের ব্যবধান');
  String get noOfficialRate => _s('No official rate', 'সরকারি দর নেই');
  String amountHigher(String a) => _s('$a higher', '$a বেশি');
  String amountLower(String a)  => _s('$a lower', '$a কম');
  String get statusSpike    => _s('SPIKE', 'বৃদ্ধি');
  String get statusDrop     => _s('DROP', 'হ্রাস');
  String get statusStable   => _s('STABLE', 'স্থিতিশীল');
  String get dailyEssentials => _s('Daily essentials', 'নিত্যপ্রয়োজনীয় পণ্য');
  String get governmentRates => _s('Government fixed rates', 'সরকারি নির্ধারিত দর');
  String get regionalPrices  => _s('Regional prices', 'বিভাগভিত্তিক দাম');
  String get division        => _s('Division', 'বিভাগ');
  String get productType     => _s('Product type', 'পণ্যের ধরন');
  String get allProducts     => _s('All products', 'সব পণ্য');
  String get currentLocation => _s('Current location', 'বর্তমান অবস্থান');
  String get regionalMarket  => _s('Regional market', 'আঞ্চলিক বাজার');
  String get viewAll         => _s('View all', 'সব দেখুন');
  String get marketPulse     => _s('Market pulse', 'বাজার পরিস্থিতি');
  String get vsGovtRate      => _s('vs govt rate', 'সরকারি দরের তুলনায়');
  String get trend           => _s('Trend', 'প্রবণতা');
  String get signedIn        => _s('Signed in', 'সাইন ইন করা আছে');
  String get interfaceLanguage => _s('Interface language', 'ভাষা');

  // --- Sample-data disclosure ----------------------------------------------
  // Shown wherever government rates appear. The app must never let sample
  // figures pass as official ones.
  String get sampleDataBadge => _s('SAMPLE', 'নমুনা');
  String get sampleDataNotice => _s(
        'Government rates shown here are sample data, not official figures.',
        'এখানে দেখানো সরকারি দর নমুনা তথ্য, প্রকৃত সরকারি দর নয়।',
      );

  // --- Tabs -----------------------------------------------------------------
  String get tabHome     => _s('HOME', 'হোম');
  String get tabSearch   => _s('SEARCH', 'খোঁজুন');
  String get tabCompare  => _s('COMPARE', 'তুলনা');
  String get tabMap      => _s('MAP', 'মানচিত্র');
  String get tabTrends   => _s('TRENDS', 'প্রবণতা');
  String get tabSettings => _s('SETTINGS', 'সেটিংস');

  // --- Map (not built yet) --------------------------------------------------
  String get mapComingSoon => _s('Map view is not available yet',
                                 'মানচিত্র এখনো চালু হয়নি');
  String get mapComingSoonHint => _s(
        'Market locations are in the database, but the map needs a maps API key '
        'and live TCB truck data before it can show anything truthful.',
        'বাজারের অবস্থান ডাটাবেসে আছে, তবে মানচিত্র দেখাতে ম্যাপ API কী এবং '
        'টিসিবি ট্রাকের সরাসরি তথ্য প্রয়োজন।',
      );
  String get nearbyMarkets => _s('Nearby markets', 'কাছের বাজার');
  String get marketsByDivision => _s('Choose your division to see local prices',
                                     'স্থানীয় দাম দেখতে আপনার বিভাগ বেছে নিন');
  String get active => _s('Active', 'সক্রিয়');
  String get searchEssentials => _s('Search essential goods…',
                                    'নিত্যপ্রয়োজনীয় পণ্য খুঁজুন…');

  // --- Trends ---------------------------------------------------------------
  String get priceAnalytics => _s('Price analytics', 'দাম বিশ্লেষণ');
  String get priceAnalyticsHint => _s(
        'Recorded price movement for essential commodities.',
        'নিত্যপণ্যের দামের রেকর্ড করা পরিবর্তন।',
      );
  String get selectedProduct => _s('Selected product', 'নির্বাচিত পণ্য');
  String get forecastUnavailable =>
      _s('No forecast shown', 'কোনো পূর্বাভাস দেখানো হচ্ছে না');
  String get forecastUnavailableHint => _s(
        'Predicting prices needs months of real observations. This database '
        'holds 30 days of sample data, so any forecast would be guesswork '
        'dressed up as analysis.',
        'দামের পূর্বাভাস দিতে কয়েক মাসের প্রকৃত তথ্য প্রয়োজন। এখানে ৩০ দিনের '
        'নমুনা তথ্য আছে, তাই কোনো পূর্বাভাস হবে শুধুই অনুমান।',
      );
  String get tagline        => _s('Compare prices. Pay less.', 'দাম মিলিয়ে দেখুন, কম দামে কিনুন।');
  String get home           => _s('Home', 'হোম');
  String get browse         => _s('Browse', 'ব্রাউজ');
  String get favorites      => _s('Favourites', 'পছন্দ');
  String get account        => _s('Account', 'অ্যাকাউন্ট');
  String get back           => _s('Back', 'ফিরে যান');
  String get retry          => _s('Retry', 'আবার চেষ্টা করুন');
  String get cancel         => _s('Cancel', 'বাতিল');
  String get close          => _s('Close', 'বন্ধ');
  String get seeAll         => _s('See all', 'সব দেখুন');

  // --- Search --------------------------------------------------------------
  String get search             => _s('Search', 'খুঁজুন');
  String get searchHint         => _s('Search rice, oil, phone…', 'চাল, তেল, ফোন খুঁজুন…');
  String get searchProducts     => _s('Search products', 'পণ্য খুঁজুন');
  String get clear              => _s('Clear', 'মুছুন');
  String get filters            => _s('Filters', 'ফিল্টার');
  String get sortBy             => _s('Sort by', 'সাজান');
  String get sortRelevance      => _s('Best match', 'সেরা মিল');
  String get sortPriceLow       => _s('Price: low to high', 'দাম: কম থেকে বেশি');
  String get sortPriceHigh      => _s('Price: high to low', 'দাম: বেশি থেকে কম');
  String get sortName           => _s('Name (A–Z)', 'নাম (ক–হ)');
  String get sortNewest         => _s('Newest', 'নতুন');
  String get priceRange         => _s('Price range', 'দামের সীমা');
  String get minPrice           => _s('Min', 'সর্বনিম্ন');
  String get maxPrice           => _s('Max', 'সর্বোচ্চ');
  String get apply              => _s('Apply', 'প্রয়োগ');
  String get reset              => _s('Reset', 'রিসেট');
  String get allCategories      => _s('All categories', 'সব ক্যাটাগরি');

  String resultsCount(int n) => isBangla
      ? '${_bn(n)} টি ফলাফল'
      : n == 1 ? '1 result' : '$n results';

  String get noResults        => _s('No products found', 'কোনো পণ্য পাওয়া যায়নি');
  String noResultsFor(String q) =>
      _s('Nothing matched "$q"', '"$q" এর সাথে কিছু মেলেনি');
  String get noResultsHint    => _s(
        'Try a shorter word, check the spelling, or search in Bangla.',
        'ছোট শব্দ লিখুন, বানান দেখে নিন, অথবা ইংরেজিতে খুঁজুন।',
      );
  String get startSearching   => _s('Search for a product to compare prices',
                                    'দাম তুলনা করতে পণ্য খুঁজুন');

  // --- Prices --------------------------------------------------------------
  String get price            => _s('Price', 'দাম');
  String get from             => _s('from', 'থেকে');
  String get cheapest         => _s('Cheapest', 'সবচেয়ে কম');
  String get bestPrice        => _s('Best price', 'সেরা দাম');
  String get noPrice          => _s('Price unavailable', 'দাম পাওয়া যায়নি');
  String get noPriceHint      => _s('No seller has listed a price yet',
                                    'এখনো কোনো বিক্রেতা দাম দেয়নি');
  String get outOfStock       => _s('Out of stock', 'স্টকে নেই');
  String get inStock          => _s('In stock', 'স্টকে আছে');
  String get comparePrices    => _s('Compare prices', 'দাম তুলনা করুন');
  String get allOffers        => _s('All sellers', 'সব বিক্রেতা');
  String get priceHistory     => _s('Price history', 'দামের ইতিহাস');
  String get visitSeller      => _s('Visit seller', 'বিক্রেতার সাইটে যান');

  // --- Price history / trend -----------------------------------------------
  String get notEnoughHistory => _s(
        'Not enough history yet — check back in a few days.',
        'যথেষ্ট তথ্য নেই — কয়েকদিন পর আবার দেখুন।',
      );
  String get lowest  => _s('Low', 'সর্বনিম্ন');
  String get highest => _s('High', 'সর্বোচ্চ');
  String trendFalling(String pct) => _s('Down $pct in 30 days',
                                        '৩০ দিনে $pct কমেছে');
  String trendRising(String pct)  => _s('Up $pct in 30 days',
                                        '৩০ দিনে $pct বেড়েছে');
  String get trendStable => _s('Steady over 30 days', '৩০ দিন ধরে স্থিতিশীল');
  String get last30Days  => _s('Last 30 days', 'গত ৩০ দিন');

  // --- Price insights (from the Python service) ----------------------------
  String get insights        => _s('Price analysis', 'দাম বিশ্লেষণ');
  String get goodTimeToBuy   => _s('Good time to buy', 'কেনার ভালো সময়');
  String get goodTimeHint    => _s('The cheapest price is at or near its recorded low.',
                                   'সবচেয়ে কম দাম এখন রেকর্ড করা সর্বনিম্নের কাছাকাছি।');
  String get medianPrice     => _s('Typical price', 'সাধারণ দাম');
  String get priceSpread     => _s('Spread', 'দামের পার্থক্য');
  String staleSellers(int n) => isBangla
      ? '${_bn(n)} টি দোকানের দাম পুরোনো'
      : n == 1 ? '1 seller\'s price is old' : '$n sellers\' prices are old';

  // --- Pagination ----------------------------------------------------------
  String get loadingMore   => _s('Loading more…', 'আরও লোড হচ্ছে…');
  String get endOfResults  => _s('That\'s everything', 'এটুকুই সব');
  String get loadMore      => _s('Load more', 'আরও দেখুন');

  String sellerCount(int n) => isBangla
      ? '${_bn(n)} টি দোকান'
      : n == 1 ? '1 seller' : '$n sellers';

  String youSave(String amount) =>
      _s('Save $amount', '$amount সাশ্রয়');

  String percentMore(String pct) =>
      _s('$pct more', '$pct বেশি');

  // --- Freshness -----------------------------------------------------------
  String updatedAgo(String rel) => _s('Updated $rel', '$rel আপডেট');
  String get priceMayBeOld => _s(
        'This price may be out of date',
        'এই দাম পুরোনো হতে পারে',
      );
  String get freshnessExplainer => _s(
        'Prices are shown with the time they were last checked so you can judge how current they are.',
        'প্রতিটি দামের সাথে শেষ কবে যাচাই হয়েছে তা দেখানো হয়, যাতে আপনি বুঝতে পারেন দামটি কতটা সাম্প্রতিক।',
      );

  // --- Deals / home --------------------------------------------------------
  String get bestDeals        => _s('Biggest savings', 'সবচেয়ে বেশি সাশ্রয়');
  String get bestDealsHint    => _s('Same product, very different prices',
                                    'একই পণ্য, দামে বড় পার্থক্য');
  String get browseCategories => _s('Browse by category', 'ক্যাটাগরি অনুযায়ী দেখুন');
  String get popularNow       => _s('Popular now', 'এখন জনপ্রিয়');

  // --- Product -------------------------------------------------------------
  String get productDetails   => _s('Product details', 'পণ্যের বিবরণ');
  String get description      => _s('Description', 'বিবরণ');
  String get brand            => _s('Brand', 'ব্র্যান্ড');
  String get category         => _s('Category', 'ক্যাটাগরি');
  String get addToFavorites   => _s('Add to favourites', 'পছন্দে যোগ করুন');
  String get removeFromFavorites => _s('Remove from favourites', 'পছন্দ থেকে সরান');
  String get savedToFavorites => _s('Saved to favourites', 'পছন্দে যুক্ত হয়েছে');
  String get removedFromFavorites => _s('Removed', 'সরানো হয়েছে');

  // --- Empty / error states ------------------------------------------------
  String get somethingWentWrong => _s('Something went wrong', 'কিছু একটা ভুল হয়েছে');
  String get connectionProblem  => _s('Connection problem', 'সংযোগ সমস্যা');
  String get connectionHint     => _s('Check your internet and try again.',
                                      'ইন্টারনেট সংযোগ দেখে আবার চেষ্টা করুন।');
  String get nothingHere        => _s('Nothing here yet', 'এখানে এখনো কিছু নেই');
  String get noFavorites        => _s('No favourites yet', 'এখনো কোনো পছন্দ নেই');
  String get noFavoritesHint    => _s('Tap the heart on any product to save it here.',
                                      'যেকোনো পণ্যের হার্ট আইকনে চাপ দিয়ে এখানে রাখুন।');
  String get loading            => _s('Loading…', 'লোড হচ্ছে…');

  // --- Auth ----------------------------------------------------------------
  String get signIn           => _s('Sign in', 'সাইন ইন');
  String get signUp           => _s('Sign up', 'সাইন আপ');
  String get signOut          => _s('Sign out', 'সাইন আউট');
  String get email            => _s('Email', 'ইমেইল');
  String get password         => _s('Password', 'পাসওয়ার্ড');
  String get confirmPassword  => _s('Confirm password', 'পাসওয়ার্ড নিশ্চিত করুন');
  String get createAccount    => _s('Create account', 'অ্যাকাউন্ট তৈরি করুন');
  String get noAccountYet     => _s("Don't have an account? Sign up",
                                    'অ্যাকাউন্ট নেই? সাইন আপ করুন');
  String get haveAccount      => _s('Already have an account? Sign in',
                                    'অ্যাকাউন্ট আছে? সাইন ইন করুন');
  String get continueAsGuest  => _s('Continue without an account',
                                    'অ্যাকাউন্ট ছাড়া চালিয়ে যান');
  String get invalidEmail     => _s('Enter a valid email', 'সঠিক ইমেইল দিন');
  String get passwordTooShort => _s('At least 8 characters', 'কমপক্ষে ৮ অক্ষর');
  String get passwordsDontMatch => _s('Passwords do not match',
                                      'পাসওয়ার্ড মিলছে না');
  String get accountCreated   => _s('Account created. Check your email to confirm.',
                                    'অ্যাকাউন্ট তৈরি হয়েছে। ইমেইল দেখে নিশ্চিত করুন।');
  String get signInToSave     => _s('Sign in to save favourites',
                                    'পছন্দ সংরক্ষণ করতে সাইন ইন করুন');
  String get signInToSaveHint => _s(
        'Browsing and comparing prices is free — an account only keeps your favourites.',
        'দাম দেখা ও তুলনা করা সম্পূর্ণ ফ্রি — অ্যাকাউন্ট শুধু আপনার পছন্দ সংরক্ষণ করে।',
      );

  // --- Settings ------------------------------------------------------------
  String get language         => _s('Language', 'ভাষা');
  String get english          => _s('English', 'English');
  String get bangla           => _s('Bangla', 'বাংলা');
  String get theme            => _s('Theme', 'থিম');
  String get themeSystem      => _s('System', 'সিস্টেম');
  String get themeLight       => _s('Light', 'লাইট');
  String get themeDark        => _s('Dark', 'ডার্ক');
  String get settings         => _s('Settings', 'সেটিংস');

  static String _bn(int n) {
    const d = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];
    return n.toString().split('').map((c) {
      final i = int.tryParse(c);
      return i == null ? c : d[i];
    }).join();
  }
}

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppStrings.supportedLocales.any((l) => l.languageCode == locale.languageCode);

  @override
  Future<AppStrings> load(Locale locale) => SynchronousFuture<AppStrings>(AppStrings(locale));

  @override
  bool shouldReload(_AppStringsDelegate old) => false;
}
