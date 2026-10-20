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
ALTER TABLE public.sellers
ADD COLUMN IF NOT EXISTS region_id UUID REFERENCES public.regions(id) ON DELETE SET NULL;
ALTER TABLE public.sellers ADD COLUMN IF NOT EXISTS latitude  NUMERIC(9,6);
ALTER TABLE public.sellers ADD COLUMN IF NOT EXISTS longitude NUMERIC(9,6);
CREATE INDEX IF NOT EXISTS idx_sellers_region ON public.sellers(region_id);
UPDATE public.sellers
SET region_id = (SELECT id FROM public.regions WHERE slug = 'dhaka')
WHERE region_id IS NULL;
DROP POLICY IF EXISTS "regions_public_read" ON public.regions;
DROP POLICY IF EXISTS "regions_admin_write" ON public.regions;
CREATE POLICY "regions_public_read" ON public.regions FOR SELECT USING (true);
CREATE POLICY "regions_admin_write" ON public.regions FOR ALL TO authenticated
USING (public.is_admin()) WITH CHECK (public.is_admin());
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
status            TEXT,
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
INSERT INTO public.divisions (name, description)
SELECT v.name, v.description
FROM (VALUES
('Food & Grocery', 'Rice, oil, lentils and everyday staples'),
('Fresh Market',   'Vegetables, fish and dairy'),
('Electronics',    'Phones and gadgets')
) AS v(name, description)
WHERE NOT EXISTS (SELECT 1 FROM public.divisions d WHERE d.name = v.name);
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
INSERT INTO public.prices
(product_id, seller_id, price, unit, unit_qty, in_stock, source, collected_at, product_url)
SELECT p.id, s.id, v.price, p.unit, v.unit_qty, v.in_stock, 'manual',
NOW() - (v.age_hours || ' hours')::INTERVAL, v.url
FROM (VALUES
('Miniket Rice',      'chaldal',      72.00, 1,   TRUE,  2,    'https://chaldal.com'),
('Miniket Rice',      'shwapno',      78.00, 1,   TRUE,  5,    NULL),
('Miniket Rice',      'agora',        80.00, 1,   TRUE,  30,   NULL),
('Miniket Rice',      'meena-bazar',  85.50, 1,   TRUE,  72,   NULL),
('Miniket Rice',      'karwan-bazar', 70.00, 1,   TRUE,  288,  NULL),
('Nazirshail Rice',   'shwapno',      82.00, 1,   TRUE,  6,    NULL),
('Nazirshail Rice',   'chaldal',      79.50, 1,   TRUE,  3,    'https://chaldal.com'),
('Nazirshail Rice',   'unimart',      88.00, 1,   TRUE,  48,   NULL),
('Chinigura Rice',    'meena-bazar', 135.00, 1,   TRUE,  10,   NULL),
('Chinigura Rice',    'agora',       142.00, 1,   TRUE,  1080, NULL),
('Soybean Oil 1L',    'chaldal',     172.00, 1,   TRUE,  1,    'https://chaldal.com'),
('Soybean Oil 1L',    'shwapno',     178.00, 1,   TRUE,  8,    NULL),
('Soybean Oil 1L',    'meena-bazar', 175.00, 1,   TRUE,  60,   NULL),
('Soybean Oil 1L',    'daraz',       169.00, 1,   FALSE, 4,    'https://daraz.com.bd'),
('Soybean Oil 5L',    'chaldal',     845.00, 5,   TRUE,  2,    'https://chaldal.com'),
('Soybean Oil 5L',    'shwapno',     880.00, 5,   TRUE,  26,   NULL),
('Soybean Oil 5L',    'unimart',     865.00, 5,   TRUE,  50,   NULL),
('Mustard Oil 1L',    'shwapno',     320.00, 1,   TRUE,  30,   NULL),
('Mustard Oil 1L',    'agora',       335.00, 1,   TRUE,  288,  NULL),
('Masoor Dal',        'karwan-bazar',128.00, 1,   TRUE,  288,  NULL),
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
('Onion',             'karwan-bazar', 58.00, 1,   TRUE,  288,  NULL),
('Onion',             'chaldal',      72.00, 1,   TRUE,  1,    'https://chaldal.com'),
('Onion',             'shwapno',      75.00, 1,   TRUE,  6,    NULL),
('Potato',            'karwan-bazar', 28.00, 1,   TRUE,  288,  NULL),
('Potato',            'chaldal',      35.00, 1,   TRUE,  1,    'https://chaldal.com'),
('Potato',            'shwapno',      38.00, 1,   TRUE,  6,    NULL),
('Farm Eggs (dozen)', 'chaldal',     142.00, 1,   TRUE,  2,    'https://chaldal.com'),
('Farm Eggs (dozen)', 'shwapno',     148.00, 1,   TRUE,  7,    NULL),
('Farm Eggs (dozen)', 'meena-bazar', 155.00, 1,   TRUE,  40,   NULL),
('Rui Fish',          'karwan-bazar',320.00, 1,   TRUE,  288,  NULL),
('Rui Fish',          'chaldal',     380.00, 1,   TRUE,  3,    'https://chaldal.com'),
('Rui Fish',          'agora',       395.00, 1,   TRUE,  28,   NULL)
) AS v(product, seller, price, unit_qty, in_stock, age_hours, url)
JOIN public.products p ON p.name  = v.product
JOIN public.sellers  s ON s.slug  = v.seller
ON CONFLICT (product_id, seller_id) DO NOTHING;
INSERT INTO public.price_history (product_id, seller_id, price, currency, recorded_at)
SELECT
p.id,
s.id,
CASE p.name
WHEN 'Miniket Rice' THEN 88.00 - (d * 0.55)
WHEN 'Onion'        THEN 48.00 + (d * 0.85)
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
UPDATE public.products p
SET govt_fixed_price      = v.rate,
govt_price_updated_at = NOW() - (v.age_days || ' days')::INTERVAL,
is_essential          = TRUE
FROM (VALUES
('Onion',              50.00, 9),
('Potato',             25.00, 9),
('Sugar',             112.00, 6),
('Miniket Rice',       74.00, 2),
('Nazirshail Rice',    78.00, 2),
('Soybean Oil 1L',    167.00, 1),
('Soybean Oil 5L',    820.00, 1),
('Masoor Dal',        130.00, 3),
('Farm Eggs (dozen)', 142.00, 2),
('Atta',               55.00, 4),
('Chola Dal',         112.00, 3)
) AS v(name, rate, age_days)
WHERE p.name = v.name;
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