"""Verify database/COMPLETE_SETUP.sql — the single-paste path."""
import pathlib, shutil, sys, psycopg, pgserver

REPO = pathlib.Path(__file__).resolve().parents[2]
PGDATA = pathlib.Path("/tmp/bazarcheck_complete")
if PGDATA.exists(): shutil.rmtree(PGDATA, ignore_errors=True)
PGDATA.mkdir(parents=True, exist_ok=True)
db = pgserver.get_server(str(PGDATA), cleanup_mode="stop")
conn = psycopg.connect(db.get_uri(), autocommit=True)
HAS_TRGM = conn.execute("SELECT COUNT(*) FROM pg_available_extensions WHERE name='pg_trgm'").fetchone()[0] > 0
fails, checks = [], 0

def run(sql, label):
    try:
        with conn.cursor() as c: c.execute(sql)
        return True
    except Exception as e:
        fails.append(f"{label}: {e}"); print(f"  FAIL {label}\n     {str(e)[:400]}"); return False

def check(label, sql, expect):
    global checks; checks += 1
    try:
        with conn.cursor() as c:
            c.execute(f"SELECT {sql}"); got = c.fetchone()[0]
    except Exception as e:
        fails.append(f"{label}: {e}"); print(f"  FAIL {label}: {str(e)[:150]}"); return
    if str(got) != str(expect):
        fails.append(f"{label}: expected {expect}, got {got}"); print(f"  FAIL {label}: expected {expect!r}, got {got!r}")
    else: print(f"  ok   {label} = {got}")

SHIM = """CREATE OR REPLACE FUNCTION public.similarity(a TEXT,b TEXT) RETURNS REAL
LANGUAGE plpgsql IMMUTABLE AS $s$ BEGIN
 IF a IS NULL OR b IS NULL OR a='' OR b='' THEN RETURN 0; END IF;
 a:=lower(a); b:=lower(b); IF a=b THEN RETURN 1; END IF;
 IF position(b in a)>0 THEN RETURN GREATEST(0.1,length(b)::REAL/NULLIF(length(a),0)::REAL); END IF;
 RETURN 0; END; $s$;"""

run("""DROP SCHEMA IF EXISTS auth CASCADE; DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public; CREATE SCHEMA auth;
CREATE TABLE auth.users (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), email TEXT);
CREATE OR REPLACE FUNCTION auth.uid() RETURNS UUID LANGUAGE sql STABLE AS $f$
 SELECT NULLIF(current_setting('test.uid',true),'')::UUID; $f$;
CREATE OR REPLACE FUNCTION auth.role() RETURNS TEXT LANGUAGE sql STABLE AS $f$
 SELECT COALESCE(NULLIF(current_setting('test.role',true),''),'anon'); $f$;
DO $d$ BEGIN CREATE ROLE anon NOLOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END $d$;
DO $d$ BEGIN CREATE ROLE authenticated NOLOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END $d$;
GRANT USAGE ON SCHEMA public TO anon, authenticated;""", "auth stub")

sql = (REPO / "database/COMPLETE_SETUP.sql").read_text(encoding="utf-8")
if not HAS_TRGM:
    sql = sql.replace("CREATE EXTENSION IF NOT EXISTS pg_trgm;", SHIM)
    sql = sql.replace("USING GIN (search_text gin_trgm_ops)", "USING BTREE (search_text)")
    sql = sql.replace("USING GIN (name gin_trgm_ops)", "USING BTREE (name)")

print("\n[1] Paste #1 (simulating the SQL Editor)")
if not run(sql, "COMPLETE_SETUP"): sys.exit(1)
print("  ok   ran clean")

print("\n[2] Everything landed")
for t in ["divisions","categories","products","sellers","prices","price_history","favorites","profiles"]:
    check(f"table {t}", f"COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_name='{t}'", 1)
check("products seeded", "COUNT(*) FROM products", 14)
check("sellers seeded (7 + 8 regional)", "COUNT(*) FROM sellers", 15)
check("prices seeded (43 + 19 regional)", "COUNT(*) FROM prices", 62)

print("\n[3] All four RPCs work")
check("search bangla", "COUNT(*) FROM search_products('চাল')", 3)
check("search english", "COUNT(*) FROM search_products('rice')", 3)
check("offers", "COUNT(*) FROM get_product_offers((SELECT id FROM products WHERE name='Miniket Rice'))", 10)
check("cheapest flagged", "seller_name FROM get_product_offers((SELECT id FROM products WHERE name='Miniket Rice')) WHERE is_cheapest", "Rangpur City Bazar")
check("best deals", "COUNT(*) FROM get_best_deals(10)", 10)
check("history", "COUNT(*) >= 30 FROM get_price_history((SELECT id FROM products WHERE name='Onion'),90)", True)

print("\n[4] Paste #2 — running it twice must be harmless")
if run(sql, "rerun"): print("  ok   ran clean again")
check("products not duplicated", "COUNT(*) FROM products", 14)
check("sellers not duplicated", "COUNT(*) FROM sellers", 15)
check("prices not duplicated", "COUNT(*) FROM prices", 62)
check("search still correct", "COUNT(*) FROM search_products('চাল')", 3)


print("\n[6] Migration 003 — favourites RPC")
check("get_favorite_products exists",
      "COUNT(*) FROM pg_proc WHERE proname='get_favorite_products'", 1)
# auth.uid() is NULL here (no signed-in user), so it must return nothing rather
# than leaking every favourite in the table.
check("returns nothing without a signed-in user",
      "COUNT(*) FROM get_favorite_products(100,0)", 0)

print("\n[7] Product images are seeded")
check("all products have an image", "COUNT(*) FROM products WHERE image_url IS NULL", 0)
check("images are https", "COUNT(*) FROM products WHERE image_url NOT LIKE 'https://%'", 0)

print("\n[8] Pagination contract the app relies on")
check("page 1 of 5", "COUNT(*) FROM search_products('',NULL,NULL,NULL,NULL,'name',5,0)", 5)
check("page 2 of 5", "COUNT(*) FROM search_products('',NULL,NULL,NULL,NULL,'name',5,5)", 5)
check("page 3 partial", "COUNT(*) FROM search_products('',NULL,NULL,NULL,NULL,'name',5,10)", 4)
check("past the end is empty", "COUNT(*) FROM search_products('',NULL,NULL,NULL,NULL,'name',5,20)", 0)
check("total_count is the FULL count, not the page",
      "total_count FROM search_products('',NULL,NULL,NULL,NULL,'name',5,0) LIMIT 1", 14)
check("pages do not overlap",
      "COUNT(DISTINCT id) FROM ("
      "SELECT id FROM search_products('',NULL,NULL,NULL,NULL,'name',5,0) UNION ALL "
      "SELECT id FROM search_products('',NULL,NULL,NULL,NULL,'name',5,5) UNION ALL "
      "SELECT id FROM search_products('',NULL,NULL,NULL,NULL,'name',5,10)) q", 14)

print("\n[9] Category filter (powers the new filter chip)")
check("filter by Rice category",
      "COUNT(*) FROM search_products('', (SELECT id FROM categories WHERE name='Rice'))", 3)
check("filter by Vegetables",
      "COUNT(*) FROM search_products('', (SELECT id FROM categories WHERE name='Vegetables'))", 2)


print("\n[11] Migration 004 — govt rates + regions")
check("regions table", "COUNT(*) FROM regions", 8)
check("govt_fixed_price column", "COUNT(*) FROM information_schema.columns "
      "WHERE table_name='products' AND column_name='govt_fixed_price'", 1)
check("essentials flagged", "COUNT(*) FROM products WHERE is_essential", 11)
check("rates only on essentials",
      "COUNT(*) FROM products WHERE govt_fixed_price IS NOT NULL", 11)
check("non-controlled left NULL",
      "govt_fixed_price IS NULL FROM products WHERE name='Rui Fish'", True)
check("sellers assigned to regions",
      "COUNT(*) FROM sellers WHERE region_id IS NULL", 0)

print("\n[12] get_essentials — home + compare")
check("returns essentials", "COUNT(*) FROM get_essentials(30)", 11)
check("onion is a spike", "status FROM get_essentials(30) WHERE name='Onion'", "spike")
check("spike state present",  "COUNT(*) > 0 FROM get_essentials(30) WHERE status='spike'",  True)
check("drop state present",   "COUNT(*) > 0 FROM get_essentials(30) WHERE status='drop'",   True)
check("stable state present", "COUNT(*) > 0 FROM get_essentials(30) WHERE status='stable'", True)
check("onion govt rate", "govt_fixed_price FROM get_essentials(30) WHERE name='Onion'", "50.00")
check("gap is computed", "price_gap > 0 FROM get_essentials(30) WHERE name='Onion'", True)
check("gap percent computed",
      "gap_percent IS NOT NULL FROM get_essentials(30) WHERE name='Onion'", True)

print("\n[13] get_regional_prices — the division table")
check("onion across regions", "COUNT(*) FROM get_regional_prices("
      "(SELECT id FROM products WHERE name='Onion'))", 8)
check("cheapest region first (Rangpur)", "region_name FROM get_regional_prices("
      "(SELECT id FROM products WHERE name='Onion')) LIMIT 1", "Rangpur")
check("rice spans regions", "(SELECT COUNT(*) FROM get_regional_prices("
      "(SELECT id FROM products WHERE name='Miniket Rice'))) >= 5", True)

print("\n[14] Honesty guards")
# A product with no official rate must never be given one.
check("no invented govt rate",
      "COUNT(*) FROM get_essentials(30) WHERE govt_fixed_price IS NULL AND status <> 'unknown'", 0)

print("\n[15] Security")
check("public read", "COUNT(*) FROM pg_policies WHERE tablename='products' AND policyname='products_public_read'", 1)
check("admin-only writes", "COUNT(*) FROM pg_policies WHERE tablename='prices' AND policyname='prices_admin_write'", 1)
check("no authenticated-write hole", "COUNT(*) FROM pg_policies WHERE qual LIKE '%auth.role() = ''authenticated''%'", 0)

print("\n" + "="*60)
if fails:
    print(f"{len(fails)} FAILURE(S) / {checks}"); [print("  x",f) for f in fails]; sys.exit(1)
print(f"ALL {checks} CHECKS PASSED"); print("="*60)
