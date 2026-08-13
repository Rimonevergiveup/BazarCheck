"""Verify database/COMPLETE_SETUP.sql — the single-paste path."""
import pathlib, shutil, sys, psycopg, pgserver

REPO = pathlib.Path(__file__).resolve().parents[2]
PGDATA = pathlib.Path("/tmp/porokh_complete")
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
check("sellers seeded", "COUNT(*) FROM sellers", 7)
check("prices seeded", "COUNT(*) FROM prices", 43)

print("\n[3] All four RPCs work")
check("search bangla", "COUNT(*) FROM search_products('চাল')", 3)
check("search english", "COUNT(*) FROM search_products('rice')", 3)
check("offers", "COUNT(*) FROM get_product_offers((SELECT id FROM products WHERE name='Miniket Rice'))", 5)
check("cheapest flagged", "seller_name FROM get_product_offers((SELECT id FROM products WHERE name='Miniket Rice')) WHERE is_cheapest", "Karwan Bazar")
check("best deals", "COUNT(*) FROM get_best_deals(10)", 10)
check("history", "COUNT(*) >= 30 FROM get_price_history((SELECT id FROM products WHERE name='Onion'),90)", True)

print("\n[4] Paste #2 — running it twice must be harmless")
if run(sql, "rerun"): print("  ok   ran clean again")
check("products not duplicated", "COUNT(*) FROM products", 14)
check("sellers not duplicated", "COUNT(*) FROM sellers", 7)
check("prices not duplicated", "COUNT(*) FROM prices", 43)
check("search still correct", "COUNT(*) FROM search_products('চাল')", 3)

print("\n[5] Security")
check("public read", "COUNT(*) FROM pg_policies WHERE tablename='products' AND policyname='products_public_read'", 1)
check("admin-only writes", "COUNT(*) FROM pg_policies WHERE tablename='prices' AND policyname='prices_admin_write'", 1)
check("no authenticated-write hole", "COUNT(*) FROM pg_policies WHERE qual LIKE '%auth.role() = ''authenticated''%'", 0)

print("\n" + "="*60)
if fails:
    print(f"{len(fails)} FAILURE(S) / {checks}"); [print("  x",f) for f in fails]; sys.exit(1)
print(f"ALL {checks} CHECKS PASSED"); print("="*60)
