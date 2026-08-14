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
