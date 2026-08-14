-- ============================================================================
-- BAZARCHECK — COMPLETE DATABASE SETUP  (single file, run once)
-- ============================================================================
-- Paste this ENTIRE file into:
--   Supabase Dashboard -> SQL Editor -> New query -> Run
--
-- No CLI, no login, no database password needed.
-- Safe to run more than once - everything is idempotent.
--
--   ⚠️  The government rates in PART 6 are SAMPLE DATA, not official figures.
--       Replace them with real TCB / DNCRP rates before showing this to users.
--       The app displays a permanent notice saying so.
--
-- AFTER RUNNING: sign up in the app, then make yourself admin:
--   UPDATE public.profiles SET role='admin' WHERE email='YOUR@EMAIL.COM';
-- ============================================================================



-- ==========================================================================
-- PART 1 of 6 — BASE CATALOGUE
-- ==========================================================================

-- ============================================================================
-- BazarCheck — Migration 001: base catalogue
-- ============================================================================
-- divisions ▸ categories ▸ products, plus ai_results.
--
-- This is the original schema, with two changes:
--   * the sample INSERTs moved to supabase/seed.sql (so migrations stay pure
--     schema and can be re-run safely)
--   * policies and triggers are dropped-then-created rather than bare CREATE,
--     so the file is idempotent
--
-- Migration 002 layers the price-comparison model on top of this.
-- ============================================================================

-- gen_random_uuid() is core from PostgreSQL 13 onward, so pgcrypto is only a
-- fallback for older instances. Never fail the migration over it.
DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pgcrypto;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pgcrypto unavailable - using core gen_random_uuid() (PG13+)';
END $$;

-- ----------------------------------------------------------------------------
-- divisions
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.divisions (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  description TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.divisions ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- categories
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.categories (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  division_id UUID REFERENCES public.divisions(id) ON DELETE CASCADE,
  description TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- products
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.products (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  category_id UUID REFERENCES public.categories(id) ON DELETE CASCADE,
  description TEXT,
  price       NUMERIC(10,2),   -- superseded by the prices table in 002
  image_url   TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- ai_results
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ai_results (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID REFERENCES auth.users(id)     ON DELETE CASCADE,
  product_id       UUID REFERENCES public.products(id) ON DELETE CASCADE,
  ai_analysis      JSONB NOT NULL,
  confidence_score NUMERIC(3,2) CHECK (confidence_score BETWEEN 0 AND 1),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.ai_results ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- Interim policies
-- ----------------------------------------------------------------------------
-- Public read only. Migration 002 adds the admin-write policies; until it runs,
-- nothing outside the dashboard can write. That ordering is deliberate — the
-- original schema granted write access to every authenticated user, which meant
-- anyone who signed up could rewrite any price.
DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['divisions', 'categories', 'products'] LOOP
    EXECUTE format('DROP POLICY IF EXISTS "%s_public_read" ON public.%I', t, t);
    EXECUTE format(
      'CREATE POLICY "%s_public_read" ON public.%I FOR SELECT USING (true)', t, t);
  END LOOP;
END $$;

DROP POLICY IF EXISTS "ai_results_owner_read"   ON public.ai_results;
DROP POLICY IF EXISTS "ai_results_owner_insert" ON public.ai_results;
CREATE POLICY "ai_results_owner_read" ON public.ai_results
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "ai_results_owner_insert" ON public.ai_results
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

-- ----------------------------------------------------------------------------
-- Indexes
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_categories_division_id ON public.categories(division_id);
CREATE INDEX IF NOT EXISTS idx_products_category_id   ON public.products(category_id);
CREATE INDEX IF NOT EXISTS idx_ai_results_user_id     ON public.ai_results(user_id);
CREATE INDEX IF NOT EXISTS idx_ai_results_product_id  ON public.ai_results(product_id);

-- ----------------------------------------------------------------------------
-- updated_at maintenance
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trigger_set_timestamp()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['divisions', 'categories', 'products', 'ai_results'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS set_timestamp_%s ON public.%I', t, t);
    EXECUTE format(
      'CREATE TRIGGER set_timestamp_%s BEFORE UPDATE ON public.%I '
      'FOR EACH ROW EXECUTE FUNCTION public.trigger_set_timestamp()', t, t);
  END LOOP;
END $$;


-- ==========================================================================
-- PART 2 of 6 — PRICE COMPARISON
-- ==========================================================================

-- ============================================================================
-- BazarCheck — Migration 002: Price Comparison Core
-- ============================================================================
-- ADDITIVE AND IDEMPOTENT. Safe on a fresh project and on one with real
-- data. Nothing is dropped, nothing is deleted. Safe to run more than once.
--
-- What this adds:
--   1. profiles      — user roles, so only admins can write price data
--   2. sellers       — the shops/sources you compare between
--   3. prices        — one row per (product, seller). THE core comparison table.
--   4. price_history — append-only log, written automatically by trigger
--   5. favorites     — user watchlist
--   6. products.*    — name_bn, brand, unit, search_text (bilingual search)
--   7. Backfill      — moves your existing products.price into prices
--   8. RLS fix       — closes the hole where any signed-up user could rewrite prices
--   9. RPC functions — search, offers, best deals (one round trip each)
--
-- Run this in: Supabase Dashboard -> SQL Editor -> New query -> Run
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 0. Extensions
-- ----------------------------------------------------------------------------
-- Required: powers bilingual partial/fuzzy search. Available on Supabase.
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Optional: gen_random_uuid() is core from PostgreSQL 13 onward, so this is
-- only a fallback for older instances. Never fail the migration over it.
DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pgcrypto;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pgcrypto unavailable - using core gen_random_uuid() (PG13+)';
END $$;


-- ----------------------------------------------------------------------------
-- 1. profiles — user roles
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.profiles (
  id         UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email      TEXT,
  full_name  TEXT,
  role       TEXT NOT NULL DEFAULT 'user' CHECK (role IN ('user', 'admin')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Auto-create a profile whenever a user signs up.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, email)
  VALUES (NEW.id, NEW.email)
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Backfill profiles for users who already exist.
INSERT INTO public.profiles (id, email)
SELECT id, email FROM auth.users
ON CONFLICT (id) DO NOTHING;

-- Admin check. SECURITY DEFINER so it can read profiles without recursing
-- through profiles' own RLS policies.
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'admin'
  );
$$;


-- ----------------------------------------------------------------------------
-- 2. sellers — the shops you compare between
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.sellers (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  name_bn     TEXT,
  slug        TEXT NOT NULL UNIQUE,
  logo_url    TEXT,
  website     TEXT,
  seller_type TEXT NOT NULL DEFAULT 'retail'
              CHECK (seller_type IN ('retail', 'online', 'wholesale', 'marketplace', 'bazar')),
  location    TEXT,
  city        TEXT,
  is_active   BOOLEAN NOT NULL DEFAULT TRUE,
  rating      NUMERIC(2,1) CHECK (rating IS NULL OR rating BETWEEN 0 AND 5),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.sellers ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_sellers_active ON public.sellers(is_active) WHERE is_active;


-- ----------------------------------------------------------------------------
-- 3. products — new columns for bilingual search and units
-- ----------------------------------------------------------------------------
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS name_bn  TEXT;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS brand    TEXT;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS unit     TEXT;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE;

-- One searchable column covering English + Bangla + brand, kept in sync by
-- Postgres itself. A single GIN trigram index then serves both scripts.
ALTER TABLE public.products DROP COLUMN IF EXISTS search_text;
ALTER TABLE public.products ADD COLUMN search_text TEXT
  GENERATED ALWAYS AS (
    COALESCE(name, '') || ' ' ||
    COALESCE(name_bn, '') || ' ' ||
    COALESCE(brand, '') || ' ' ||
    COALESCE(description, '')
  ) STORED;

CREATE INDEX IF NOT EXISTS idx_products_search_trgm
  ON public.products USING GIN (search_text gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_products_name_trgm
  ON public.products USING GIN (name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_products_active
  ON public.products(is_active) WHERE is_active;

-- Guard against the negative prices the original schema allowed.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'products_price_non_negative'
  ) THEN
    ALTER TABLE public.products
      ADD CONSTRAINT products_price_non_negative
      CHECK (price IS NULL OR price >= 0);
  END IF;
END $$;


-- ----------------------------------------------------------------------------
-- 4. prices — one row per (product, seller). This is the comparison table.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.prices (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id   UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  seller_id    UUID NOT NULL REFERENCES public.sellers(id)  ON DELETE CASCADE,
  price        NUMERIC(12,2) NOT NULL CHECK (price >= 0),
  currency     CHAR(3) NOT NULL DEFAULT 'BDT',
  unit         TEXT,                      -- 'kg', 'litre', 'piece'
  unit_qty     NUMERIC(10,3) NOT NULL DEFAULT 1 CHECK (unit_qty > 0),
  in_stock     BOOLEAN NOT NULL DEFAULT TRUE,
  product_url  TEXT,                      -- deep link to the seller's page
  source       TEXT NOT NULL DEFAULT 'manual'
               CHECK (source IN ('manual', 'scrape', 'api', 'import', 'user')),
  -- When this price was actually observed. THE field that makes prices trustworthy.
  collected_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT prices_unique_product_seller UNIQUE (product_id, seller_id)
);

ALTER TABLE public.prices ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_prices_product    ON public.prices(product_id);
CREATE INDEX IF NOT EXISTS idx_prices_seller     ON public.prices(seller_id);
CREATE INDEX IF NOT EXISTS idx_prices_collected  ON public.prices(collected_at DESC);
-- Serves "cheapest in-stock offer for this product" directly from the index.
CREATE INDEX IF NOT EXISTS idx_prices_product_cheapest
  ON public.prices(product_id, price) WHERE in_stock;


-- ----------------------------------------------------------------------------
-- 5. price_history — append-only, written by trigger
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.price_history (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id  UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  seller_id   UUID NOT NULL REFERENCES public.sellers(id)  ON DELETE CASCADE,
  price       NUMERIC(12,2) NOT NULL CHECK (price >= 0),
  currency    CHAR(3) NOT NULL DEFAULT 'BDT',
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.price_history ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_price_history_product
  ON public.price_history(product_id, recorded_at DESC);

-- Log every insert, and every update that actually changes the price.
CREATE OR REPLACE FUNCTION public.log_price_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' OR NEW.price IS DISTINCT FROM OLD.price THEN
    INSERT INTO public.price_history (product_id, seller_id, price, currency, recorded_at)
    VALUES (NEW.product_id, NEW.seller_id, NEW.price, NEW.currency, NEW.collected_at);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_log_price_change ON public.prices;
CREATE TRIGGER trg_log_price_change
  AFTER INSERT OR UPDATE ON public.prices
  FOR EACH ROW EXECUTE FUNCTION public.log_price_change();


-- ----------------------------------------------------------------------------
-- 6. favorites — user watchlist
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.favorites (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES auth.users(id)     ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT favorites_unique UNIQUE (user_id, product_id)
);

ALTER TABLE public.favorites ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_favorites_user ON public.favorites(user_id);


-- ----------------------------------------------------------------------------
-- 7. updated_at triggers for the new tables
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trigger_set_timestamp()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_timestamp_profiles ON public.profiles;
CREATE TRIGGER set_timestamp_profiles BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.trigger_set_timestamp();

DROP TRIGGER IF EXISTS set_timestamp_sellers ON public.sellers;
CREATE TRIGGER set_timestamp_sellers BEFORE UPDATE ON public.sellers
  FOR EACH ROW EXECUTE FUNCTION public.trigger_set_timestamp();

DROP TRIGGER IF EXISTS set_timestamp_prices ON public.prices;
CREATE TRIGGER set_timestamp_prices BEFORE UPDATE ON public.prices
  FOR EACH ROW EXECUTE FUNCTION public.trigger_set_timestamp();


-- ============================================================================
-- 8. BACKFILL — move existing products.price into the new prices table
-- ============================================================================
-- Your current data has one price per product with no seller attached. We
-- create a single placeholder seller to own those prices so nothing is lost
-- and the app keeps working immediately. Re-assign them to real sellers as
-- you add real data. products.price is LEFT IN PLACE (deprecated, not dropped).

-- Only created when there is actually something to backfill. On a fresh
-- project this inserts nothing, so you don't start with a phantom seller that
-- owns no prices.
INSERT INTO public.sellers (name, name_bn, slug, seller_type, location, city)
SELECT 'BazarCheck Listing', 'পরখ তালিকা', 'bazarcheck-listing', 'retail', 'Unassigned', 'Dhaka'
WHERE EXISTS (SELECT 1 FROM public.products WHERE price IS NOT NULL AND price >= 0)
ON CONFLICT (slug) DO NOTHING;

INSERT INTO public.prices (product_id, seller_id, price, currency, source, collected_at)
SELECT
  p.id,
  (SELECT id FROM public.sellers WHERE slug = 'bazarcheck-listing'),
  p.price,
  'BDT',
  'import',
  COALESCE(p.updated_at, p.created_at, NOW())
FROM public.products p
WHERE p.price IS NOT NULL
  AND p.price >= 0
ON CONFLICT (product_id, seller_id) DO NOTHING;


-- ============================================================================
-- 9. RLS — close the write hole
-- ============================================================================
-- BEFORE: "Enable insert/update for authenticated users only" meant ANY user
-- who signed up could rewrite ANY price. AFTER: reads stay public, writes are
-- admin-only.

-- --- products / categories / divisions: public read, admin write -----------
DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['products', 'categories', 'divisions'] LOOP
    EXECUTE format('DROP POLICY IF EXISTS "Enable read access for all users" ON public.%I', t);
    EXECUTE format('DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.%I', t);
    EXECUTE format('DROP POLICY IF EXISTS "Enable update for authenticated users only" ON public.%I', t);
    EXECUTE format('DROP POLICY IF EXISTS "%s_public_read" ON public.%I', t, t);
    EXECUTE format('DROP POLICY IF EXISTS "%s_admin_write" ON public.%I', t, t);

    EXECUTE format(
      'CREATE POLICY "%s_public_read" ON public.%I FOR SELECT USING (true)', t, t);
    EXECUTE format(
      'CREATE POLICY "%s_admin_write" ON public.%I FOR ALL TO authenticated '
      'USING (public.is_admin()) WITH CHECK (public.is_admin())', t, t);
  END LOOP;
END $$;

-- --- sellers / prices / price_history: public read, admin write ------------
DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['sellers', 'prices', 'price_history'] LOOP
    EXECUTE format('DROP POLICY IF EXISTS "%s_public_read" ON public.%I', t, t);
    EXECUTE format('DROP POLICY IF EXISTS "%s_admin_write" ON public.%I', t, t);

    EXECUTE format(
      'CREATE POLICY "%s_public_read" ON public.%I FOR SELECT USING (true)', t, t);
    EXECUTE format(
      'CREATE POLICY "%s_admin_write" ON public.%I FOR ALL TO authenticated '
      'USING (public.is_admin()) WITH CHECK (public.is_admin())', t, t);
  END LOOP;
END $$;

-- --- profiles: users see and edit only their own row -----------------------
DROP POLICY IF EXISTS "profiles_self_read"   ON public.profiles;
DROP POLICY IF EXISTS "profiles_self_update" ON public.profiles;
CREATE POLICY "profiles_self_read" ON public.profiles
  FOR SELECT TO authenticated USING (auth.uid() = id);
-- Note: role is deliberately NOT self-editable — see the guard trigger below.
CREATE POLICY "profiles_self_update" ON public.profiles
  FOR UPDATE TO authenticated USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

-- Stop a user from promoting themselves to admin via profiles_self_update.
--
-- auth.uid() IS NULL means there is no end user in context - i.e. the SQL
-- Editor, service_role, or a server-side job. Those are trusted and MUST be
-- allowed through, otherwise there would be no way to create the very first
-- admin (see the bootstrap note at the end of this file).
CREATE OR REPLACE FUNCTION public.guard_profile_role()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.role IS DISTINCT FROM OLD.role
     AND auth.uid() IS NOT NULL
     AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only an admin can change a role';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_profile_role ON public.profiles;
CREATE TRIGGER trg_guard_profile_role
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.guard_profile_role();

-- --- favorites: fully owner-scoped -----------------------------------------
DROP POLICY IF EXISTS "favorites_owner_all" ON public.favorites;
CREATE POLICY "favorites_owner_all" ON public.favorites
  FOR ALL TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- --- ai_results: add the missing UPDATE + DELETE policies ------------------
DROP POLICY IF EXISTS "ai_results_owner_update" ON public.ai_results;
DROP POLICY IF EXISTS "ai_results_owner_delete" ON public.ai_results;
CREATE POLICY "ai_results_owner_update" ON public.ai_results
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "ai_results_owner_delete" ON public.ai_results
  FOR DELETE TO authenticated USING (auth.uid() = user_id);


-- ============================================================================
-- 10. RPC functions — the app calls these instead of assembling joins client-side
-- ============================================================================

-- ---------------------------------------------------------------------------
-- search_products: bilingual search + filters + sort + price summary,
-- all in ONE round trip. Empty query = browse mode.
-- ---------------------------------------------------------------------------
-- NOTE: every input parameter is p_-prefixed on purpose. Naming an input the
-- same as a RETURNS TABLE column (e.g. min_price) makes the reference ambiguous
-- inside the body and silently disables the filter.
DROP FUNCTION IF EXISTS public.search_products(TEXT, UUID, UUID, NUMERIC, NUMERIC, TEXT, INT, INT);
CREATE FUNCTION public.search_products(
  p_query     TEXT    DEFAULT NULL,
  p_category  UUID    DEFAULT NULL,
  p_division  UUID    DEFAULT NULL,
  p_min_price NUMERIC DEFAULT NULL,
  p_max_price NUMERIC DEFAULT NULL,
  p_sort      TEXT    DEFAULT 'relevance',  -- relevance|price_asc|price_desc|name|newest
  p_limit     INT     DEFAULT 20,
  p_offset    INT     DEFAULT 0
)
RETURNS TABLE (
  id            UUID,
  name          TEXT,
  name_bn       TEXT,
  brand         TEXT,
  description   TEXT,
  image_url     TEXT,
  unit          TEXT,
  category_id   UUID,
  category_name TEXT,
  min_price     NUMERIC,
  max_price     NUMERIC,
  seller_count  INT,
  last_updated  TIMESTAMPTZ,
  total_count   BIGINT
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  WITH summary AS (
    SELECT
      pr.product_id,
      MIN(pr.price)      AS min_price,
      MAX(pr.price)      AS max_price,
      COUNT(*)::INT      AS seller_count,
      MAX(pr.collected_at) AS last_updated
    FROM public.prices pr
    WHERE pr.in_stock
    GROUP BY pr.product_id
  ),
  filtered AS (
    SELECT
      p.id, p.name, p.name_bn, p.brand, p.description, p.image_url, p.unit,
      p.category_id, c.name AS category_name, p.created_at,
      s.min_price, s.max_price,
      COALESCE(s.seller_count, 0) AS seller_count,
      s.last_updated,
      CASE
        WHEN p_query IS NULL OR btrim(p_query) = '' THEN 0
        ELSE GREATEST(
               similarity(COALESCE(p.name, ''),    p_query),
               similarity(COALESCE(p.name_bn, ''), p_query),
               similarity(COALESCE(p.brand, ''),   p_query)
             )
      END AS relevance
    FROM public.products p
    LEFT JOIN summary    s ON s.product_id  = p.id
    LEFT JOIN public.categories c ON c.id   = p.category_id
    WHERE p.is_active
      AND (p_query IS NULL OR btrim(p_query) = ''
           OR p.search_text ILIKE '%' || btrim(p_query) || '%')
      AND (p_category  IS NULL OR p.category_id = p_category)
      AND (p_division  IS NULL OR c.division_id = p_division)
      AND (p_min_price IS NULL OR s.min_price  >= p_min_price)
      AND (p_max_price IS NULL OR s.min_price  <= p_max_price)
  ),
  counted AS (SELECT COUNT(*) AS n FROM filtered)
  SELECT
    f.id, f.name, f.name_bn, f.brand, f.description, f.image_url, f.unit,
    f.category_id, f.category_name,
    f.min_price, f.max_price, f.seller_count, f.last_updated,
    (SELECT n FROM counted) AS total_count
  FROM filtered f
  ORDER BY
    CASE WHEN p_sort = 'price_asc'  THEN f.min_price  END ASC  NULLS LAST,
    CASE WHEN p_sort = 'price_desc' THEN f.min_price  END DESC NULLS LAST,
    CASE WHEN p_sort = 'newest'     THEN f.created_at END DESC NULLS LAST,
    CASE WHEN p_sort = 'relevance'  THEN f.relevance  END DESC NULLS LAST,
    f.name ASC
  LIMIT  GREATEST(1, LEAST(p_limit, 100))
  OFFSET GREATEST(0, p_offset);
$$;


-- ---------------------------------------------------------------------------
-- get_product_offers: every seller's price for one product, cheapest first.
-- This is the price comparison view.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_product_offers(UUID);
CREATE FUNCTION public.get_product_offers(p_product_id UUID)
RETURNS TABLE (
  price_id      UUID,
  seller_id     UUID,
  seller_name   TEXT,
  seller_name_bn TEXT,
  seller_type   TEXT,
  seller_logo   TEXT,
  location      TEXT,
  rating        NUMERIC,
  price         NUMERIC,
  currency      CHAR(3),
  unit          TEXT,
  unit_qty      NUMERIC,
  in_stock      BOOLEAN,
  product_url   TEXT,
  source        TEXT,
  collected_at  TIMESTAMPTZ,
  is_cheapest   BOOLEAN,
  pct_above_min NUMERIC
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  WITH offers AS (
    SELECT
      pr.id AS price_id, s.id AS seller_id, s.name AS seller_name,
      s.name_bn AS seller_name_bn, s.seller_type, s.logo_url AS seller_logo,
      s.location, s.rating,
      pr.price, pr.currency, pr.unit, pr.unit_qty, pr.in_stock,
      pr.product_url, pr.source, pr.collected_at
    FROM public.prices pr
    JOIN public.sellers s ON s.id = pr.seller_id
    WHERE pr.product_id = p_product_id AND s.is_active
  ),
  cheapest AS (
    SELECT MIN(price) AS m FROM offers WHERE in_stock
  )
  SELECT
    o.*,
    (o.in_stock AND o.price = (SELECT m FROM cheapest)) AS is_cheapest,
    CASE
      WHEN (SELECT m FROM cheapest) IS NULL OR (SELECT m FROM cheapest) = 0 THEN NULL
      ELSE ROUND(((o.price - (SELECT m FROM cheapest)) / (SELECT m FROM cheapest)) * 100, 1)
    END AS pct_above_min
  FROM offers o
  ORDER BY o.in_stock DESC, o.price ASC;
$$;


-- ---------------------------------------------------------------------------
-- get_best_deals: biggest spread between cheapest and dearest seller.
-- Powers the home screen — "you could save ৳X on these".
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_best_deals(INT);
CREATE FUNCTION public.get_best_deals(p_limit INT DEFAULT 10)
RETURNS TABLE (
  id           UUID,
  name         TEXT,
  name_bn      TEXT,
  image_url    TEXT,
  unit         TEXT,
  min_price    NUMERIC,
  max_price    NUMERIC,
  savings      NUMERIC,
  savings_pct  NUMERIC,
  seller_count INT,
  last_updated TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT
    p.id, p.name, p.name_bn, p.image_url, p.unit,
    MIN(pr.price) AS min_price,
    MAX(pr.price) AS max_price,
    MAX(pr.price) - MIN(pr.price) AS savings,
    CASE WHEN MAX(pr.price) = 0 THEN 0
         ELSE ROUND(((MAX(pr.price) - MIN(pr.price)) / MAX(pr.price)) * 100, 1)
    END AS savings_pct,
    COUNT(*)::INT AS seller_count,
    MAX(pr.collected_at) AS last_updated
  FROM public.products p
  JOIN public.prices pr ON pr.product_id = p.id AND pr.in_stock
  WHERE p.is_active
  GROUP BY p.id, p.name, p.name_bn, p.image_url, p.unit
  HAVING COUNT(*) > 1 AND MAX(pr.price) > MIN(pr.price)
  ORDER BY savings_pct DESC NULLS LAST
  LIMIT GREATEST(1, LEAST(p_limit, 50));
$$;


-- ---------------------------------------------------------------------------
-- get_price_history: chart data for one product
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_price_history(UUID, INT);
CREATE FUNCTION public.get_price_history(p_product_id UUID, p_days INT DEFAULT 90)
RETURNS TABLE (day DATE, min_price NUMERIC, avg_price NUMERIC, max_price NUMERIC)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT
    recorded_at::DATE AS day,
    MIN(price)                AS min_price,
    ROUND(AVG(price), 2)      AS avg_price,
    MAX(price)                AS max_price
  FROM public.price_history
  WHERE product_id = p_product_id
    AND recorded_at >= NOW() - (GREATEST(1, p_days) || ' days')::INTERVAL
  GROUP BY 1
  ORDER BY 1 ASC;
$$;


-- ---------------------------------------------------------------------------
-- Grants: anonymous users can read. This is what enables browsing without login.
-- ---------------------------------------------------------------------------
GRANT EXECUTE ON FUNCTION public.search_products(TEXT, UUID, UUID, NUMERIC, NUMERIC, TEXT, INT, INT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_product_offers(UUID)      TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_best_deals(INT)           TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_price_history(UUID, INT)  TO anon, authenticated;


-- ============================================================================
-- AFTER RUNNING THIS: make yourself an admin
-- ============================================================================
-- Replace the email with your own, then run:
--
--   UPDATE public.profiles SET role = 'admin' WHERE email = 'you@example.com';
--
-- Until you do, NOBODY can write price data from the app — which is the point.
-- Use the Supabase dashboard (service_role) or an admin account for imports.
-- ============================================================================


-- ==========================================================================
-- PART 3 of 6 — FAVOURITES RPC
-- ==========================================================================

-- ============================================================================
-- BazarCheck — Migration 003: favourites RPC
-- ============================================================================
-- Fixes a real scaling bug. The app previously loaded favourites by fetching
-- the first 100 products and filtering client-side, so a favourite ranked 101st
-- silently vanished from the list.
--
-- This returns the favourited products directly, with the same price summary
-- shape as search_products, so the same ProductCard renders them.
--
-- Scoped by auth.uid() rather than taking a user_id argument: there is then no
-- way to ask for somebody else's favourites, regardless of what the client
-- sends.
--
-- ADDITIVE AND IDEMPOTENT.
-- ============================================================================

DROP FUNCTION IF EXISTS public.get_favorite_products(INT, INT);
CREATE FUNCTION public.get_favorite_products(
  p_limit  INT DEFAULT 100,
  p_offset INT DEFAULT 0
)
RETURNS TABLE (
  id            UUID,
  name          TEXT,
  name_bn       TEXT,
  brand         TEXT,
  description   TEXT,
  image_url     TEXT,
  unit          TEXT,
  category_id   UUID,
  category_name TEXT,
  min_price     NUMERIC,
  max_price     NUMERIC,
  seller_count  INT,
  last_updated  TIMESTAMPTZ,
  total_count   BIGINT
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  WITH mine AS (
    SELECT f.product_id, f.created_at
    FROM public.favorites f
    WHERE f.user_id = auth.uid()
  ),
  summary AS (
    SELECT
      pr.product_id,
      MIN(pr.price)        AS min_price,
      MAX(pr.price)        AS max_price,
      COUNT(*)::INT        AS seller_count,
      MAX(pr.collected_at) AS last_updated
    FROM public.prices pr
    JOIN mine m ON m.product_id = pr.product_id
    WHERE pr.in_stock
    GROUP BY pr.product_id
  ),
  counted AS (SELECT COUNT(*) AS n FROM mine)
  SELECT
    p.id, p.name, p.name_bn, p.brand, p.description, p.image_url, p.unit,
    p.category_id, c.name AS category_name,
    s.min_price, s.max_price,
    COALESCE(s.seller_count, 0) AS seller_count,
    s.last_updated,
    (SELECT n FROM counted) AS total_count
  FROM mine m
  JOIN public.products p       ON p.id = m.product_id
  LEFT JOIN summary s          ON s.product_id = p.id
  LEFT JOIN public.categories c ON c.id = p.category_id
  WHERE p.is_active
  ORDER BY m.created_at DESC          -- most recently saved first
  LIMIT  GREATEST(1, LEAST(p_limit, 200))
  OFFSET GREATEST(0, p_offset);
$$;

-- Authenticated only: an anonymous caller has no auth.uid() and would always
-- get an empty set, so there is no reason to expose it to anon.
GRANT EXECUTE ON FUNCTION public.get_favorite_products(INT, INT) TO authenticated;


-- ==========================================================================
-- PART 4 of 6 — GOVT RATES + REGIONS
-- ==========================================================================

-- ============================================================================
-- BazarCheck — Migration 004: government rates + geographic regions
-- ============================================================================
-- Adds the two axes the BazarCheck design compares on, which the seller-vs-
-- seller model alone could not express:
--
--   1. GOVT FIXED vs LOCAL MARKET   — the official rate against what shops
--                                     actually charge, and the gap between them
--   2. Geographic region            — Dhaka / Chittagong / Rajshahi / …
--
-- Note on naming: the existing `divisions` table holds PRODUCT groups
-- ("Food & Grocery"), not Bangladesh's administrative divisions. To avoid a
-- confusing collision this migration introduces `regions` for geography and
-- leaves `divisions` alone.
--
-- ADDITIVE AND IDEMPOTENT.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Government-fixed rate on products
-- ----------------------------------------------------------------------------
-- The officially published rate (TCB / DNCRP). Nullable, because most products
-- do not have one — only essential commodities are rate-controlled, and the UI
-- must show nothing rather than invent a figure.
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS govt_fixed_price NUMERIC(12,2)
    CHECK (govt_fixed_price IS NULL OR govt_fixed_price >= 0);

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS govt_price_updated_at TIMESTAMPTZ;

-- Marks the staples that appear under "Daily Essentials" on the home screen.
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS is_essential BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_products_essential
  ON public.products(is_essential) WHERE is_essential;


-- ----------------------------------------------------------------------------
-- 2. Regions — Bangladesh's eight administrative divisions
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.regions (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name       TEXT NOT NULL UNIQUE,
  name_bn    TEXT,
  slug       TEXT NOT NULL UNIQUE,
  latitude   NUMERIC(9,6),
  longitude  NUMERIC(9,6),
  is_active  BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.regions ENABLE ROW LEVEL SECURITY;

INSERT INTO public.regions (name, name_bn, slug, latitude, longitude) VALUES
  ('Dhaka',      'ঢাকা',        'dhaka',      23.810332, 90.412518),
  ('Chittagong', 'চট্টগ্রাম',    'chittagong', 22.356851, 91.783182),
  ('Rajshahi',   'রাজশাহী',     'rajshahi',   24.363589, 88.624135),
  ('Khulna',     'খুলনা',        'khulna',     22.845641, 89.540328),
  ('Barishal',   'বরিশাল',      'barishal',   22.701002, 90.353451),
  ('Sylhet',     'সিলেট',       'sylhet',     24.894929, 91.868706),
  ('Rangpur',    'রংপুর',       'rangpur',    25.746058, 89.275227),
  ('Mymensingh', 'ময়মনসিংহ',   'mymensingh', 24.747149, 90.420273)
ON CONFLICT (slug) DO NOTHING;


-- ----------------------------------------------------------------------------
-- 3. Attach sellers/markets to a region
-- ----------------------------------------------------------------------------
ALTER TABLE public.sellers
  ADD COLUMN IF NOT EXISTS region_id UUID REFERENCES public.regions(id) ON DELETE SET NULL;

ALTER TABLE public.sellers ADD COLUMN IF NOT EXISTS latitude  NUMERIC(9,6);
ALTER TABLE public.sellers ADD COLUMN IF NOT EXISTS longitude NUMERIC(9,6);

CREATE INDEX IF NOT EXISTS idx_sellers_region ON public.sellers(region_id);

-- Existing sellers all sit in Dhaka.
UPDATE public.sellers
   SET region_id = (SELECT id FROM public.regions WHERE slug = 'dhaka')
 WHERE region_id IS NULL;


-- ----------------------------------------------------------------------------
-- 4. RLS — public read, admin write (same posture as everything else)
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "regions_public_read" ON public.regions;
DROP POLICY IF EXISTS "regions_admin_write" ON public.regions;
CREATE POLICY "regions_public_read" ON public.regions FOR SELECT USING (true);
CREATE POLICY "regions_admin_write" ON public.regions FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());


-- ============================================================================
-- 5. RPC: essentials for the home screen
-- ============================================================================
-- Government rate beside the local market average, with the gap between them.
DROP FUNCTION IF EXISTS public.get_essentials(INT);
CREATE FUNCTION public.get_essentials(p_limit INT DEFAULT 20)
RETURNS TABLE (
  id                UUID,
  name              TEXT,
  name_bn           TEXT,
  image_url         TEXT,
  unit              TEXT,
  govt_fixed_price  NUMERIC,
  local_avg_price   NUMERIC,
  local_min_price   NUMERIC,
  price_gap         NUMERIC,
  gap_percent       NUMERIC,
  status            TEXT,   -- spike | stable | drop | unknown
  seller_count      INT,
  last_updated      TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  WITH local AS (
    SELECT
      pr.product_id,
      ROUND(AVG(pr.price), 2) AS avg_price,
      MIN(pr.price)           AS min_price,
      COUNT(*)::INT           AS seller_count,
      MAX(pr.collected_at)    AS last_updated
    FROM public.prices pr
    WHERE pr.in_stock
    GROUP BY pr.product_id
  )
  SELECT
    p.id, p.name, p.name_bn, p.image_url, p.unit,
    p.govt_fixed_price,
    l.avg_price,
    l.min_price,
    CASE WHEN p.govt_fixed_price IS NULL OR l.avg_price IS NULL THEN NULL
         ELSE ROUND(l.avg_price - p.govt_fixed_price, 2) END,
    CASE WHEN p.govt_fixed_price IS NULL OR p.govt_fixed_price = 0
              OR l.avg_price IS NULL THEN NULL
         ELSE ROUND(((l.avg_price - p.govt_fixed_price) / p.govt_fixed_price) * 100, 1) END,
    -- >10% over the official rate is a spike; at or under it is a drop.
    CASE
      WHEN p.govt_fixed_price IS NULL OR l.avg_price IS NULL THEN 'unknown'
      WHEN l.avg_price > p.govt_fixed_price * 1.10 THEN 'spike'
      WHEN l.avg_price <= p.govt_fixed_price       THEN 'drop'
      ELSE 'stable'
    END,
    COALESCE(l.seller_count, 0),
    l.last_updated
  FROM public.products p
  LEFT JOIN local l ON l.product_id = p.id
  WHERE p.is_active AND p.is_essential
  ORDER BY
    CASE WHEN p.govt_fixed_price IS NULL OR l.avg_price IS NULL THEN 1 ELSE 0 END,
    (l.avg_price - p.govt_fixed_price) DESC NULLS LAST,
    p.name
  LIMIT GREATEST(1, LEAST(p_limit, 100));
$$;


-- ============================================================================
-- 6. RPC: regional price table on the product page
-- ============================================================================
DROP FUNCTION IF EXISTS public.get_regional_prices(UUID);
CREATE FUNCTION public.get_regional_prices(p_product_id UUID)
RETURNS TABLE (
  region_id     UUID,
  region_name   TEXT,
  region_name_bn TEXT,
  avg_price     NUMERIC,
  min_price     NUMERIC,
  seller_count  INT,
  last_updated  TIMESTAMPTZ,
  trend_percent NUMERIC
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  WITH current AS (
    SELECT
      r.id, r.name, r.name_bn,
      ROUND(AVG(pr.price), 2) AS avg_price,
      MIN(pr.price)           AS min_price,
      COUNT(*)::INT           AS seller_count,
      MAX(pr.collected_at)    AS last_updated
    FROM public.prices pr
    JOIN public.sellers s ON s.id = pr.seller_id
    JOIN public.regions r ON r.id = s.region_id
    WHERE pr.product_id = p_product_id AND pr.in_stock AND s.is_active
    GROUP BY r.id, r.name, r.name_bn
  ),
  past AS (
    -- Average a week ago, to derive the trend arrow.
    SELECT s.region_id, ROUND(AVG(h.price), 2) AS avg_price
    FROM public.price_history h
    JOIN public.sellers s ON s.id = h.seller_id
    WHERE h.product_id = p_product_id
      AND h.recorded_at BETWEEN NOW() - INTERVAL '10 days' AND NOW() - INTERVAL '5 days'
    GROUP BY s.region_id
  )
  SELECT
    c.id, c.name, c.name_bn, c.avg_price, c.min_price, c.seller_count, c.last_updated,
    CASE WHEN pa.avg_price IS NULL OR pa.avg_price = 0 THEN NULL
         ELSE ROUND(((c.avg_price - pa.avg_price) / pa.avg_price) * 100, 1) END
  FROM current c
  LEFT JOIN past pa ON pa.region_id = c.id
  ORDER BY c.avg_price ASC;
$$;


GRANT EXECUTE ON FUNCTION public.get_essentials(INT)         TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_regional_prices(UUID)   TO anon, authenticated;


-- ==========================================================================
-- PART 5 of 6 — SAMPLE CATALOGUE
-- ==========================================================================

-- ============================================================================
-- BazarCheck — seed data
-- ============================================================================
-- ILLUSTRATIVE SAMPLE DATA. These are plausible Bangladeshi retail figures used
-- to exercise the UI; they are NOT live market prices and must not be presented
-- as such. Replace with real observations before showing this to any user.
--
-- Deliberately includes prices at every freshness level (fresh / recent / stale
-- / outdated) and one out-of-stock offer, so the trust signals in the UI are
-- visible without waiting for data to age.
--
-- Idempotent: re-running will not duplicate anything.
--
-- Applied automatically by `supabase db reset`, or manually with:
--   psql "$DATABASE_URL" -f supabase/seed.sql
-- ============================================================================


-- ----------------------------------------------------------------------------
-- Divisions
-- ----------------------------------------------------------------------------
INSERT INTO public.divisions (name, description)
SELECT v.name, v.description
FROM (VALUES
  ('Food & Grocery', 'Rice, oil, lentils and everyday staples'),
  ('Fresh Market',   'Vegetables, fish and dairy'),
  ('Electronics',    'Phones and gadgets')
) AS v(name, description)
WHERE NOT EXISTS (SELECT 1 FROM public.divisions d WHERE d.name = v.name);

-- ----------------------------------------------------------------------------
-- Categories
-- ----------------------------------------------------------------------------
INSERT INTO public.categories (name, division_id, description)
SELECT v.name, d.id, v.description
FROM (VALUES
  ('Rice',            'Food & Grocery', 'চাল'),
  ('Edible Oil',      'Food & Grocery', 'ভোজ্য তেল'),
  ('Lentils',         'Food & Grocery', 'ডাল'),
  ('Sugar & Flour',   'Food & Grocery', 'চিনি ও আটা'),
  ('Vegetables',      'Fresh Market',   'সবজি'),
  ('Eggs & Dairy',    'Fresh Market',   'ডিম ও দুধ'),
  ('Fish',            'Fresh Market',   'মাছ'),
  ('Mobile Phones',   'Electronics',    'মোবাইল ফোন')
) AS v(name, division, description)
JOIN public.divisions d ON d.name = v.division
WHERE NOT EXISTS (SELECT 1 FROM public.categories c WHERE c.name = v.name);

-- ----------------------------------------------------------------------------
-- Sellers
-- ----------------------------------------------------------------------------
INSERT INTO public.sellers (name, name_bn, slug, seller_type, location, city, rating)
VALUES
  ('Shwapno',       'স্বপ্ন',          'shwapno',      'retail',      'Dhanmondi',    'Dhaka', 4.2),
  ('Meena Bazar',   'মীনা বাজার',     'meena-bazar',  'retail',      'Gulshan',      'Dhaka', 4.0),
  ('Agora',         'আগোরা',          'agora',        'retail',      'Mohammadpur',  'Dhaka', 4.1),
  ('Unimart',       'ইউনিমার্ট',      'unimart',      'retail',      'Gulshan',      'Dhaka', 4.3),
  ('Chaldal',       'চালডাল',         'chaldal',      'online',      'Online',       'Dhaka', 4.4),
  ('Daraz',         'দারাজ',          'daraz',        'marketplace', 'Online',       'Dhaka', 3.9),
  ('Karwan Bazar',  'কারওয়ান বাজার', 'karwan-bazar', 'bazar',       'Karwan Bazar', 'Dhaka', 3.7)
ON CONFLICT (slug) DO NOTHING;

-- ----------------------------------------------------------------------------
-- Products  (English + Bangla names, so search works in both scripts)
-- ----------------------------------------------------------------------------
INSERT INTO public.products (name, name_bn, brand, unit, category_id, description, image_url)
SELECT v.name, v.name_bn, v.brand, v.unit, c.id, v.description, v.image_url
FROM (VALUES
  ('Miniket Rice',      'মিনিকেট চাল',       'ACI',       'kg',    'Rice',          'Premium polished miniket rice', 'https://placehold.co/600x600/e8d9b5/3f3f46/png?text=Miniket+Rice'),
  ('Nazirshail Rice',   'নাজিরশাইল চাল',     'Pran',      'kg',    'Rice',          'Aromatic nazirshail rice', 'https://placehold.co/600x600/e0cfa8/3f3f46/png?text=Nazirshail+Rice'),
  ('Chinigura Rice',    'চিনিগুঁড়া চাল',     'Teer',      'kg',    'Rice',          'Fragrant polao rice', 'https://placehold.co/600x600/efe3c7/3f3f46/png?text=Chinigura+Rice'),
  ('Soybean Oil 1L',    'সয়াবিন তেল ১ লিটার','Fresh',     'litre', 'Edible Oil',    'Fortified soybean oil, 1 litre bottle', 'https://placehold.co/600x600/f2d675/3f3f46/png?text=Soybean+Oil+1L'),
  ('Soybean Oil 5L',    'সয়াবিন তেল ৫ লিটার','Rupchanda', 'litre', 'Edible Oil',    'Fortified soybean oil, 5 litre can', 'https://placehold.co/600x600/e8c95a/3f3f46/png?text=Soybean+Oil+5L'),
  ('Mustard Oil 1L',    'সরিষার তেল',        'Radhuni',   'litre', 'Edible Oil',    'Cold pressed mustard oil', 'https://placehold.co/600x600/d9a441/3f3f46/png?text=Mustard+Oil+1L'),
  ('Masoor Dal',        'মসুর ডাল',          'Teer',      'kg',    'Lentils',       'Red lentils', 'https://placehold.co/600x600/e2a06a/3f3f46/png?text=Masoor+Dal'),
  ('Chola Dal',         'ছোলা ডাল',          'Pran',      'kg',    'Lentils',       'Split chickpea lentils', 'https://placehold.co/600x600/d8b271/3f3f46/png?text=Chola+Dal'),
  ('Sugar',             'চিনি',              'Fresh',     'kg',    'Sugar & Flour', 'Refined white sugar', 'https://placehold.co/600x600/f5f2ea/3f3f46/png?text=Sugar'),
  ('Atta',              'আটা',               'Teer',      'kg',    'Sugar & Flour', 'Whole wheat flour', 'https://placehold.co/600x600/e6d7bd/3f3f46/png?text=Atta'),
  ('Onion',             'পেঁয়াজ',            NULL,        'kg',    'Vegetables',    'Local onion', 'https://placehold.co/600x600/c98c9a/3f3f46/png?text=Onion'),
  ('Potato',            'আলু',               NULL,        'kg',    'Vegetables',    'Local potato', 'https://placehold.co/600x600/d9c3a0/3f3f46/png?text=Potato'),
  ('Farm Eggs (dozen)', 'ফার্মের ডিম',       NULL,        'dozen', 'Eggs & Dairy',  'Brown farm eggs, 12 pieces', 'https://placehold.co/600x600/f0e2c8/3f3f46/png?text=Farm+Eggs'),
  ('Rui Fish',          'রুই মাছ',           NULL,        'kg',    'Fish',          'Fresh rui, medium size', 'https://placehold.co/600x600/bcd3d9/3f3f46/png?text=Rui+Fish')
) AS v(name, name_bn, brand, unit, category, description, image_url)
JOIN public.categories c ON c.name = v.category
WHERE NOT EXISTS (SELECT 1 FROM public.products p WHERE p.name = v.name);

-- ----------------------------------------------------------------------------
-- Prices — the whole point. Several sellers per product, at different ages.
-- ----------------------------------------------------------------------------
-- collected_at spread on purpose:
--   NOW()            -> "just now"   (green)
--   NOW() - 3 days   -> "3d ago"     (neutral)
--   NOW() - 12 days  -> "12d ago"    (amber, stale)
--   NOW() - 45 days  -> "1mo ago"    (red, outdated)
INSERT INTO public.prices
  (product_id, seller_id, price, unit, unit_qty, in_stock, source, collected_at, product_url)
SELECT p.id, s.id, v.price, p.unit, v.unit_qty, v.in_stock, 'manual',
       NOW() - (v.age_hours || ' hours')::INTERVAL, v.url
FROM (VALUES
  -- Miniket Rice: wide spread, the flagship comparison example
  ('Miniket Rice',      'chaldal',      72.00, 1,   TRUE,  2,    'https://chaldal.com'),
  ('Miniket Rice',      'shwapno',      78.00, 1,   TRUE,  5,    NULL),
  ('Miniket Rice',      'agora',        80.00, 1,   TRUE,  30,   NULL),
  ('Miniket Rice',      'meena-bazar',  85.50, 1,   TRUE,  72,   NULL),
  ('Miniket Rice',      'karwan-bazar', 70.00, 1,   TRUE,  288,  NULL),   -- 12d, stale

  ('Nazirshail Rice',   'shwapno',      82.00, 1,   TRUE,  6,    NULL),
  ('Nazirshail Rice',   'chaldal',      79.50, 1,   TRUE,  3,    'https://chaldal.com'),
  ('Nazirshail Rice',   'unimart',      88.00, 1,   TRUE,  48,   NULL),

  ('Chinigura Rice',    'meena-bazar', 135.00, 1,   TRUE,  10,   NULL),
  ('Chinigura Rice',    'agora',       142.00, 1,   TRUE,  1080, NULL),   -- 45d, outdated

  -- Oil: 5L can vs 1L bottle shows per-unit normalisation
  ('Soybean Oil 1L',    'chaldal',     172.00, 1,   TRUE,  1,    'https://chaldal.com'),
  ('Soybean Oil 1L',    'shwapno',     178.00, 1,   TRUE,  8,    NULL),
  ('Soybean Oil 1L',    'meena-bazar', 175.00, 1,   TRUE,  60,   NULL),
  ('Soybean Oil 1L',    'daraz',       169.00, 1,   FALSE, 4,    'https://daraz.com.bd'),  -- out of stock

  ('Soybean Oil 5L',    'chaldal',     845.00, 5,   TRUE,  2,    'https://chaldal.com'),
  ('Soybean Oil 5L',    'shwapno',     880.00, 5,   TRUE,  26,   NULL),
  ('Soybean Oil 5L',    'unimart',     865.00, 5,   TRUE,  50,   NULL),

  ('Mustard Oil 1L',    'shwapno',     320.00, 1,   TRUE,  30,   NULL),
  ('Mustard Oil 1L',    'agora',       335.00, 1,   TRUE,  288,  NULL),   -- stale

  ('Masoor Dal',        'karwan-bazar',128.00, 1,   TRUE,  288,  NULL),   -- stale
  ('Masoor Dal',        'chaldal',     138.00, 1,   TRUE,  1,    'https://chaldal.com'),
  ('Masoor Dal',        'shwapno',     142.00, 1,   TRUE,  12,   NULL),
  ('Masoor Dal',        'meena-bazar', 145.00, 1,   TRUE,  70,   NULL),

  ('Chola Dal',         'shwapno',     108.00, 1,   TRUE,  14,   NULL),
  ('Chola Dal',         'chaldal',     112.00, 1,   TRUE,  2,    'https://chaldal.com'),

  ('Sugar',             'chaldal',     122.00, 1,   TRUE,  3,    'https://chaldal.com'),
  ('Sugar',             'shwapno',     125.00, 1,   TRUE,  20,   NULL),
  ('Sugar',             'agora',       130.00, 1,   TRUE,  55,   NULL),

  ('Atta',              'shwapno',      52.00, 1,   TRUE,  9,    NULL),
  ('Atta',              'chaldal',      49.50, 1,   TRUE,  2,    'https://chaldal.com'),
  ('Atta',              'unimart',      55.00, 1,   TRUE,  75,   NULL),

  -- Fresh produce: bazar is cheapest but least fresh data — a real tradeoff
  ('Onion',             'karwan-bazar', 58.00, 1,   TRUE,  288,  NULL),   -- stale
  ('Onion',             'chaldal',      72.00, 1,   TRUE,  1,    'https://chaldal.com'),
  ('Onion',             'shwapno',      75.00, 1,   TRUE,  6,    NULL),

  ('Potato',            'karwan-bazar', 28.00, 1,   TRUE,  288,  NULL),   -- stale
  ('Potato',            'chaldal',      35.00, 1,   TRUE,  1,    'https://chaldal.com'),
  ('Potato',            'shwapno',      38.00, 1,   TRUE,  6,    NULL),

  ('Farm Eggs (dozen)', 'chaldal',     142.00, 1,   TRUE,  2,    'https://chaldal.com'),
  ('Farm Eggs (dozen)', 'shwapno',     148.00, 1,   TRUE,  7,    NULL),
  ('Farm Eggs (dozen)', 'meena-bazar', 155.00, 1,   TRUE,  40,   NULL),

  ('Rui Fish',          'karwan-bazar',320.00, 1,   TRUE,  288,  NULL),   -- stale
  ('Rui Fish',          'chaldal',     380.00, 1,   TRUE,  3,    'https://chaldal.com'),
  ('Rui Fish',          'agora',       395.00, 1,   TRUE,  28,   NULL)
) AS v(product, seller, price, unit_qty, in_stock, age_hours, url)
JOIN public.products p ON p.name  = v.product
JOIN public.sellers  s ON s.slug  = v.seller
ON CONFLICT (product_id, seller_id) DO NOTHING;

-- ----------------------------------------------------------------------------
-- Synthetic price history, so trend detection and the history chart have data
-- ----------------------------------------------------------------------------
-- Miniket rice trending DOWN over 30 days; onion trending UP. The trigger on
-- `prices` only records changes from now on, so we backfill the past here.
INSERT INTO public.price_history (product_id, seller_id, price, currency, recorded_at)
SELECT
  p.id,
  s.id,
  CASE p.name
    WHEN 'Miniket Rice' THEN 88.00 - (d * 0.55)          -- 88 -> ~72
    WHEN 'Onion'        THEN 48.00 + (d * 0.85)          -- 48 -> ~73
    ELSE 100.00
  END::NUMERIC(12,2),
  'BDT',
  NOW() - ((30 - d) || ' days')::INTERVAL
FROM public.products p
JOIN public.sellers s ON s.slug = 'chaldal'
CROSS JOIN generate_series(0, 29) AS d
WHERE p.name IN ('Miniket Rice', 'Onion')
  AND NOT EXISTS (
    SELECT 1 FROM public.price_history h
    WHERE h.product_id = p.id AND h.seller_id = s.id
      AND h.recorded_at < NOW() - INTERVAL '1 day'
  );


-- ============================================================================
-- What you should see after this runs
-- ============================================================================
--   Home        "Biggest savings" led by Chinigura Rice and Miniket Rice
--   Search      "চাল" or "rice" -> 3 products;  "তেল" or "oil" -> 3
--   Detail      Miniket Rice: 5 sellers, Karwan Bazar cheapest at ৳70 but
--               flagged 12 days old; Chaldal ৳72 checked 2 hours ago
--   Freshness   green / neutral / amber / red all visible across the catalogue
--   Stock       Daraz's Soybean Oil 1L listed but greyed out as out of stock
-- ============================================================================


-- ==========================================================================
-- PART 6 of 6 — SAMPLE GOVT RATES
-- ==========================================================================

-- ============================================================================
-- BazarCheck — government rates + regional spread (SAMPLE DATA)
-- ============================================================================
--   ⚠️  THESE ARE NOT REAL GOVERNMENT RATES.
--
-- Plausible figures used to exercise the GOVT FIXED vs LOCAL MARKET UI. The
-- real numbers are published by TCB and the DNCRP; replace these before showing
-- the app to anyone. The `govt_price_updated_at` timestamps below are set to
-- recent dates so the freshness indicators behave realistically.
--
-- Idempotent.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Government-fixed rates on the essential commodities
-- ----------------------------------------------------------------------------
UPDATE public.products p
   SET govt_fixed_price      = v.rate,
       govt_price_updated_at = NOW() - (v.age_days || ' days')::INTERVAL,
       is_essential          = TRUE
  FROM (VALUES
    -- Volatile fresh produce: the official rate lags well behind the market,
    -- which is the realistic case in Bangladesh and produces a SPIKE.
    ('Onion',              50.00, 9),   -- market ~৳68  -> ~+36%  SPIKE
    ('Potato',             25.00, 9),   -- market ~৳32  -> ~+27%  SPIKE
    ('Sugar',             112.00, 6),   -- market ~৳128 -> ~+14%  SPIKE

    -- Packaged staples: the rate tracks the market closely -> STABLE
    ('Miniket Rice',       74.00, 2),
    ('Nazirshail Rice',    78.00, 2),
    ('Soybean Oil 1L',    167.00, 1),
    ('Soybean Oil 5L',    820.00, 1),
    ('Masoor Dal',        130.00, 3),
    ('Farm Eggs (dozen)', 142.00, 2),

    -- Rate set above the current market -> DROP (good for the buyer)
    ('Atta',               55.00, 4),   -- market ~৳52  -> ~-5%   DROP
    ('Chola Dal',         112.00, 3)    -- market ~৳110 -> ~-2%   DROP
  ) AS v(name, rate, age_days)
 WHERE p.name = v.name;

-- Chinigura, mustard oil and rui fish are not rate-controlled — left NULL on
-- purpose so the UI shows "no official rate" rather than a made-up number.

-- ----------------------------------------------------------------------------
-- Sellers across the eight regions, so the regional price table has content
-- ----------------------------------------------------------------------------
INSERT INTO public.sellers (name, name_bn, slug, seller_type, location, city, rating, region_id)
SELECT v.name, v.name_bn, v.slug, v.stype, v.location, v.city, v.rating, r.id
FROM (VALUES
  ('Chittagong Reazuddin Bazar', 'রিয়াজউদ্দিন বাজার', 'reazuddin-bazar', 'bazar',  'Reazuddin',  'Chittagong', 3.8, 'chittagong'),
  ('Chittagong Bahaddarhat',     'বহদ্দারহাট',        'bahaddarhat',     'bazar',  'Bahaddarhat','Chittagong', 3.6, 'chittagong'),
  ('Rajshahi Shaheb Bazar',      'সাহেব বাজার',       'shaheb-bazar',    'bazar',  'Shaheb',     'Rajshahi',   3.9, 'rajshahi'),
  ('Khulna Boro Bazar',          'বড় বাজার',          'khulna-boro',     'bazar',  'Boro Bazar', 'Khulna',     3.7, 'khulna'),
  ('Sylhet Bandar Bazar',        'বন্দর বাজার',        'bandar-bazar',    'bazar',  'Bandar',     'Sylhet',     3.8, 'sylhet'),
  ('Barishal Port Road Bazar',   'পোর্ট রোড বাজার',    'port-road-bazar', 'bazar',  'Port Road',  'Barishal',   3.5, 'barishal'),
  ('Rangpur City Bazar',         'রংপুর সিটি বাজার',   'rangpur-city',    'bazar',  'City Bazar', 'Rangpur',    3.6, 'rangpur'),
  ('Mymensingh Mecha Bazar',     'মেছুয়া বাজার',       'mecha-bazar',     'bazar',  'Mechua',     'Mymensingh', 3.5, 'mymensingh')
) AS v(name, name_bn, slug, stype, location, city, rating, region)
JOIN public.regions r ON r.slug = v.region
ON CONFLICT (slug) DO NOTHING;

-- ----------------------------------------------------------------------------
-- Regional prices for onion and rice — enough to populate the regional table
-- ----------------------------------------------------------------------------
-- Regional variation is deliberate: Rajshahi and Rangpur are producing regions
-- and price lower; Chittagong and Sylhet price higher.
INSERT INTO public.prices
  (product_id, seller_id, price, unit, unit_qty, in_stock, source, collected_at)
SELECT p.id, s.id, v.price, p.unit, 1, TRUE, 'manual',
       NOW() - (v.age_hours || ' hours')::INTERVAL
FROM (VALUES
  ('Onion',        'reazuddin-bazar',  82.00,  4),
  ('Onion',        'shaheb-bazar',     58.00,  6),
  ('Onion',        'khulna-boro',      68.00,  8),
  ('Onion',        'bandar-bazar',     76.00,  5),
  ('Onion',        'port-road-bazar',  71.00, 10),
  ('Onion',        'rangpur-city',     56.00,  7),
  ('Onion',        'mecha-bazar',      63.00,  9),

  ('Miniket Rice', 'reazuddin-bazar',  84.00,  4),
  ('Miniket Rice', 'shaheb-bazar',     71.00,  6),
  ('Miniket Rice', 'khulna-boro',      76.00,  8),
  ('Miniket Rice', 'bandar-bazar',     82.00,  5),
  ('Miniket Rice', 'rangpur-city',     69.00,  7),

  ('Potato',       'shaheb-bazar',     26.00,  6),
  ('Potato',       'rangpur-city',     24.00,  7),
  ('Potato',       'reazuddin-bazar',  39.00,  4),

  ('Masoor Dal',   'reazuddin-bazar', 149.00,  5),
  ('Masoor Dal',   'shaheb-bazar',    134.00,  6),

  ('Sugar',        'reazuddin-bazar', 133.00,  5),
  ('Sugar',        'bandar-bazar',    128.00,  9)
) AS v(product, seller, price, age_hours)
JOIN public.products p ON p.name = v.product
JOIN public.sellers  s ON s.slug = v.seller
ON CONFLICT (product_id, seller_id) DO NOTHING;

-- ============================================================================
-- After this runs:
--   Home     "Daily Essentials" shows GOVT FIXED beside LOCAL AVG, with the
--            gap and a SPIKE / STABLE / DROP pill
--   Compare  onion is a clear spike (govt ৳65, local average well above)
--   Product  regional table spans all eight divisions for onion and rice
-- ============================================================================


-- ==========================================================================
-- DONE.
-- ==========================================================================
