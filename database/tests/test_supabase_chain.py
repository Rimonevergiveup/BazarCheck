"""Verify the exact sequence `supabase db push` will run on a FRESH project:

    supabase/migrations/20260814000001_initial_schema.sql
    supabase/migrations/20260814000002_price_comparison.sql
    supabase/seed.sql

then assert the app's four RPC functions return what the UI expects.
"""
import pathlib
import shutil
import sys

import psycopg

REPO = pathlib.Path(__file__).resolve().parents[2]
PGDATA = pathlib.Path("/tmp/porokh_chain")
if PGDATA.exists():
    shutil.rmtree(PGDATA, ignore_errors=True)
PGDATA.mkdir(parents=True, exist_ok=True)

import pgserver

print("Starting PostgreSQL ...")
db = pgserver.get_server(str(PGDATA), cleanup_mode="stop")
conn = psycopg.connect(db.get_uri(), autocommit=True)

HAS_TRGM = conn.execute(
    "SELECT COUNT(*) FROM pg_available_extensions WHERE name='pg_trgm'"
).fetchone()[0] > 0

fails, checks = [], 0


def run(sql, label):
    try:
        with conn.cursor() as cur:
            cur.execute(sql)
        return True
    except Exception as e:  # noqa: BLE001
        fails.append(f"{label}: {type(e).__name__}: {e}")
        print(f"  FAIL {label}\n       {type(e).__name__}: {str(e)[:400]}")
        return False


def check(label, sql, expect):
    global checks
    checks += 1
    try:
        with conn.cursor() as cur:
            cur.execute(f"SELECT {sql}")
            row = cur.fetchone()
        got = None if row is None else row[0]
    except Exception as e:  # noqa: BLE001
        fails.append(f"{label}: {type(e).__name__}: {str(e)[:250]}")
        print(f"  FAIL {label}: {type(e).__name__}: {str(e)[:180]}")
        return
    if str(got) != str(expect):
        fails.append(f"{label}: expected {expect!r}, got {got!r}")
        print(f"  FAIL {label}: expected {expect!r}, got {got!r}")
    else:
        print(f"  ok   {label} = {got}")


TRGM_SHIM = """
CREATE OR REPLACE FUNCTION public.similarity(a TEXT, b TEXT)
RETURNS REAL LANGUAGE plpgsql IMMUTABLE AS $shim$
BEGIN
  IF a IS NULL OR b IS NULL OR a='' OR b='' THEN RETURN 0; END IF;
  a := lower(a); b := lower(b);
  IF a = b THEN RETURN 1; END IF;
  IF position(b in a) > 0 THEN
    RETURN GREATEST(0.1, length(b)::REAL / NULLIF(length(a),0)::REAL);
  END IF;
  RETURN 0;
END;
$shim$;
"""


def prep(sql):
    """Substitute pg_trgm only when this build lacks contrib (Supabase has it)."""
    if HAS_TRGM:
        return sql
    sql = sql.replace("CREATE EXTENSION IF NOT EXISTS pg_trgm;", TRGM_SHIM)
    sql = sql.replace("USING GIN (search_text gin_trgm_ops)", "USING BTREE (search_text)")
    sql = sql.replace("USING GIN (name gin_trgm_ops)", "USING BTREE (name)")
    return sql


# --- Fake the Supabase auth schema -----------------------------------------
print("\n[0] Supabase auth schema stub")
run("""
DROP SCHEMA IF EXISTS auth CASCADE;
DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public; CREATE SCHEMA auth;
CREATE TABLE auth.users (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), email TEXT);
CREATE OR REPLACE FUNCTION auth.uid() RETURNS UUID LANGUAGE sql STABLE AS $f$
  SELECT NULLIF(current_setting('test.uid', true), '')::UUID; $f$;
CREATE OR REPLACE FUNCTION auth.role() RETURNS TEXT LANGUAGE sql STABLE AS $f$
  SELECT COALESCE(NULLIF(current_setting('test.role', true), ''), 'anon'); $f$;
DO $d$ BEGIN CREATE ROLE anon NOLOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END $d$;
DO $d$ BEGIN CREATE ROLE authenticated NOLOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END $d$;
GRANT USAGE ON SCHEMA public TO anon, authenticated;
""", "auth stub")

# --- Migration 001 ----------------------------------------------------------
print("\n[1] 20260814000001_initial_schema.sql")
m1 = (REPO / "supabase/migrations/20260814000001_initial_schema.sql").read_text(encoding="utf-8")
if not run(prep(m1), "migration 001"):
    sys.exit(1)
print("  ok   applied")

# --- Migration 002 ----------------------------------------------------------
print("\n[2] 20260814000002_price_comparison.sql")
m2 = (REPO / "supabase/migrations/20260814000002_price_comparison.sql").read_text(encoding="utf-8")
if not run(prep(m2), "migration 002"):
    sys.exit(1)
print("  ok   applied")

# --- Seed -------------------------------------------------------------------
print("\n[3] seed.sql")
seed = (REPO / "supabase/seed.sql").read_text(encoding="utf-8")
if not run(seed, "seed"):
    sys.exit(1)
print("  ok   applied")

print("\n[4] Seed contents")
check("divisions", "COUNT(*) FROM divisions", 3)
check("categories", "COUNT(*) FROM categories", 8)
check("sellers (no phantom placeholder)", "COUNT(*) FROM sellers", 7)
check("products", "COUNT(*) FROM products", 14)
check("prices", "COUNT(*) FROM prices", 43)
check("synthetic history rows", "COUNT(*) FROM price_history h JOIN products p ON p.id=h.product_id JOIN sellers s ON s.id=h.seller_id WHERE p.name IN ('Miniket Rice','Onion') AND s.slug='chaldal' AND h.recorded_at < NOW() - INTERVAL '1 day'", 60)

print("\n[5] Seed is idempotent (re-run)")
run(seed, "seed rerun")
check("divisions still", "COUNT(*) FROM divisions", 3)
check("products still", "COUNT(*) FROM products", 14)
check("prices still", "COUNT(*) FROM prices", 43)
check("history not duplicated", "COUNT(*) FROM price_history h JOIN products p ON p.id=h.product_id JOIN sellers s ON s.id=h.seller_id WHERE p.name IN ('Miniket Rice','Onion') AND s.slug='chaldal' AND h.recorded_at < NOW() - INTERVAL '1 day'", 60)

print("\n[6] search_products — what the search screen calls")
check("english 'rice'", "COUNT(*) FROM search_products('rice')", 3)
check("bangla 'চাল'", "COUNT(*) FROM search_products('চাল')", 3)
check("english 'oil'", "COUNT(*) FROM search_products('oil')", 3)
check("bangla 'তেল'", "COUNT(*) FROM search_products('তেল')", 3)
check("bangla 'পেঁয়াজ'", "COUNT(*) FROM search_products('পেঁয়াজ')", 1)
check("brand 'ACI'", "COUNT(*) FROM search_products('ACI')", 1)
check("browse all", "COUNT(*) FROM search_products('')", 14)
check("miniket min price", "min_price FROM search_products('Miniket')", "70.00")
check("miniket seller count", "seller_count FROM search_products('Miniket')", 5)
check("nonsense", "COUNT(*) FROM search_products('zzzz')", 0)

print("\n[7] get_product_offers — the comparison table")
check("miniket offers", "COUNT(*) FROM get_product_offers("
      "(SELECT id FROM products WHERE name='Miniket Rice'))", 5)
check("cheapest seller", "seller_name FROM get_product_offers("
      "(SELECT id FROM products WHERE name='Miniket Rice')) WHERE is_cheapest", "Karwan Bazar")
check("dearest pct above min", "pct_above_min FROM get_product_offers("
      "(SELECT id FROM products WHERE name='Miniket Rice')) WHERE seller_name='Meena Bazar'", "22.1")
check("out-of-stock listed last", "seller_name FROM get_product_offers("
      "(SELECT id FROM products WHERE name='Soybean Oil 1L')) ORDER BY in_stock ASC LIMIT 1", "Daraz")
check("out-of-stock excluded from min",
      "min_price FROM search_products('Soybean Oil 1L')", "172.00")

print("\n[8] get_best_deals — the home screen carousel")
check("deals returned", "COUNT(*) FROM get_best_deals(10)", 10)
check("top deal has a real spread", "savings > 0 FROM get_best_deals(1)", True)

print("\n[9] get_price_history — trend data")
check("miniket history days >= 30", "COUNT(*) >= 30 FROM get_price_history("
      "(SELECT id FROM products WHERE name='Miniket Rice'), 90)", True)
check("onion history days >= 30", "COUNT(*) >= 30 FROM get_price_history("
      "(SELECT id FROM products WHERE name='Onion'), 90)", True)

print("\n[10] Freshness spread is visible in the UI")
check("fresh (<24h) present", "COUNT(*) > 0 FROM prices WHERE collected_at > NOW() - INTERVAL '24 hours'", True)
check("stale (7-30d) present", "COUNT(*) > 0 FROM prices WHERE collected_at BETWEEN "
      "NOW() - INTERVAL '30 days' AND NOW() - INTERVAL '7 days'", True)
check("outdated (>30d)", "COUNT(*) FROM prices WHERE collected_at < NOW() - INTERVAL '30 days'", 1)
check("out of stock", "COUNT(*) FROM prices WHERE NOT in_stock", 1)

print("\n[11] Security still correct on a fresh project")
check("anon can read products",
      "COUNT(*) FROM pg_policies WHERE tablename='products' AND policyname='products_public_read'", 1)
check("writes are admin-only",
      "COUNT(*) FROM pg_policies WHERE tablename='prices' AND policyname='prices_admin_write'", 1)
check("no legacy authenticated-write policy",
      "COUNT(*) FROM pg_policies WHERE qual LIKE '%auth.role() = ''authenticated''%'", 0)

print("\n" + "=" * 62)
if fails:
    print(f"RESULT: {len(fails)} FAILURE(S) / {checks} checks\n")
    for f in fails:
        print("  x", f)
    sys.exit(1)
print(f"RESULT: ALL {checks} CHECKS PASSED")
print("=" * 62)
