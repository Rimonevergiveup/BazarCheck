-- ============================================================================
-- Porokh — seed data
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

BEGIN;

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

COMMIT;

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
