# Bazaedam — How to Run

A Flutter marketplace app: **Divisions → Categories → Products**, loaded dynamically
from Supabase (nothing hardcoded), with email auth and AI product analysis +
recommendations served by the Python FastAPI service.

Your Supabase credentials are already wired into the app
(`bazaedam_app/lib/config/app_config.dart`), so once the database schema is applied
the app runs with no further config.

---

## 1. Apply the database schema (required — do this first)

The app reads from tables that must exist in your Supabase project.

1. Open your project → **SQL Editor**: https://supabase.com/dashboard/project/wgzzqssnkucrfzdxtqra/sql
2. Paste the entire contents of **`supabase_schema.sql`** and click **Run**.

This creates `divisions`, `categories`, `products`, `ai_results`, enables Row Level
Security (public read), and inserts sample data (Electronics, Clothing, Home & Kitchen…).

## 2. Allow quick sign-in (recommended for testing)

By default Supabase requires email confirmation before a new account can log in.
For fast local testing: **Authentication → Providers → Email → turn OFF "Confirm email"**,
then Save. (Leave it ON for production and confirm via the email link instead.)

## 3. Run the Flutter app

```bash
cd bazaedam_app
flutter pub get
flutter run          # pick a device / emulator / Chrome
```

Sign up, then sign in. You'll land on the **Divisions** list → tap to drill into
**Categories** → tap into **Products** → tap a product for details.

## 4. Start the Python AI service (for AI Analysis + Recommendations)

The product detail screen and the ✨ recommendations button call this service.
The app auto-targets it correctly on the Android emulator (`10.0.2.2:8000`) and on
iOS/desktop/web (`localhost:8000`).

```bash
cd ai_service
pip install -r requirements.txt
python main.py        # serves http://localhost:8000
```

If the service is off, the app still works — the AI sections just show an
"AI service is offline" message with a Retry button.

**Physical phone?** It can't reach your PC's localhost. Run the app pointing at your
computer's LAN IP:

```bash
flutter run --dart-define=AI_BASE_URL=http://192.168.1.10:8000   # your PC's IP
```

---

## What was fixed to make it work

- The whole Flutter `lib/` UI/data layer existed as a skeleton, but **Supabase
  credentials were placeholders** (`your-project-url…`) — the app could never connect.
  Real URL + publishable key are now baked in via `AppConfig`.
- **AI was never wired to the app.** Added a typed `AiService`, `ProductAnalysis` /
  `Recommendation` models, Riverpod providers, a product **AI Analysis** section with
  thumbs-up/down feedback, and a **Recommendations** screen.
- Replaced the flat "dump everything" home screen with a proper
  **Division → Category → Product** drill-down, with loading / empty / error states
  and pull-to-refresh.

## Troubleshooting

- **Blank lists / "No divisions yet":** the schema hasn't been applied — do step 1, then pull to refresh.
- **Login fails right after sign-up:** email confirmation is on — do step 2, or click the link in the confirmation email.
- **Auth key / "Invalid API key" error on startup:** your resolved `supabase_flutter`
  may predate the new `sb_publishable_…` key format. Run `flutter pub upgrade supabase_flutter`,
  or use the legacy `anon` JWT from **Settings → API** instead of the publishable key.
- **Product images show a broken-image icon:** expected — the sample rows use
  `https://example.com/...` placeholder URLs. Replace `image_url` values with real ones.
