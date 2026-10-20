import 'package:flutter/foundation.dart';

/// Central configuration.
///
/// Every value can be overridden at build time with `--dart-define`, so the
/// same source builds against dev, staging and production without edits:
///
///   flutter build apk \
///     --dart-define=SUPABASE_URL=https://xxx.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=sb_publishable_xxx \
///     --dart-define=PRICE_SERVICE_URL=https://api.bazarcheck.com
class AppConfig {
  AppConfig._();

  // ---------------------------------------------------------------------------
  // Supabase
  // ---------------------------------------------------------------------------
  // The publishable ("anon") key is designed to ship inside a client — it grants
  // only what Row Level Security allows. That is safe HERE because migration
  // 002 restricts all writes to admins; before that migration, any signed-up
  // user could rewrite every price in the database.
  //
  // Prefer --dart-define in CI so the committed default is only a dev fallback.
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://fhctcrasoesugarhxuco.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_l1u45FBnFM5q2p9LxAmovg_QUFMkNms',
  );

  // ---------------------------------------------------------------------------
  // Python price service (ai_service/main.py)
  // ---------------------------------------------------------------------------
  static const String _priceServiceOverride =
      String.fromEnvironment('PRICE_SERVICE_URL');

  /// Base URL for the price-insights service.
  ///
  /// Emulators cannot reach the host through `localhost`, so the default is
  /// resolved per platform. For a physical device, pass your machine's LAN IP:
  ///   flutter run --dart-define=PRICE_SERVICE_URL=http://192.168.1.10:8000
  static String get priceServiceBaseUrl {
    if (_priceServiceOverride.isNotEmpty) return _priceServiceOverride;
    if (kIsWeb) return 'http://localhost:8000';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000'; // Android emulator -> host machine
    }
    return 'http://localhost:8000';
  }

  /// A price older than this is shown with a warning tint.
  static const Duration staleAfter = Duration(days: 7);
}
