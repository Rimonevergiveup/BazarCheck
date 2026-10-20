DO $$
BEGIN
CREATE EXTENSION IF NOT EXISTS pgcrypto;
EXCEPTION WHEN OTHERS THEN
RAISE NOTICE 'pgcrypto unavailable - using core gen_random_uuid() (PG13+)';
END $$;
CREATE TABLE IF NOT EXISTS public.divisions (
id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
name        TEXT NOT NULL,
description TEXT,
created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.divisions ENABLE ROW LEVEL SECURITY;
CREATE TABLE IF NOT EXISTS public.categories (
id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
name        TEXT NOT NULL,
division_id UUID REFERENCES public.divisions(id) ON DELETE CASCADE,
description TEXT,
created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
CREATE TABLE IF NOT EXISTS public.products (
id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
name        TEXT NOT NULL,
category_id UUID REFERENCES public.categories(id) ON DELETE CASCADE,
description TEXT,
price       NUMERIC(10,2),
image_url   TEXT,
created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
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
CREATE INDEX IF NOT EXISTS idx_categories_division_id ON public.categories(division_id);
CREATE INDEX IF NOT EXISTS idx_products_category_id   ON public.products(category_id);
CREATE INDEX IF NOT EXISTS idx_ai_results_user_id     ON public.ai_results(user_id);
CREATE INDEX IF NOT EXISTS idx_ai_results_product_id  ON public.ai_results(product_id);
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
CREATE EXTENSION IF NOT EXISTS pg_trgm;
DO $$
BEGIN
CREATE EXTENSION IF NOT EXISTS pgcrypto;
EXCEPTION WHEN OTHERS THEN
RAISE NOTICE 'pgcrypto unavailable - using core gen_random_uuid() (PG13+)';
END $$;
CREATE TABLE IF NOT EXISTS public.profiles (
id         UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
email      TEXT,
full_name  TEXT,
role       TEXT NOT NULL DEFAULT 'user' CHECK (role IN ('user', 'admin')),
created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
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
INSERT INTO public.profiles (id, email)
SELECT id, email FROM auth.users
ON CONFLICT (id) DO NOTHING;
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
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS name_bn  TEXT;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS brand    TEXT;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS unit     TEXT;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE;
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
CREATE TABLE IF NOT EXISTS public.prices (
id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
product_id   UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
seller_id    UUID NOT NULL REFERENCES public.sellers(id)  ON DELETE CASCADE,
price        NUMERIC(12,2) NOT NULL CHECK (price >= 0),
currency     CHAR(3) NOT NULL DEFAULT 'BDT',
unit         TEXT,
unit_qty     NUMERIC(10,3) NOT NULL DEFAULT 1 CHECK (unit_qty > 0),
in_stock     BOOLEAN NOT NULL DEFAULT TRUE,
product_url  TEXT,
source       TEXT NOT NULL DEFAULT 'manual'
CHECK (source IN ('manual', 'scrape', 'api', 'import', 'user')),
collected_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
CONSTRAINT prices_unique_product_seller UNIQUE (product_id, seller_id)
);
ALTER TABLE public.prices ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_prices_product    ON public.prices(product_id);
CREATE INDEX IF NOT EXISTS idx_prices_seller     ON public.prices(seller_id);
CREATE INDEX IF NOT EXISTS idx_prices_collected  ON public.prices(collected_at DESC);
CREATE INDEX IF NOT EXISTS idx_prices_product_cheapest
ON public.prices(product_id, price) WHERE in_stock;
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
CREATE TABLE IF NOT EXISTS public.favorites (
id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
user_id    UUID NOT NULL REFERENCES auth.users(id)     ON DELETE CASCADE,
product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
CONSTRAINT favorites_unique UNIQUE (user_id, product_id)
);
ALTER TABLE public.favorites ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_favorites_user ON public.favorites(user_id);
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
DROP POLICY IF EXISTS "profiles_self_read"   ON public.profiles;
DROP POLICY IF EXISTS "profiles_self_update" ON public.profiles;
CREATE POLICY "profiles_self_read" ON public.profiles
FOR SELECT TO authenticated USING (auth.uid() = id);
