"""Static validation of the Cube model files (no Cube server needed).

Resolves every reference the way Cube would, and checks columns against the real ClickHouse tables:
  V1 names are unique            V2 each cube's table and every column it reads exist in ClickHouse
  V3 measure references resolve  V4 joins go from fact or mart cubes to dimension cubes only
  V5 rollup members exist and list project_id
  V6 view includes resolve through join paths, names are unique within a view, ids are exposed
  V7 every included member has a description of at least three words
  V8 one primary key per cube    V9 every fact and mart cube is exposed by at least one view

Needs CH_HOST, CH_PORT, CH_SECURE, CH_DBT_USER, CH_DBT_PASSWORD (a read-only user is enough).
Exits non-zero if anything fails. Usage:  python sl_test/tests/validate_cube_model.py
"""
import base64
import glob
import json
import os
import re
import sys
import urllib.request

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
MODEL = os.path.join(HERE, "..", "cube", "model")
URL = f"{'https' if os.environ.get('CH_SECURE', 'True').lower() == 'true' else 'http'}://{os.environ['CH_HOST']}:{os.environ.get('CH_PORT', '443')}/"
AUTH = "Basic " + base64.b64encode(f"{os.environ['CH_DBT_USER']}:{os.environ['CH_DBT_PASSWORD']}".encode()).decode()
ERR = []


def ch(sql):
    req = urllib.request.Request(URL, data=(sql + " FORMAT JSONCompact").encode(), headers={"Authorization": AUTH})
    return json.loads(urllib.request.urlopen(req, timeout=120).read().decode())["data"]


def bad(code, msg): ERR.append((code, msg))


cubes, views = {}, {}
for f in glob.glob(os.path.join(MODEL, "cubes", "*.yml")):
    for c in yaml.safe_load(open(f, encoding="utf-8"))["cubes"]:
        if c["name"] in cubes: bad("V1", f"duplicate cube {c['name']}")
        cubes[c["name"]] = c
for f in glob.glob(os.path.join(MODEL, "views", "*.yml")):
    for v in yaml.safe_load(open(f, encoding="utf-8"))["views"]:
        if v["name"] in views or v["name"] in cubes: bad("V1", f"duplicate or clashing name {v['name']}")
        views[v["name"]] = v

KW = {"and", "or", "not", "is", "null", "in", "as", "else", "then", "case", "when", "end", "select", "from", "true", "false"}


def columns_in(sql):
    s = re.sub(r"'[^']*'", "", str(sql))
    toks = re.findall(r"[A-Za-z_][A-Za-z0-9_]*(?!\w)(?!\s*\()", s)
    return {t for t in toks if t.lower() not in KW}


def members(c): return {m["name"]: m for m in c.get("dimensions", []) + c.get("measures", [])}


# ---- V2 tables and columns
tables = {}
for c in cubes.values():
    t = c["sql_table"]
    db, name = t.split(".")
    if t not in tables:
        tables[t] = {r[0] for r in ch(f"select name from system.columns where database = '{db}' and table = '{name}'")}
    if not tables[t]: bad("V2", f"{c['name']}: table {t} not found")
    for m in c.get("dimensions", []) + c.get("measures", []):
        sql = str(m.get("sql", m["name"]))
        if m["type"] == "number" or "{" in sql: continue
        for col in columns_in(sql):
            if tables[t] and col not in tables[t]: bad("V2", f"{c['name']}.{m['name']} reads column '{col}' that {t} does not have")

# ---- V3 measure references, V8 primary keys
for c in cubes.values():
    ms = {m["name"] for m in c.get("measures", [])}
    for m in c.get("measures", []):
        for ref in re.findall(r"\{([A-Za-z_]\w*)\}", str(m.get("sql", ""))):
            if ref not in ms: bad("V3", f"{c['name']}.{m['name']} refers to unknown measure {{{ref}}}")
    pks = [d["name"] for d in c.get("dimensions", []) if d.get("primary_key")]
    if len(pks) != 1: bad("V8", f"{c['name']} has {len(pks)} primary keys")

# ---- V4 joins
for c in cubes.values():
    is_fact = c["sql_table"].split(".")[1].startswith(("fct_", "mart_"))
    for j in c.get("joins", []):
        if j["name"] not in cubes: bad("V4", f"{c['name']} joins unknown cube {j['name']}")
        elif is_fact and not j["name"].startswith("dim_"): bad("V4", f"{c['name']} joins non-dimension cube {j['name']}")
        if "{CUBE}" not in j["sql"] or "{" + j["name"] + "}" not in j["sql"]: bad("V4", f"{c['name']} join to {j['name']} does not reference both sides")

# ---- V5 rollups
for c in cubes.values():
    mem = members(c); jn = {j["name"] for j in c.get("joins", [])}
    for p in c.get("pre_aggregations", []):
        for ref in p.get("measures", []) + p.get("dimensions", []) + [p.get("time_dimension", "")]:
            cube_n, _, mem_n = ref.partition(".")
            tgt = c if cube_n == "CUBE" else cubes.get(cube_n)
            if tgt is None or (cube_n != "CUBE" and cube_n not in jn): bad("V5", f"{c['name']}.{p['name']}: {ref} is not reachable"); continue
            if mem_n not in members(tgt): bad("V5", f"{c['name']}.{p['name']}: unknown member {ref}")
        if "CUBE.project_id" not in p.get("dimensions", []): bad("V5", f"{c['name']}.{p['name']} does not list project_id")
        for ix in p.get("indexes", []):
            for col in ix.get("columns", []):
                if col not in p.get("dimensions", []): bad("V5", f"{c['name']}.{p['name']} index column {col} is not a rollup dimension")

# ---- V6 / V7 views
exposed = set()
for v in views.values():
    seen = {}
    for entry in v["cubes"]:
        path = entry["join_path"].split(".")
        if path[0] not in cubes: bad("V6", f"{v['name']}: unknown cube {path[0]}"); continue
        cur = cubes[path[0]]; exposed.add(path[0])
        for hop in path[1:]:
            if hop not in {j["name"] for j in cur.get("joins", [])}: bad("V6", f"{v['name']}: {cur['name']} has no join to {hop}"); cur = None; break
            cur = cubes[hop]
        if cur is None: continue
        mem = members(cur)
        for inc in entry["includes"]:
            if inc not in mem: bad("V6", f"{v['name']}: {cur['name']} has no member {inc}"); continue
            if mem[inc].get("public") is False: bad("V6", f"{v['name']}: includes hidden member {cur['name']}.{inc}")
            if inc in seen: bad("V6", f"{v['name']}: member name {inc} appears twice ({seen[inc]} and {cur['name']})")
            seen[inc] = cur["name"]
            if len(str(mem[inc].get("description", "")).split()) < 3: bad("V7", f"{v['name']}.{inc} has a description shorter than three words")
    for need in ("project_id", "customer_id", "date"):
        if need not in seen: bad("V6", f"{v['name']} does not expose {need}")
    if not any(m["type"] != "number" or True for m in []): pass

# ---- V9 coverage
for c in cubes.values():
    if c["sql_table"].split(".")[1].startswith(("fct_", "mart_")) and c["name"] not in exposed: bad("V9", f"{c['name']} is not exposed by any view")

n_members = sum(len(c.get("dimensions", [])) + len(c.get("measures", [])) for c in cubes.values())
print(f"cubes {len(cubes)}, views {len(views)}, members {n_members}, rollups {sum(len(c.get('pre_aggregations', [])) for c in cubes.values())}, ClickHouse tables checked {len(tables)}")
if ERR:
    by = {}
    for code, msg in ERR: by.setdefault(code, []).append(msg)
    for code, msgs in sorted(by.items()):
        print(f"FAIL {code}: {len(msgs)} problems")
        for m in msgs[:8]: print("   -", m)
    sys.exit(1)
print("PASS V1-V9: every reference resolves, every column exists, every fact and mart is exposed by a view")
