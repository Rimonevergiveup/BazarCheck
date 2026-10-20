CREATE POLICY "profiles_self_update" ON public.profiles
FOR UPDATE TO authenticated USING (auth.uid() = id) WITH CHECK (auth.uid() = id);
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
DROP POLICY IF EXISTS "favorites_owner_all" ON public.favorites;
CREATE POLICY "favorites_owner_all" ON public.favorites
FOR ALL TO authenticated
USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "ai_results_owner_update" ON public.ai_results;
DROP POLICY IF EXISTS "ai_results_owner_delete" ON public.ai_results;
CREATE POLICY "ai_results_owner_update" ON public.ai_results
FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "ai_results_owner_delete" ON public.ai_results
FOR DELETE TO authenticated USING (auth.uid() = user_id);
DROP FUNCTION IF EXISTS public.search_products(TEXT, UUID, UUID, NUMERIC, NUMERIC, TEXT, INT, INT);
CREATE FUNCTION public.search_products(
p_query     TEXT    DEFAULT NULL,
p_category  UUID    DEFAULT NULL,
p_division  UUID    DEFAULT NULL,
p_min_price NUMERIC DEFAULT NULL,
p_max_price NUMERIC DEFAULT NULL,
p_sort      TEXT    DEFAULT 'relevance',
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
GRANT EXECUTE ON FUNCTION public.search_products(TEXT, UUID, UUID, NUMERIC, NUMERIC, TEXT, INT, INT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_product_offers(UUID)      TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_best_deals(INT)           TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_price_history(UUID, INT)  TO anon, authenticated;
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
ORDER BY m.created_at DESC
LIMIT  GREATEST(1, LEAST(p_limit, 200))
OFFSET GREATEST(0, p_offset);
$$;
GRANT EXECUTE ON FUNCTION public.get_favorite_products(INT, INT) TO authenticated;
ALTER TABLE public.products
ADD COLUMN IF NOT EXISTS govt_fixed_price NUMERIC(12,2)
CHECK (govt_fixed_price IS NULL OR govt_fixed_price >= 0);
ALTER TABLE public.products
ADD COLUMN IF NOT EXISTS govt_price_updated_at TIMESTAMPTZ;
ALTER TABLE public.products
ADD COLUMN IF NOT EXISTS is_essential BOOLEAN NOT NULL DEFAULT FALSE;
CREATE INDEX IF NOT EXISTS idx_products_essential
ON public.products(is_essential) WHERE is_essential;
CREATE TABLE IF NOT EXISTS public.regions (
id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
