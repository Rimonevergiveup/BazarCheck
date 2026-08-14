# BazarCheck — How to Run

A price-comparison app for Bangladesh. Search a product in **Bangla or English**,
see what every seller charges, and know **when each price was last checked**.

```
Flutter app  ──►  Supabase (PostgreSQL + Auth)   ← all comparison happens here
     │                    ▲
     └──►  Python price service (optional)  ──────┘   trends & statistics
```

---

## 1. Apply the database migration — do this first

The app reads through RPC functions that migration 002 creates. Nothing works
until it has run.

1. Open **Supabase → SQL Editor → New query**
2. Paste the whole of **`database/migrations/002_price_comparison.sql`**
3. Run it

The migration is **additive and idempotent**: it creates nothing destructively,
drops no columns, deletes no rows, and is safe to run twice. It will:

- add `sellers`, `prices`, `price_history`, `favorites`, `profiles`
- add `name_bn`, `brand`, `unit`, `search_text` to `products`
- **move your existing `products.price` values into `prices`**, attached to a
  placeholder seller called *BazarCheck Listing* (`products.price` is left intact)
- close the security hole where any signed-up user could rewrite every price

### Make yourself an admin

Writes are now admin-only. Grant yourself the role from the SQL Editor:

```sql
UPDATE public.profiles SET role = 'admin' WHERE email = 'you@example.com';
```

Until you do this, nobody can add or change prices from the app — which is the
point. Re-assign the backfilled prices from *BazarCheck Listing* to real sellers as
you add them.

---

## 2. Run the Flutter app

```bash
cd bazarcheck_app
flutter pub get
flutter run
```

**No login is required.** Search, browse and compare prices work anonymously.
An account is only needed to save favourites.

To point at a different Supabase project without editing source:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://xxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=sb_publishable_xxx
```

---

## 3. Run the price service (optional)

The app is fully functional without it — all comparison happens in Postgres.
This service adds statistical analysis on top: medians, trend detection from
price history, and stale-price flagging.

```bash
cd ai_service
cp .env.example .env        # fill in SUPABASE_URL and SUPABASE_ANON_KEY
pip install -r requirements.txt
python main.py              # http://localhost:8000  (docs at /docs)
```

Or with Docker:

```bash
docker compose up --build
```

Physical device? It cannot reach your PC's `localhost`:

```bash
flutter run --dart-define=PRICE_SERVICE_URL=http://192.168.1.10:8000
```

---

## 4. Run the tests

> **Windows PowerShell users:** Windows PowerShell 5.1 (the blue default shell)
> does not support `&&` — it errors with *"The token '&&' is not a valid
> statement separator in this version."* Run each line separately, as written
> below, or use the `npm run` shortcuts at the end of this section.

**Flutter — formatters, models, widgets**

```
cd bazarcheck_app
flutter pub get
flutter analyze
flutter test
```

**Price service — analysis logic + HTTP surface**

```
cd ai_service
pip install -r requirements.txt
pytest -v
```

**Database — applies both schemas to a real PostgreSQL, then asserts the
backfill, constraints, RLS and all four RPC functions**

```
pip install "psycopg[binary]" pgserver
python database/tests/test_migration.py
```

### Shortcuts

`npm` runs its scripts through `cmd.exe` on Windows, where `&&` *is* valid — so
these work in any shell, from the repo root:

```
npm run test:app        # flutter analyze + flutter test
npm run test:service    # pytest
npm run test:db         # migration checks
npm test                # all three
```

---

## Adding real price data

```sql
-- 1. A seller
INSERT INTO sellers (name, name_bn, slug, seller_type, city)
VALUES ('Shwapno', 'স্বপ্ন', 'shwapno', 'retail', 'Dhaka');

-- 2. A product, searchable in both scripts
INSERT INTO products (name, name_bn, brand, unit, category_id, description)
VALUES ('Miniket Rice', 'মিনিকেট চাল', 'ACI', 'kg',
        (SELECT id FROM categories WHERE name = 'Rice'), 'Premium miniket');

-- 3. That seller's price. collected_at is what the app shows as freshness —
--    always set it honestly.
INSERT INTO prices (product_id, seller_id, price, unit, source, collected_at)
VALUES (
  (SELECT id FROM products WHERE name = 'Miniket Rice'),
  (SELECT id FROM sellers  WHERE slug = 'shwapno'),
  78.00, 'kg', 'manual', NOW()
);
```

Add the same product at a second seller and the comparison appears
automatically — cheapest badge, savings figure, and the spread on the card.

`price_history` is written by a trigger whenever a price changes. You never
insert into it directly.

---

## Troubleshooting

**Empty lists / "Nothing here yet"** — migration 002 has not been applied. Do step 1.

**Prices show but no comparison** — each product has only one seller. Comparison
needs two or more rows in `prices` for the same `product_id`.

**"Only an admin can change a role"** — expected. Run the promotion SQL from the
Supabase SQL Editor (service_role context), not from the app.

**Cannot insert prices from the app** — also expected. Writes require
`profiles.role = 'admin'`.

**Bangla search finds nothing** — the product needs a `name_bn` value.
`search_text` is generated from `name + name_bn + brand + description`.

**Broken product images** — the original seed rows use `https://example.com/...`
placeholders. Replace `image_url` with real URLs; the app shows a neutral basket
icon rather than a broken-image glyph in the meantime.

**Price shows "Price unavailable"** — no seller has a row in `prices` for that
product. This is deliberate: the app will not print ৳0 when it does not know.
