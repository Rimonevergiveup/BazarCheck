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
