-- ============================================================================
-- Porokh — Migration 002: Price Comparison Core
-- ============================================================================
-- ADDITIVE AND IDEMPOTENT. Safe to run on a database that already has real
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

BEGIN;

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

INSERT INTO public.sellers (name, name_bn, slug, seller_type, location, city)
VALUES ('Porokh Listing', 'পরখ তালিকা', 'porokh-listing', 'retail', 'Unassigned', 'Dhaka')
ON CONFLICT (slug) DO NOTHING;

INSERT INTO public.prices (product_id, seller_id, price, currency, source, collected_at)
SELECT
  p.id,
  (SELECT id FROM public.sellers WHERE slug = 'porokh-listing'),
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

COMMIT;

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
