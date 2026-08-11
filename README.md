# Porokh · পরখ

Compare product prices across sellers in Bangladesh. Search in **Bangla or
English**, see what every shop charges, and know **when each price was last
checked**.

```
USER OPENS POROKH  →  SEARCHES ("চাল" or "rice")  →  SEES EVERY SELLER'S PRICE
                     →  CHEAPEST IS BADGED  →  KNOWS HOW FRESH EACH PRICE IS
```

No account needed to search or compare. Sign in only to save favourites.

---

## Stack

| Layer | Technology |
|---|---|
| App | Flutter (Dart), Riverpod, Material 3, Bangla + English |
| Data | Supabase — PostgreSQL, Auth, Row Level Security |
| Comparison logic | PostgreSQL functions (`search_products`, `get_product_offers`, …) |
| Analysis (optional) | Python FastAPI — medians, trends, stale-price detection |

Price comparison runs **inside Postgres**, not in the client: one round trip per
screen, and the same logic serves the app and the Python service.

---

## Layout

```
porokh/
├── porokh_app/                Flutter app
│   ├── lib/
│   │   ├── core/formatters.dart     ৳ BDT, Bangla digits, freshness
│   │   ├── l10n/app_strings.dart    Bangla + English
│   │   ├── theme/app_theme.dart     brand theme, light + dark
│   │   ├── models/                  ProductSummary, PriceOffer, BestDeal
│   │   ├── repositories/            CatalogRepository (RPC calls)
│   │   ├── providers.dart           Riverpod: search, favourites, settings
│   │   ├── screens/                 home, search, detail, favourites, account
│   │   └── widgets/                 product card, offer tile, price widgets
│   └── test/                        formatter, model and widget tests
│
├── ai_service/                  Python price service (optional)
│   ├── main.py                      statistics over real Supabase data
│   └── test_main.py                 23 tests
│
├── database/
│   ├── migrations/
│   │   └── 002_price_comparison.sql additive, idempotent
│   └── tests/test_migration.py      62 checks against real PostgreSQL
│
├── supabase_schema.sql          original schema (migration 001)
├── HOW_TO_RUN.md                start here
├── POROKH_AUDIT.md            audit of the pre-rebuild codebase
└── docs/archive/                superseded planning docs
```

---

## Quick start

```bash
# 1. Apply database/migrations/002_price_comparison.sql in the Supabase SQL Editor
# 2. Make yourself admin:
#    UPDATE public.profiles SET role='admin' WHERE email='you@example.com';

cd porokh_app && flutter pub get && flutter run
```

Full instructions, including how to add sellers and prices: **[HOW_TO_RUN.md](HOW_TO_RUN.md)**

---

## Data model

```
divisions ─< categories ─< products ─< prices >─ sellers
                                │         │
                                │         └──> price_history  (trigger-written)
                                └──< favorites >── auth.users ── profiles (role)
```

`prices` is the heart of it: one row per **(product, seller)**, carrying `price`,
`currency`, `unit`, `in_stock`, `source` and — critically — `collected_at`, the
timestamp the app surfaces so a price is never presented as current when it isn't.

---

## Principles

1. **Never show a price the app cannot stand behind.** No price means "Price
   unavailable", not ৳0. Every price carries its age.
2. **Comparison lives in the database.** One RPC per screen; no client-side joins.
3. **Reads are public, writes are admin-only.** Enforced by RLS, not by the UI.
4. **Bangla is a first-class language**, not a translation layer bolted on.
5. **Nothing is invented.** The price service reports statistics or says it
   doesn't know.

---

## Tests

```bash
cd porokh_app && flutter test          # formatters, models, widgets
cd ai_service && pytest -v               # 23 tests
python database/tests/test_migration.py  # 62 checks on real PostgreSQL
```

CI runs all three plus `flutter analyze --fatal-warnings` and a Docker build.

## Licence

MIT
