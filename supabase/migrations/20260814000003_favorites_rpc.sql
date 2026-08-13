-- ============================================================================
-- Porokh — Migration 003: favourites RPC
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
