# Bazardam — Full Codebase Audit

**Date:** 9 August 2026
**Scope:** Read-only inspection. No source files were modified.
**Verdict up front:** The code that exists is clean and works. But **it is not a price-comparison app.** It is a single-price catalog browser. The core feature you described — comparing prices across sellers — has no code, no tables, and no UI anywhere in this repository.

---

## 0. The headline finding

You described Bazardam as:

> *Users can search for products and see their current prices, compare prices between different sources/sellers, and easily understand where they can get a better price.*

Here is what the repository actually contains, verified by exhaustive grep across all `.dart`, `.py`, and `.sql` files:

| Core capability you described | Found in code? | Evidence |
|---|---|---|
| Product **search** | **No — zero occurrences** | No `SearchBar`, no `TextField` outside the two auth forms, no `.ilike()`, no `textSearch`, no `tsvector`. Navigation is drill-down only. |
| **Sellers / stores / sources** | **No** | No `sellers` table, no `seller_id` column, no seller model, no seller UI. The word does not appear in any source file. |
| **Price comparison** | **No** | Impossible by construction — `products.price` is a single scalar column. One product = one price. There is nothing to compare. |
| **Price freshness** | **No (partially available)** | `products.updated_at` exists in the DB with an auto-update trigger, but the app never selects it, never parses it, never displays it. |
| **Price history** | **No** | No table, no code. |
| Favourites / watchlist / alerts | **No** | Not present. |
| Admin / product management | **No** | No admin UI. Prices can only be changed by hand in the Supabase dashboard. |

This is a **scope gap, not a bug**. Nothing is broken here — the features were simply never built. The project you have is a well-structured *foundation* that was scaffolded from a generic "Flutter + Supabase + Python AI" architecture template (see `Recomend.txt` and `.qoder/plans/`), and price comparison is never mentioned in any of the 18 planning documents at the repo root either.

Everything below audits what *does* exist, and then the roadmap tells you what to build.

---

## 1. Project structure

```
bazaedam/
├── bazaedam_app/                 Flutter app — the entire product
│   ├── lib/                      21 Dart files, 1,444 lines total
│   │   ├── main.dart             App entry, MaterialApp, routes
│   │   ├── supabase_client.dart  Supabase.initialize()
│   │   ├── home_page.dart        Thin 11-line wrapper around HomeScreen
│   │   ├── providers.dart        All Riverpod providers (68 lines)
│   │   ├── config/
│   │   │   └── app_config.dart   ⚠️ Hardcoded Supabase URL + key; AI base URL
│   │   ├── models/
│   │   │   ├── division.dart     id, name, description
│   │   │   ├── category.dart     + divisionId
│   │   │   ├── product.dart      + price, imageUrl, categoryId
│   │   │   └── ai_models.dart    ProductAnalysis, Recommendation
│   │   ├── repositories/
│   │   │   └── supabase_repository.dart   5 read methods, 2 of them dead
│   │   ├── services/
│   │   │   ├── auth_service.dart Supabase email auth wrapper
│   │   │   └── ai_service.dart   HTTP client for the FastAPI service
│   │   ├── screens/
│   │   │   ├── auth/{auth_gate, login_screen, signup_screen}.dart
│   │   │   ├── home_screen.dart          Divisions list
│   │   │   ├── categories_screen.dart    Categories in a division
│   │   │   ├── products_screen.dart      Products in a category
│   │   │   ├── product_detail_screen.dart
│   │   │   └── recommendations_screen.dart
│   │   └── widgets/
│   │       └── status_views.dart Loading / Error / Empty panels
│   ├── pubspec.yaml
│   └── test/widget_test.dart     ⚠️ Placeholder only: expect(true, isTrue)
│
├── ai_service/                   Python FastAPI service
│   ├── main.py                   ~130 lines — 100% hardcoded mock responses
│   ├── requirements.txt          numpy/sklearn/pillow declared but unused
│   ├── Dockerfile                ⚠️ Does not build (see §11)
│   └── .env                      All placeholder values — nothing real leaked
│
├── supabase_schema.sql           4 tables, RLS policies, triggers, sample data
├── docker-compose.yml            ai-service only
├── package.json + index.js       npm used purely as a task runner; index.js is a no-op
├── .github/workflows/ci.yml      flutter analyze + test; python import check
└── 18 × *.md                     ARCHITECTURE.md, ARCHITECTURE_OVERVIEW.md,
                                  ARCHITECTURE_REFERENCE.md, SUMMARY.md,
                                  QUICK_SUMMARY.md, STATUS.md, STATUS_SUMMARY.md,
                                  STATUS_UPDATE.md, ONE_PAGE_SUMMARY.md …
                                  Heavily overlapping. Maintenance liability.
```

**Note:** the folder is `bazaedam` (with an extra *e*) everywhere in code, while you call the product "Bazardam". Worth settling on one spelling before you ship.

**Not a git repository.** There is no `.git` directory, so there is no version history and no safety net. This should be fixed before any code changes.

---

## 2. Technology stack (determined from code, not assumed)

### Frontend
| Concern | Actual |
|---|---|
| Framework | Flutter, Dart SDK `^3.10.7` |
| State management | Riverpod 2.4.12 (`FutureProvider`, `FutureProvider.family`, `StreamProvider`) |
| Navigation | Imperative `Navigator.push(MaterialPageRoute)` + two named routes. No GoRouter. |
| UI system | Material 3, `ColorScheme.fromSeed(Colors.blue)` — stock default, zero branding |
| API client | `supabase_flutter` SDK for data; `http` 1.2.2 for the AI service |
| Images | `Image.network` — **no caching package** |
| Localization | **None.** No `flutter_localizations`, no Bangla support |
| Dead dependencies | `path_provider` and `image_picker` are declared but referenced in **0** files |

### Backend
There are effectively **two** backends, and the interesting one is missing:

1. **Supabase** — the real backend. The Flutter client talks to PostgreSQL **directly** via the Supabase SDK. There is no API layer, no server-side business logic, no validation layer. All authorisation rests entirely on RLS policies.
2. **`ai_service/` (FastAPI)** — a stub. Three endpoints, all returning hardcoded Python dicts. Verified: `main.py` contains **no** import of supabase, psycopg, sqlalchemy, redis, dotenv, or `os.getenv`. It has no database connection and no environment access at all. `numpy`, `scikit-learn`, and `pillow` are installed but never imported.

### Database
Supabase PostgreSQL. Four tables: `divisions`, `categories`, `products`, `ai_results`. UUID primary keys via `gen_random_uuid()`. RLS enabled on all four.

### Infrastructure
`docker-compose.yml` for the AI service only. GitHub Actions CI runs `flutter analyze`, `flutter test`, and a Python import check. **No hosting configured** for the AI service — the app hardcodes `localhost:8000` / `10.0.2.2:8000`, which means AI features cannot work for any real user on a real device.

---

## 3. Actual architecture

```
                        ┌──────────────┐
                        │     User     │
                        └──────┬───────┘
                               ↓
                    ┌──────────────────────┐
                    │   Flutter app        │
                    │   (Riverpod)         │
                    └───┬──────────────┬───┘
                        │              │
      supabase_flutter  │              │  http (localhost:8000)
      (direct DB access)│              │
                        ↓              ↓
        ┌───────────────────────┐   ┌──────────────────────┐
        │  Supabase PostgreSQL  │   │  FastAPI ai_service  │
        │  + Auth + RLS         │   │                      │
        │                       │   │  returns hardcoded   │
        │  divisions            │   │  dicts. No DB.       │
        │  categories           │   │  No auth. No CORS.   │
        │  products             │   └──────────────────────┘
        │  ai_results (unused)  │            ✗
        └───────────────────────┘   no connection between them
```

Key architectural facts:

- **There is no API layer.** The mobile client queries the database directly. Any change to business rules requires an app release, and all security is RLS.
- **The AI service is an island.** It never reads or writes Supabase. The `ai_results` table is defined, indexed, and RLS-protected — and **never written to by anything**.
- **Error handling** is per-provider: each screen's `AsyncValue.when` renders `ErrorView` with a Retry button. Reasonable pattern, but raw exception text is shown to end users (`'Could not load divisions.\n$e'`), which leaks internal detail.
- **No offline support, no caching layer, no retry/backoff.**

---

## 4. Product data flow (what actually happens)

There is no search, so the only path is a three-tap drill-down:

```
App launch
   ↓  main() → initSupabase() → AuthGate
   ↓  🔒 login required before ANY browsing
HomeScreen        → divisionsProvider        → supabase.from('divisions').select().order('name')
   ↓ tap
CategoriesScreen  → categoriesByDivision(id) → .from('categories').eq('division_id',id).order('name')
   ↓ tap
ProductsScreen    → productsByCategory(id)   → .from('products').eq('category_id',id).order('name')
   ↓ tap
ProductDetailScreen
   ├─ shows product.price               (already in memory, from the list query)
   └─ POST /api/v1/analyze-product      → hardcoded mock response
```

Field by field:

| Field | Origin | Notes |
|---|---|---|
| Product name | `products.name` | No uniqueness constraint |
| Image | `products.image_url` (raw string) | `Image.network`, no caching. Sample data uses `https://example.com/...` → every image is broken on a fresh install |
| **Price** | `products.price` — `NUMERIC(10,2)`, **nullable** | Single scalar. Null coerces to `0.0` in `Product.fromJson` |
| Seller | **does not exist** | — |
| Currency | **does not exist in DB** | UI hardcodes `$` — wrong for a ৳ BDT market |
| Availability | **does not exist** | — |
| Freshness | `updated_at` exists in DB | Never selected, never shown |
| Sort order | `.order('name')` | Alphabetical only. No price sort. |

---

## 5. Feature inventory

| Feature | Status | Frontend | Backend | Database | Notes |
|---|---|---|---|---|---|
| Division browsing | ✅ Working | ✅ | ➖ direct DB | ✅ | Clean drill-down with refresh |
| Category browsing | ✅ Working | ✅ | ➖ | ✅ | |
| Product listing | ✅ Working | ✅ | ➖ | ✅ | No pagination |
| Product details | ✅ Working | ✅ | ➖ | ✅ | |
| **Product search** | ➖ **Not implemented** | ➖ | ➖ | ➖ | **Core feature, zero code** |
| Product price (single) | ⚠️ Partial | ⚠️ | ➖ | ⚠️ | Renders `$0.00` when price is NULL |
| **Price comparison** | ➖ **Not implemented** | ➖ | ➖ | ➖ | **Core feature, no schema for it** |
| **Seller / store info** | ➖ **Not implemented** | ➖ | ➖ | ➖ | **Core feature** |
| Price freshness display | ➖ Not implemented | ➖ | ➖ | 🚧 column exists | Data is there, unused |
| Price history | ➖ Not implemented | ➖ | ➖ | ➖ | |
| Filtering / sorting | ➖ Not implemented | ➖ | ➖ | ➖ | Alphabetical only |
| Product images | ⚠️ Partial | ⚠️ | ➖ | ✅ | No caching; sample URLs are fake |
| Authentication | ⚠️ Partial | ⚠️ | ✅ Supabase | ✅ | Works, but see the nav bug in §9 |
| AI analysis | 🧪 Fake | ✅ | 🧪 mock | ➖ | Same fabricated answer for every product |
| AI recommendations | 🧪 Fake | ✅ | 🧪 mock | ➖ | Returns two hardcoded Apple products |
| Feedback (thumbs) | ❌ Broken | ✅ | ❌ discards | ➖ | Server returns 200 and throws the data away |
| Favourites / alerts | ➖ Not implemented | ➖ | ➖ | ➖ | |
| Admin panel | ➖ Not implemented | ➖ | ➖ | ➖ | Prices are hand-edited in Supabase |
| Tests | ❌ Placeholder | ❌ | ➖ | ➖ | `expect(true, isTrue)` |

Legend: ✅ working · ⚠️ partial · ❌ broken · 🚧 incomplete · 🧪 fake/experimental · ➖ not implemented

---

## 6. Price system audit

This is the most important section, and the news is not good.

### Where prices come from
Manual rows in `products.price`, typed by hand into the Supabase dashboard. There is **no** admin UI, **no** scraper, **no** import job, **no** external price API, and **no** scheduled update of any kind. Every price is entered once and then decays silently.

### Can prices be compared?
**No — not as a bug, but as a schema impossibility.**

```
What Bazardam needs                    What the schema has
────────────────────                   ───────────────────
Product                                 Product
 ├── Seller A → ৳ 120                    └── price → 120.00
 ├── Seller B → ৳ 135
 ├── Seller C → ৳ 118  ← cheapest
```

`products` has one `price` column. There is no `prices` table, no `sellers` table, no join. Price comparison cannot be added without a schema change.

### Price freshness
`products.updated_at` exists and is maintained by the `set_timestamp_products` trigger. But:

- `SupabaseRepository.getProductsByCategory()` calls bare `.select()` (all columns), so `updated_at` *is* fetched over the wire —
- …but `Product.fromJson` doesn't parse it, `Product` has no field for it, and no screen displays it.

**Result: the app shows every price as if it were current, with no way for a user or for you to know it is three months stale.** For a price-comparison product this is the single most damaging trust issue.

### The `$0.00` problem
```dart
price: (json['price'] as num?)?.toDouble() ?? 0.0,   // product.dart:24
```
`products.price` is nullable. A product with no price renders as **`$0.00`** — a confident, specific, wrong number. "Price unknown" and "free" are being displayed identically. This is worse than showing nothing.

### Currency
The schema has no currency column. The UI hardcodes a dollar sign in two places:
- `products_screen.dart:84` — `'\$${p.price.toStringAsFixed(2)}'`
- `product_detail_screen.dart:78` — same

For a Bangladeshi market app this is straightforwardly wrong.

---

## 7. Search audit

**There is nothing to audit — search does not exist.** Verified by grep across every Dart, Python, and SQL file: no search widget, no query parameter, no `ilike`, no `textSearch`, no full-text index, no `pg_trgm` extension.

Consequences for the core user journey:

| Question | Answer |
|---|---|
| Search speed | n/a |
| Exact / partial / case-insensitive matching | n/a |
| Typo tolerance | n/a |
| Bangla ("চাল") search | n/a — and no Bangla support anywhere in the app |
| Category / brand / price filters | None. No `brand` column exists. |
| Sorting | Alphabetical by name only, server-side |
| Pagination | None. `.select()` returns every row in a category. |
| No-result UX | `EmptyView` exists and is used for empty categories — reusable when search is built |

Today, to find rice a user must correctly guess which division and which category it was filed under, then scan an alphabetical list. That is the opposite of the journey you described.

Also missing from the DB for search: no index on `products.name`, so any `ILIKE` you add will trigger a sequential scan.

---

## 8. Database audit

### Actual schema

```sql
divisions   (id UUID PK, name TEXT NOT NULL, description, created_at, updated_at)
categories  (id UUID PK, name TEXT NOT NULL, division_id → divisions ON DELETE CASCADE,
             description, created_at, updated_at)
products    (id UUID PK, name TEXT NOT NULL, category_id → categories ON DELETE CASCADE,
             description, price NUMERIC(10,2) NULL, image_url TEXT, created_at, updated_at)
ai_results  (id UUID PK, user_id → auth.users, product_id → products,
             ai_analysis JSONB NOT NULL, confidence_score NUMERIC(3,2) CHECK 0..1,
             created_at, updated_at)
```

**Indexes:** `categories(division_id)`, `products(category_id)`, `ai_results(user_id)`, `ai_results(product_id)`. All four are FK indexes — sensible, and correctly chosen for the drill-down queries the app actually runs.

**Triggers:** `trigger_set_timestamp()` on all four tables. Correct.

### Problems found

| # | Issue | Severity |
|---|---|---|
| D1 | **No `sellers` table and no `prices` table.** The core domain is absent. | Critical |
| D2 | **RLS write hole:** on `divisions`, `categories`, and `products`, the INSERT/UPDATE policies are `auth.role() = 'authenticated'`. **Any user who signs up can insert products and rewrite any price.** No admin role, no ownership check. | Critical |
| D3 | `products.price` is nullable with no `CHECK (price >= 0)`. Negative and null prices are both accepted. | High |
| D4 | No currency column. | High |
| D5 | No `UNIQUE` constraints anywhere. Duplicate divisions, categories, and products are all permitted. | High |
| D6 | **The schema file is not re-runnable.** `CREATE TABLE IF NOT EXISTS` is guarded, but `CREATE POLICY` and `CREATE TRIGGER` are not (re-running errors), and the sample `INSERT`s are unguarded (re-running silently duplicates all sample data). | Medium |
| D7 | No index on `products.name` — future search will seq-scan. | Medium |
| D8 | No `DELETE` policy on any table. Deletes fail silently under RLS. | Medium |
| D9 | `ai_results` has an `updated_at` trigger but **no UPDATE policy**, so the trigger can never fire. | Low |
| D10 | Sample `image_url` values are `https://example.com/...` — guaranteed broken images on any fresh install. | Low |
| D11 | `NUMERIC(10,2)` caps prices at 99,999,999.99. Fine for retail, worth noting. | Info |

---

## 9. UI/UX audit

### Against the journey you care about

```
Open app  →  Find product  →  Understand price  →  Compare  →  Decide
   🔒            ❌               ⚠️                 ❌          ❌
 login wall   no search      no freshness      impossible   impossible
```

### Home screen
Opens (after a mandatory login) to a plain list of **divisions**: "Electronics", "Clothing", "Home & Kitchen". A price-comparison app's home screen shows **no prices and no search box**. A first-time user cannot tell what this app is for.

### Product card (`products_screen.dart`)
Shows name, description (2 lines), 56×56 image, price. Missing: seller, freshness, unit (per kg / per litre), any comparison signal ("3 sellers, from ৳118"). The price is rendered in the `ListTile.trailing` slot — visually the least prominent position on the row, for the most important number in the app.

### Product detail
Image → name → price → description → **a large "AI Analysis" card**. That card renders, for *every single product including a T-shirt*:

> Category: **Electronics** · Sentiment: **positive** · Confidence: **95%**
> Key features: *high performance · long battery life · excellent camera*

These strings are hardcoded in `ai_service/main.py:44-50`. Presenting fabricated data at 95% confidence next to a real price will destroy user trust the first time someone notices. The thumbs up/down buttons below it post to an endpoint that returns `{"status": "recorded"}` and discards the payload.

### 🔴 Navigation bug — users can get permanently stuck at login

Verified by tracing the widget tree:

1. `MaterialApp(home: AuthGate())` — `AuthGate` owns the `/` route and watches `authStateProvider`.
2. Logged out, `AuthGate` renders `LoginScreen` *as a widget inside `/`*.
3. Tapping "Don't have an account? Sign Up" calls `Navigator.pushReplacementNamed(context, '/signup')` — this **replaces the `/` route, unmounting `AuthGate`**.
4. `SignupScreen` succeeds → `pushReplacementNamed('/login')` → `LoginScreen` now exists as a standalone route.
5. The user signs in. `signInWithEmail` succeeds and `authStateProvider` emits the user — **but `AuthGate` is no longer in the tree, and `LoginScreen._login()` does not navigate on success.**
6. **The user is authenticated but stuck staring at the login form.** Only a full app restart recovers.

This hits every new user who signs up through the in-app link — i.e. all of them.

### Other UI issues
- **Auth wall before browsing.** For a price-comparison app this is a serious funnel problem — users should be able to search prices anonymously and only sign in for favourites/alerts.
- Stock Material 3 blue seed theme, no logo, no brand identity, no dark theme configuration.
- No localisation. No Bangla. No `flutter_localizations` dependency.
- Raw exception strings shown to users.
- No `Semantics` labels, no accessibility work.
- 56×56 image thumbnails with no placeholder or fade-in — lists will visibly pop as images load.

---

## 10. Performance audit

### Frontend
| Issue | Detail |
|---|---|
| **No image caching** | `Image.network` re-downloads on every rebuild and every scroll recycle. `cached_network_image` is not a dependency. |
| **No pagination** | `.select()` fetches *every* product in a category. A 500-item category is one huge payload. |
| **Over-fetching columns** | Bare `.select()` pulls `description`, `created_at`, `updated_at` for list views that need four fields. |
| Full invalidation on refresh | Pull-to-refresh calls `ref.invalidate()`, discarding the whole cache. |
| AI call per detail open | Every product detail fires an HTTP POST with a 15s timeout, and the response is byte-identical every time. No caching. |
| Riverpod usage | `FutureProvider.family` caching is correct. No unnecessary rebuild problems found. |

### Backend
The FastAPI service returns constants, so it has no performance characteristics worth measuring. Note it uses `async def` handlers with purely synchronous bodies — fine now, a footgun once real I/O is added.

### Database
Queries are simple single-table filters on indexed FK columns. Performance is fine **for the queries that exist**. The moment you add search or a price join, you will need `pg_trgm` on `products.name` and an index on `prices(product_id)`.

---

## 11. Security audit

### ⚠️ Credentials

```
⚠️ Live Supabase project URL + publishable key hardcoded in:
   bazaedam_app/lib/config/app_config.dart
```

The `sb_publishable_…` key type **is** designed to ship in clients — it is not a secret by itself. But it is only safe when RLS is correct, **and here RLS is not correct**. Combined with finding D2 below, shipping this build means anyone who downloads your APK can sign up and rewrite every price in your database.

```
✅ ai_service/.env — inspected. All values are placeholders
   (your-project-url…, user:password@localhost…). Nothing real is exposed.
   Keep it that way: it is correctly listed in .gitignore.
```

### Findings

| # | Issue | Severity |
|---|---|---|
| S1 | **Any authenticated user can INSERT/UPDATE `products`, `categories`, `divisions`** via RLS policy `auth.role() = 'authenticated'`. Price data is fully writable by any signed-up user. | **Critical** |
| S2 | **FastAPI has no authentication on any endpoint.** No JWT validation, no API key, no rate limiting. | High |
| S3 | `GET /api/v1/recommendations/{user_id}` accepts an arbitrary user ID in the path with no ownership check. Classic IDOR — harmless today only because the data is fake. | High |
| S4 | **No CORS configuration** on FastAPI. Flutter Web will be blocked in the browser; a permissive fix would then expose the API to any origin. | Medium |
| S5 | Raw exception text rendered to end users (`'Could not load divisions.\n$e'`) leaks internal detail. | Medium |
| S6 | `API_DEBUG=True` in `.env.example` — encourages shipping debug mode. | Low |
| S7 | Password validation is `length >= 6` only. No strength requirement. | Low |
| S8 | **`ai_service/.gitignore` contains `Dockerfile`** — the Dockerfile would be excluded from any commit. | Low |
| S9 | No `DELETE` RLS policies → deletes fail silently rather than being explicitly denied. | Low |

### 🔴 The Docker image does not build

`ai_service/Dockerfile` line 10:
```dockerfile
RUN addgroup -g 1001 appgroup && adduser -u 1001 -G appgroup -D appuser
```
These are **BusyBox/Alpine** flags, but the base image is `python:3.11-slim`, which is **Debian**. I ran both commands on Debian to confirm:

```
addgroup -g 2001 tg2                 → exit 1   ("Option g is ambiguous")
adduser -u 2001 -G tg2 -D tu2        → exit 1   ("Option d is ambiguous")
```

The `RUN` layer fails, so `docker build` fails, so `docker-compose up` fails. The Debian form is `addgroup --gid 1001 appgroup && adduser --uid 1001 --ingroup appgroup --disabled-password --gecos "" appuser`. The `USER appuser` intent is good — it just never executes.

### Other correctness issues
- `bazaedam_app/test/widget_test.dart` is `expect(true, isTrue)`. CI runs `flutter test` and always passes. **You have green CI with zero real coverage.**
- `SupabaseRepository.getCategories()` and `getProducts()` are dead code — verified zero call sites.
- `path_provider` and `image_picker` are unused dependencies.
- `index.js` is a no-op that prints hardcoded `e:/bazaedam/` paths.
- 18 overlapping markdown files at the repo root will drift out of sync with reality.

---

## 12. Product quality — can a real user succeed?

| The user asks… | Today's answer |
|---|---|
| "How much does this cost?" | ⚠️ Only if they can find the product by guessing its division and category — and the number may be months old, may be `$0.00`, and is labelled in the wrong currency. |
| "Where is it cheaper?" | ❌ **Impossible.** One price per product, no sellers. |
| "When was this price updated?" | ❌ The data exists in the DB and is never shown. |
| "Can I search?" | ❌ No search exists. |
| "Can I filter or sort by price?" | ❌ Alphabetical only. |
| "Can I trust this price?" | ❌ No source, no timestamp, no seller attribution — and a fabricated 95%-confidence "AI Analysis" panel sitting right next to it. |

**Bazardam cannot currently deliver its core promise.** The foundation underneath — auth, Riverpod wiring, repository pattern, loading/error/empty states, CI — is solid, clean, and worth keeping. The domain model on top of it is for a different app.

---

## 13. Prioritised roadmap

### P0 — Critical (do first; security and correctness)

| Problem | Impact | Recommended solution | Files affected | Difficulty |
|---|---|---|---|---|
| Any authenticated user can rewrite any price (S1/D2) | Anyone with the APK can corrupt your entire price database | Split read from write: keep public SELECT, restrict INSERT/UPDATE/DELETE to an admin role via a `profiles.role` claim or `service_role` only | `supabase_schema.sql` | Medium |
| Users stuck at login after signing up (§9) | Every new user hits this | Keep `AuthGate` mounted — use `Navigator.push` (not `pushReplacementNamed`) for the auth screens, or move auth into a router that reacts to `authStateProvider` | `main.dart`, `login_screen.dart`, `signup_screen.dart`, `auth_gate.dart` | Low |
| `$0.00` shown for NULL prices (§6) | Displays a confident wrong number | Make `Product.price` nullable (`double?`) and render "Price unavailable" | `models/product.dart`, `products_screen.dart`, `product_detail_screen.dart` | Low |
| Fabricated AI analysis shown as fact (§9) | Destroys trust in real prices | Remove the AI Analysis card from product detail until the service is real, or label it clearly as a demo | `product_detail_screen.dart` | Low |
| Docker image does not build (S/§11) | AI service cannot be deployed at all | Replace BusyBox flags with the Debian `adduser` form | `ai_service/Dockerfile` | Low |
| Not under version control | No history, no rollback, no safety net for any of the below | `git init`, verify `.env` is ignored, commit the current state as a baseline | repo root | Low |
| `ai_service/.gitignore` excludes `Dockerfile` (S8) | Deployment file silently missing from commits | Remove that line | `ai_service/.gitignore` | Low |

### P1 — High (this is where Bazardam becomes Bazardam)

| Problem | Impact | Recommended solution | Files affected | Difficulty |
|---|---|---|---|---|
| **No seller/price model** | The product's core promise is unbuildable | Add `sellers` table and a `prices` table (`product_id`, `seller_id`, `price`, `currency`, `url`, `in_stock`, `collected_at`) with `UNIQUE(product_id, seller_id)`. Migrate `products.price` into it. | `supabase_schema.sql`, new migration | High |
| **No search** | Users cannot find anything | Add `SearchBar` on the home screen → repository `searchProducts(q)` using `.ilike('name', '%q%')`, backed by a `pg_trgm` GIN index on `products.name`. Add Bangla later via a `name_bn` column. | new `search_screen.dart`, `supabase_repository.dart`, `providers.dart`, schema | Medium |
| **No price comparison UI** | Even with data, nothing shows it | Product detail: seller rows sorted by price, cheapest badged. Product card: "from ৳118 · 3 sellers". | `product_detail_screen.dart`, `products_screen.dart` | Medium |
| **Price freshness invisible** | Users can't tell stale from current | Parse `updated_at`/`collected_at` into the model, show "Updated 2 days ago", grey out anything over N days | `models/`, both price-rendering screens | Low |
| Wrong currency (`$` hardcoded) | Wrong market | Add a `currency` column; add a single `formatPrice()` helper defaulting to `৳` | new `utils/format.dart`, schema | Low |
| Login wall before browsing | Kills top-of-funnel | Let anonymous users browse and search; gate only favourites/alerts | `auth_gate.dart`, `main.dart` | Medium |
| Home screen shows no search and no prices | Purpose unclear on first open | Redesign home: search bar on top, "cheapest today" / popular products below | `home_screen.dart` | Medium |

### P2 — Medium (performance, architecture, maintainability)

| Problem | Impact | Recommended solution | Files affected | Difficulty |
|---|---|---|---|---|
| No image caching | Wasted bandwidth, janky lists | Add `cached_network_image` | `pubspec.yaml`, both image sites | Low |
| No pagination | Large categories fetch everything | `.range()` + infinite scroll | `supabase_repository.dart`, `products_screen.dart` | Medium |
| Over-fetching columns | Larger payloads than needed | Explicit `.select('id,name,image_url,...')` | `supabase_repository.dart` | Low |
| Placeholder tests + green CI | False confidence | Real widget tests for search/product card/price formatting; `pytest` for the API | `test/`, `ai_service/tests/` | Medium |
| AI service is a mock | Fake data presented as real | Either make it real (read Supabase, compute genuine recommendations) or delete it and its UI | `ai_service/main.py`, `recommendations_screen.dart` | High |
| AI service unreachable in production | AI features can never work for real users | Deploy it and set `AI_BASE_URL` at build time | `docker-compose.yml`, `app_config.dart` | Medium |
| No FastAPI auth/CORS/rate limiting (S2–S4) | Open API | Validate the Supabase JWT; configure explicit CORS origins | `ai_service/main.py` | Medium |
| Schema not re-runnable (D6) | Re-running duplicates sample data | `DROP POLICY IF EXISTS`, `CREATE OR REPLACE TRIGGER`, guard the seed inserts | `supabase_schema.sql` | Low |
| Missing constraints (D3/D5) | Bad data can enter | `CHECK (price >= 0)`, `UNIQUE` on natural keys | `supabase_schema.sql` | Low |
| No index on `products.name` (D7) | Search will seq-scan | `CREATE EXTENSION pg_trgm; CREATE INDEX … USING GIN (name gin_trgm_ops)` | `supabase_schema.sql` | Low |
| Raw errors shown to users (S5) | Leaks internals, poor UX | Map exceptions to friendly messages | `widgets/status_views.dart`, screens | Low |
| Feedback endpoint discards data (§5) | Silent no-op | Persist to a `feedback` table, or remove the buttons | `ai_service/main.py`, `product_detail_screen.dart` | Low |

### P3 — Low (polish and hygiene)

| Problem | Impact | Recommended solution | Files affected | Difficulty |
|---|---|---|---|---|
| No Bangla / localisation | Excludes most of your market | `flutter_localizations` + ARB files; `name_bn` on products | `pubspec.yaml`, `main.dart`, `l10n/` | Medium |
| Dead deps and dead code | Bloat, confusion | Remove `path_provider`, `image_picker`, `getCategories()`, `getProducts()`, `index.js` | `pubspec.yaml`, `supabase_repository.dart` | Low |
| 18 overlapping markdown files | Docs will drift and mislead | Consolidate into `README.md` + `ARCHITECTURE.md` + `HOW_TO_RUN.md` | repo root | Low |
| Stock Material blue theme | No brand identity | Define a proper `ColorScheme`, typography, and dark theme | `main.dart`, new `theme/` | Medium |
| Naming inconsistency (`bazaedam` vs Bazardam) | Confusing | Pick one and normalise | many | Medium |
| No favourites / price alerts | Missing retention hook | Add once the price model lands | new screens + schema | Medium |
| No accessibility work | Excludes users | Add `Semantics` labels, verify contrast and tap targets | all screens | Medium |

---

## Suggested sequencing

The P1 schema change (sellers + prices) is the pivot the whole product turns on, and most other P1 work depends on it. A sensible order:

1. **Safety net** — `git init`, commit the baseline. *(30 min)*
2. **P0 security + the login trap** — RLS write policies, `AuthGate` navigation, `$0.00`, remove the fake AI panel, fix the Dockerfile. *(half a day)*
3. **The price model** — `sellers` + `prices` tables, migrate the existing `price` column, add currency and `collected_at`. *(1–2 days)*
4. **Search** — `pg_trgm` index, `searchProducts()`, search UI, no-results state. *(1–2 days)*
5. **Comparison UI + freshness** — seller list sorted by price, cheapest badge, "updated X ago". *(1–2 days)*
6. **Home redesign + anonymous browsing.** *(1–2 days)*
7. P2 performance and hardening, then P3 polish.

---

**Bazardam analysis is complete. I understand the existing application and am ready to implement the improvements.**

Waiting for your approval before changing any code.
