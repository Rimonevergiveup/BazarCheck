import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config.dart';

/// Global accessor for the initialised Supabase client.
SupabaseClient get supabase => Supabase.instance.client;

/// Initialise Supabase before the app starts (called from `main()`).
///
/// Credentials come from [AppConfig], which reads `--dart-define` values first
/// and falls back to the committed dev defaults.
Future<void> initSupabase() async {
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );
}
