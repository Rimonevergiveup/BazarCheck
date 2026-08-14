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
