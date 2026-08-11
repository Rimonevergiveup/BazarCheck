"""Verify Bazardam migration 002 against a real PostgreSQL instance.

Simulates Supabase (auth schema + auth.uid()/auth.role()), applies the ORIGINAL
schema with sample data, then applies migration 002 and checks backfill,
constraints, RLS, bilingual search and the RPC functions.
"""
import os
import pathlib
import shutil
import sys

import psycopg

# Repo root, resolved relative to this file so it works anywhere.
REPO = pathlib.Path(__file__).resolve().parents[2]

# CI supplies a real PostgreSQL via DATABASE_URL. Locally we fall back to an
# embedded server from the `pgserver` package (no root required).
DATABASE_URL = os.environ.get("DATABASE_URL")

if DATABASE_URL:
    print("Connecting to PostgreSQL from DATABASE_URL ...")
    conn = psycopg.connect(DATABASE_URL, autocommit=True)
else:
    import pgserver  # noqa: PLC0415  - optional local-only dependency

    PGDATA = pathlib.Path("/tmp/bazardam_pgtest")
    if PGDATA.exists():
        shutil.rmtree(PGDATA, ignore_errors=True)
    PGDATA.mkdir(parents=True, exist_ok=True)
    print("Starting embedded PostgreSQL ...")
    db = pgserver.get_server(str(PGDATA), cleanup_mode="stop")
    conn = psycopg.connect(db.get_uri(), autocommit=True)

print("  ", conn.execute("SELECT version()").fetchone()[0][:60])

# Is the real pg_trgm extension available? Supabase and the official postgres
# image both have it; the embedded pgserver build ships without contrib.
HAS_TRGM = conn.execute(
    "SELECT COUNT(*) FROM pg_available_extensions WHERE name = 'pg_trgm'"
).fetchone()[0] > 0
print("   pg_trgm available:", HAS_TRGM)

fails, checks = [], 0


def exec_sql(sql, label):
    """Run a script. Returns True on success, records the real error on failure."""
    try:
        with conn.cursor() as cur:
            cur.execute(sql)
        return True
    except Exception as e:  # noqa: BLE001
        fails.append(f"{label}: {type(e).__name__}: {e}")
        print(f"  FAIL {label}\n        {type(e).__name__}: {str(e)[:500]}")
        return False


def scalar(sql):
    with conn.cursor() as cur:
        cur.execute(sql)
        row = cur.fetchone()
    return None if row is None else row[0]


def check(label, sql, expect):
    global checks
    checks += 1
    try:
        got = scalar(f"SELECT {sql}")
    except Exception as e:  # noqa: BLE001
        fails.append(f"{label}: query error {type(e).__name__}: {str(e)[:300]}")
        print(f"  FAIL {label}: {type(e).__name__}: {str(e)[:200]}")
        return
    if str(got) != str(expect):
        fails.append(f"{label}: expected {expect!r}, got {got!r}")
        print(f"  FAIL {label}: expected {expect!r}, got {got!r}")
    else:
        print(f"  ok   {label} = {got}")


def check_raises(label, sql):
    """Assert that a statement is rejected."""
    global checks
    checks += 1
    try:
        with conn.cursor() as cur:
            cur.execute(sql)
    except Exception:  # noqa: BLE001
        print(f"  ok   {label} rejected")
        return
    fails.append(f"{label}: was ACCEPTED but should have been rejected")
    print(f"  FAIL {label} accepted")


# --------------------------------------------------------------------------
print("\n[1] Mock Supabase auth schema")
exec_sql(
    """
    DROP SCHEMA IF EXISTS auth CASCADE;
    DROP SCHEMA IF EXISTS public CASCADE;
    CREATE SCHEMA public;
    CREATE SCHEMA auth;

    CREATE TABLE auth.users (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      email TEXT
    );
    CREATE OR REPLACE FUNCTION auth.uid() RETURNS UUID LANGUAGE sql STABLE AS $fn$
      SELECT NULLIF(current_setting('test.uid', true), '')::UUID;
    $fn$;
    CREATE OR REPLACE FUNCTION auth.role() RETURNS TEXT LANGUAGE sql STABLE AS $fn$
      SELECT COALESCE(NULLIF(current_setting('test.role', true), ''), 'anon');
    $fn$;
    DO $do$ BEGIN CREATE ROLE anon NOLOGIN;
      EXCEPTION WHEN duplicate_object THEN NULL; END $do$;
    DO $do$ BEGIN CREATE ROLE authenticated NOLOGIN;
      EXCEPTION WHEN duplicate_object THEN NULL; END $do$;
    GRANT USAGE ON SCHEMA public TO anon, authenticated;
    """,
    "auth schema",
)

print("\n[2] Original supabase_schema.sql (simulating existing data)")
if not exec_sql((REPO / "supabase_schema.sql").read_text(encoding="utf-8"), "original schema"):
    sys.exit(1)
check("original products seeded", "COUNT(*) FROM products", 4)
check("original divisions seeded", "COUNT(*) FROM divisions", 3)
exec_sql(
    "INSERT INTO auth.users (id, email) VALUES "
    "('11111111-1111-1111-1111-111111111111', 'owner@bazardam.test')",
    "seed user",
)

print("\n[3] Migration 002")
mig_raw = (REPO / "database/migrations/002_price_comparison.sql").read_text(encoding="utf-8")

# ---------------------------------------------------------------------------
# SANDBOX SHIM. This pgserver build has no contrib, so pg_trgm is unavailable.
# Supabase DOES have pg_trgm, so the real migration is left untouched; here we
# substitute two things so the rest can be tested for real:
#   1. CREATE EXTENSION pg_trgm  -> a pure-SQL similarity() stand-in
#   2. GIN (col gin_trgm_ops)    -> BTREE (col)   [index TYPE only; ILIKE
#      semantics, which is what search correctness depends on, are identical]
# Everything else - tables, constraints, backfill, triggers, RLS, all four RPC
# functions - runs exactly as written.
# ---------------------------------------------------------------------------
TRGM_SHIM = """
CREATE OR REPLACE FUNCTION public.similarity(a TEXT, b TEXT)
RETURNS REAL LANGUAGE plpgsql IMMUTABLE AS $shim$
DECLARE la INT; lb INT;
BEGIN
  IF a IS NULL OR b IS NULL OR a = '' OR b = '' THEN RETURN 0; END IF;
  a := lower(a); b := lower(b);
  IF a = b THEN RETURN 1; END IF;
  IF position(b in a) > 0 THEN
    la := length(a); lb := length(b);
    RETURN GREATEST(0.1, lb::REAL / NULLIF(la, 0)::REAL);
  END IF;
  RETURN 0;
END;
$shim$;
"""
if HAS_TRGM:
    mig = mig_raw  # run the migration exactly as it ships
    print("   running migration UNMODIFIED (pg_trgm present)")
else:
    mig = mig_raw.replace("CREATE EXTENSION IF NOT EXISTS pg_trgm;", TRGM_SHIM)
    mig = mig.replace("USING GIN (search_text gin_trgm_ops)", "USING BTREE (search_text)")
    mig = mig.replace("USING GIN (name gin_trgm_ops)", "USING BTREE (name)")
    assert "gin_trgm_ops" not in mig, "shim missed a trgm index"
    print("   running migration WITH TRGM SHIM (no contrib in this build)")

if not exec_sql(mig, "migration 002"):
    print("\n*** MIGRATION FAILED — see error above ***")
    sys.exit(1)
print("  ok   migration applied cleanly")

print("\n[4] Structure")
for t in ["profiles", "sellers", "prices", "price_history", "favorites"]:
    check(f"table {t}", f"COUNT(*) FROM information_schema.tables "
                        f"WHERE table_schema='public' AND table_name='{t}'", 1)
for c in ["name_bn", "brand", "unit", "search_text", "is_active"]:
    check(f"products.{c}", f"COUNT(*) FROM information_schema.columns "
                           f"WHERE table_name='products' AND column_name='{c}'", 1)
# pg_trgm shimmed in sandbox - see note above
check("search index exists", "COUNT(*) FROM pg_indexes WHERE indexname='idx_products_search_trgm'", 1)
check("unique(product,seller)", "COUNT(*) FROM pg_constraint "
                                "WHERE conname='prices_unique_product_seller'", 1)

print("\n[5] Backfill (must not lose data)")
check("placeholder seller", "COUNT(*) FROM sellers WHERE slug='bazardam-listing'", 1)
check("4 prices backfilled", "COUNT(*) FROM prices", 4)
check("products.price NOT dropped", "COUNT(*) FROM information_schema.columns "
                                    "WHERE table_name='products' AND column_name='price'", 1)
check("value preserved", "p.price FROM prices p JOIN products pr ON pr.id=p.product_id "
                         "WHERE pr.name='iPhone 15 Pro'", "999.99")
check("currency BDT", "COUNT(*) FROM prices WHERE currency='BDT'", 4)
check("history auto-logged", "COUNT(*) FROM price_history", 4)
check("profile backfilled", "COUNT(*) FROM profiles", 1)

print("\n[6] Idempotency (re-run the whole migration)")
if exec_sql(mig, "rerun"):
    print("  ok   re-ran without error")
check("no duplicate prices", "COUNT(*) FROM prices", 4)
check("no duplicate sellers", "COUNT(*) FROM sellers", 1)
check("no duplicate profiles", "COUNT(*) FROM profiles", 1)

print("\n[7] Constraints")
sid = scalar("SELECT id FROM sellers WHERE slug='bazardam-listing'")
pid = scalar("SELECT id FROM products WHERE name='iPhone 15 Pro'")
check_raises("negative price",
             f"INSERT INTO prices (product_id,seller_id,price) VALUES ('{pid}','{sid}',-5)")
check_raises("duplicate (product,seller)",
             f"INSERT INTO prices (product_id,seller_id,price) VALUES ('{pid}','{sid}',100)")
check_raises("bad seller_type",
             "INSERT INTO sellers (name,slug,seller_type) VALUES ('X','x','nonsense')")
check_raises("zero unit_qty",
             f"INSERT INTO prices (product_id,seller_id,price,unit_qty) "
             f"VALUES ('{pid}','{sid}',10,0)")

print("\n[8] Multi-seller comparison")
exec_sql(
    """
    INSERT INTO sellers (name, name_bn, slug, seller_type, city) VALUES
      ('Shwapno',    'স্বপ্ন',       'shwapno',     'retail', 'Dhaka'),
      ('Meena Bazar','মীনা বাজার',  'meena-bazar', 'retail', 'Dhaka'),
      ('Chaldal',    'চালডাল',      'chaldal',     'online', 'Dhaka')
    ON CONFLICT (slug) DO NOTHING;
    INSERT INTO products (name, name_bn, brand, unit, category_id, description)
    SELECT 'Miniket Rice', 'মিনিকেট চাল', 'ACI', 'kg',
           (SELECT id FROM categories WHERE name='Smartphones'), 'Premium rice'
    WHERE NOT EXISTS (SELECT 1 FROM products WHERE name='Miniket Rice');
    """,
    "seed sellers",
)
rice = scalar("SELECT id FROM products WHERE name='Miniket Rice'")
exec_sql(
    f"""
    INSERT INTO prices (product_id, seller_id, price, unit, source) VALUES
      ('{rice}', (SELECT id FROM sellers WHERE slug='shwapno'),     78.00, 'kg', 'manual'),
      ('{rice}', (SELECT id FROM sellers WHERE slug='meena-bazar'), 85.50, 'kg', 'manual'),
      ('{rice}', (SELECT id FROM sellers WHERE slug='chaldal'),     72.00, 'kg', 'manual')
    ON CONFLICT (product_id, seller_id) DO NOTHING;
    """,
    "seed prices",
)
check("3 offers", f"COUNT(*) FROM get_product_offers('{rice}')", 3)
check("cheapest first", f"price FROM get_product_offers('{rice}') LIMIT 1", "72.00")
check("cheapest flagged", f"seller_name FROM get_product_offers('{rice}') WHERE is_cheapest", "Chaldal")
check("pct above min", f"pct_above_min FROM get_product_offers('{rice}') "
                       f"WHERE seller_name='Meena Bazar'", "18.8")

print("\n[9] Bilingual search")
check("english 'rice'",    "COUNT(*) FROM search_products('rice')", 1)
check("case-insensitive",  "COUNT(*) FROM search_products('RICE')", 1)
check("bangla 'চাল'",      "COUNT(*) FROM search_products('চাল')", 1)
check("bangla 'মিনিকেট'",  "COUNT(*) FROM search_products('মিনিকেট')", 1)
check("brand 'ACI'",       "COUNT(*) FROM search_products('ACI')", 1)
check("partial 'mini'",    "COUNT(*) FROM search_products('mini')", 1)
check("nonsense -> 0",     "COUNT(*) FROM search_products('zzzqqq')", 0)
check("empty -> browse",   "COUNT(*) FROM search_products('')", 5)
check("min_price surfaced","min_price FROM search_products('rice')", "72.00")
check("seller_count",      "seller_count FROM search_products('rice')", 3)
check("total_count",       "total_count FROM search_products('') LIMIT 1", 5)

print("\n[10] Filters and sorting")
check("price_asc",  "name FROM search_products('',NULL,NULL,NULL,NULL,'price_asc') LIMIT 1", "Cotton T-Shirt")
check("price_desc", "name FROM search_products('',NULL,NULL,NULL,NULL,'price_desc') LIMIT 1", "MacBook Pro")
check("max_price<=100", "COUNT(*) FROM search_products('',NULL,NULL,NULL,100)", 3)
check("min_price>=500", "COUNT(*) FROM search_products('',NULL,NULL,500,NULL)", 2)
check("limit 2",  "COUNT(*) FROM search_products('',NULL,NULL,NULL,NULL,'name',2,0)", 2)
check("offset 4", "COUNT(*) FROM search_products('',NULL,NULL,NULL,NULL,'name',2,4)", 1)

print("\n[11] Best deals + price history")
check("deals found", "COUNT(*) FROM get_best_deals(10)", 1)
check("savings",     "savings FROM get_best_deals(10)", "13.50")
check("history rows",f"COUNT(*) FROM get_price_history('{rice}', 90)", 1)
exec_sql(f"UPDATE prices SET price=69.00 WHERE product_id='{rice}' "
         f"AND seller_id=(SELECT id FROM sellers WHERE slug='chaldal')", "price change")
check("history grew", f"COUNT(*) FROM price_history WHERE product_id='{rice}'", 4)
check("new cheapest", f"price FROM get_product_offers('{rice}') LIMIT 1", "69.00")
exec_sql(f"UPDATE prices SET in_stock=false WHERE product_id='{rice}' "
         f"AND seller_id=(SELECT id FROM sellers WHERE slug='chaldal')", "out of stock")
check("out-of-stock excluded from min", "min_price FROM search_products('rice')", "78.00")
check("out-of-stock still listed", f"COUNT(*) FROM get_product_offers('{rice}')", 3)

print("\n[12] RLS / admin role")
uid = "11111111-1111-1111-1111-111111111111"
exec_sql(f"SET test.uid = '{uid}'; SET test.role = 'authenticated'", "ctx")
check("non-admin", "is_admin()", "False")
exec_sql("RESET test.uid", "clear uid = service_role/dashboard context")
exec_sql(f"UPDATE profiles SET role='admin' WHERE id='{uid}'", "bootstrap first admin")
exec_sql(f"SET test.uid = '{uid}'", "restore uid")
check("now admin", "is_admin()", "True")
check("rls enabled on prices",
      "relrowsecurity FROM pg_class WHERE relname='prices'", "True")
check("admin write policy exists",
      "COUNT(*) FROM pg_policies WHERE tablename='prices' AND policyname='prices_admin_write'", 1)
check("old insecure policy gone",
      "COUNT(*) FROM pg_policies WHERE tablename='products' "
      "AND policyname='Enable insert for authenticated users only'", 0)
check("public read policy on products",
      "COUNT(*) FROM pg_policies WHERE tablename='products' AND policyname='products_public_read'", 1)

print("\n" + "=" * 64)
if fails:
    print(f"RESULT: {len(fails)} FAILURE(S) / {checks} checks\n")
    for f in fails:
        print("  x", f)
    sys.exit(1)
print(f"RESULT: ALL {checks} CHECKS PASSED")
print("=" * 64)
