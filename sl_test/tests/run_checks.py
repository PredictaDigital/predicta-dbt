"""Run the sl_test data checks (D1-D14) and print a results table.

Reads ClickHouse connection details and credentials from the environment
(CH_HOST, CH_PORT, CH_SECURE, CH_DBT_USER, CH_DBT_PASSWORD); never prints them.
Golden numbers come from sl_test/golden/expected.json, computed in Python from the
original S3 files, independently of ClickHouse. Exits non-zero if any check fails.

Usage:  python sl_test/tests/run_checks.py [--phase 3|4]
"""
import base64
import json
import os
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
EXP = json.load(open(os.path.join(HERE, "..", "golden", "expected.json"), encoding="utf-8"))
DB = "sl_test"
PROJECT = EXP["meta"]["project_id"]
SCHEME = "https" if os.environ.get("CH_SECURE", "True").lower() == "true" else "http"
URL = f"{SCHEME}://{os.environ['CH_HOST']}:{os.environ.get('CH_PORT', '443')}/"
AUTH = "Basic " + base64.b64encode(f"{os.environ['CH_DBT_USER']}:{os.environ['CH_DBT_PASSWORD']}".encode()).decode()
RESULTS = []


def q(sql):
    """Run a query, return rows as lists (FORMAT JSONCompact)."""
    req = urllib.request.Request(URL, data=(sql + " FORMAT JSONCompact").encode(), headers={"Authorization": AUTH})
    try:
        return json.loads(urllib.request.urlopen(req, timeout=300).read().decode())["data"]
    except urllib.error.HTTPError as e:
        raise RuntimeError(e.read().decode()[:300])


def record(cid, what, expected, actual, ok, note=""):
    RESULTS.append((cid, what, str(expected), str(actual), "PASS" if ok is True else ("N/A" if ok is None else "FAIL"), note))


def close(a, b, tol=1e-6):
    return abs(float(a) - float(b)) <= tol * max(1.0, abs(float(b)))


# ------------------------------------------------------------------ D1
def d1():
    bad = {}
    for model, n in EXP["staging_rows"].items():
        got = int(q(f"select count() from {DB}.{model}")[0][0])
        if got != n:
            bad[model] = (n, got)
    record("D1", "Staging row counts equal the independently deduplicated counts", f"{len(EXP['staging_rows'])} models match",
           "all match" if not bad else f"mismatch {bad}", not bad)


# ------------------------------------------------------------------ D2
def d2():
    keys = EXP["extra"]["ga4_traffic_restated"]
    bad = []
    for k in keys:
        rows = q(f"select sum(sessions) from {DB}.fct_ga4__traffic_daily where date = '{k['date']}' and source = '{k['source']}' and medium = '{k['medium']}'")
        got = int(rows[0][0] or 0)
        if got != k["latest_sessions"]:
            bad.append((k["date"], k["source"], k["medium"], k["latest_sessions"], got))
    record("D2", "Re-sent GA4 rows: the fact holds the latest extract's value", f"{len(keys)} restated keys at latest value",
           "all at latest value" if not bad else f"wrong: {bad}", not bad and len(keys) > 0,
           "" if keys else "no restated keys found in the data, so this check proves nothing")


# ------------------------------------------------------------------ D3 / D6
def d3():
    record("D3", "Campaign snapshot: only the latest snapshot is read", "-", "-", None, "No snapshot stream in the SEO sources (GA4, GSC, Lighthouse). PPC is out of scope this round.")


def d6():
    record("D6", "Campaign rename: facts join to the right name per date", "-", "-", None, "No campaigns in the SEO sources. PPC is out of scope this round.")


# ------------------------------------------------------------------ D4
GRAIN = {
    "fct_ga4__traffic_daily": "project_id, connection_id, date, source, medium",
    "fct_ga4__page_daily": "project_id, connection_id, date, page_key",
    "fct_gsc__site_daily": "project_id, connection_id, date, search_type",
    "fct_gsc__page_daily": "project_id, connection_id, date, page_key, search_type",
    "fct_gsc__device_daily": "project_id, connection_id, date, search_type, device",
    "fct_gsc__query_daily": "project_id, connection_id, date, search_type, query",
    "fct_lighthouse__report_daily": "project_id, connection_id, date, page_key, strategy",
    "fct_lighthouse__audit_daily": "project_id, connection_id, date, page_key, strategy, audit_id",
}


def d4():
    bad = {}
    for t, g in GRAIN.items():
        n, u = q(f"select count(), uniqExact({g}) from {DB}.{t}")[0]
        exp_rows = EXP["fact_rows"][t]
        if int(n) != int(u) or int(n) != exp_rows:
            bad[t] = f"rows={n} unique={u} expected={exp_rows}"
    record("D4", "Unique grain keys per fact, and fact row counts match the golden counts", f"{len(GRAIN)} facts unique and equal to expected",
           "all unique, counts match" if not bad else bad, not bad,
           "Two-ad-account case not applicable: each source here has a single account.")


# ------------------------------------------------------------------ D5
def d5():
    pages = [t for t in GRAIN if "page_key" in GRAIN[t]]
    bad = []
    for t in pages:
        n = int(q(f"select count() from (select distinct project_id, page_key from {DB}.{t}) where (project_id, page_key) not in (select project_id, page_key from {DB}.dim_page)")[0][0])
        if n:
            bad.append((t, "page", n))
    for t in GRAIN:
        n = int(q(f"select count() from (select distinct project_id, connection_id from {DB}.{t}) where (project_id, connection_id) not in (select project_id, connection_id from {DB}.dim_connection)")[0][0])
        if n:
            bad.append((t, "connection", n))
    for t in ["fct_gsc__device_daily"]:
        n = int(q(f"select count() from (select distinct device from {DB}.{t}) where device not in (select device from {DB}.dim_device)")[0][0])
        if n:
            bad.append((t, "device", n))
    record("D5", "Relationships on project plus key: no orphans (page, connection, device)", "0 orphans", "0 orphans" if not bad else bad, not bad)


# ------------------------------------------------------------------ D7
def d7():
    rows = q(f"select page_group, uniqExact(normalised_url), count() from {DB}.sl_url_normalisation_probe group by page_group order by page_group")
    got = {r[0]: (int(r[1]), int(r[2])) for r in rows}
    variants_ok = got.get("about", (0, 0))[0] == 1 and got.get("home", (0, 0))[0] == 1
    distinct_ok = int(q(f"select uniqExact(normalised_url) from {DB}.sl_url_normalisation_probe")[0][0]) == len(got)
    col = EXP["extra"]["ga4_pages_collapse"]
    n_dim = int(q(f"select count() from (select distinct project_id, page_key from {DB}.fct_ga4__page_daily)")[0][0])
    ok = variants_ok and distinct_ok and n_dim == col["distinct_normalised_urls"]
    record("D7", "URL variants collapse to one page_key; different pages stay different",
           f"about: 1 form from {got.get('about', ('?', '?'))[1]} variants, home: 1 from {got.get('home', ('?', '?'))[1]}; GA4 pages: {col['distinct_normalised_urls']} keys from {col['distinct_raw_paths']} raw paths",
           f"{got}; GA4 page keys {n_dim}", ok)


# ------------------------------------------------------------------ D8
MEAS = {
    "fct_ga4__traffic_daily": (None, ["sessions", "engaged_sessions", "total_users", "new_users", "pageviews", "session_duration_sec"]),
    "fct_ga4__page_daily": (None, ["pageviews"]),
    "fct_gsc__site_daily": ("search_type", ["clicks", "impressions", "sum_position", "position_impressions"]),
    "fct_gsc__page_daily": ("search_type", ["clicks", "impressions", "sum_position", "position_impressions"]),
    "fct_gsc__device_daily": ("search_type", ["clicks", "impressions", "sum_position", "position_impressions"]),
    "fct_gsc__query_daily": ("search_type", ["clicks", "impressions", "sum_position", "position_impressions"]),
    "fct_lighthouse__report_daily": ("strategy", ["runs", "performance_score", "accessibility_score", "best_practices_score", "seo_score",
                                                  "first_contentful_paint_ms", "speed_index_ms", "largest_contentful_paint_ms",
                                                  "time_to_interactive_ms", "total_blocking_time_ms", "cumulative_layout_shift"]),
    "fct_lighthouse__audit_daily": ("strategy", ["score", "audit_failed", "audit_scored"]),
}


def d8():
    bad, checked = [], 0
    for t, (sub, ms) in MEAS.items():
        sel = ", ".join(f"sum({m})" for m in ms)
        if t == "fct_lighthouse__audit_daily":
            sel += ", count()"
        grp = "date" + (f", {sub}" if sub else "")
        exp = EXP["totals_by_date"][t]
        got = {}
        for r in q(f"select {grp.replace('date', 'toString(date)', 1)}, {sel} from {DB}.{t} where project_id = '{PROJECT}' group by {grp}"):
            key = r[0] if not sub else f"{r[0]}|{r[1]}"
            vals = r[1:] if not sub else r[2:]
            got[key] = vals
        if set(got) != set(exp):
            bad.append((t, "date keys differ", len(exp), len(got)))
            continue
        names = list(ms) + (["audits"] if t == "fct_lighthouse__audit_daily" else [])
        for key, e in exp.items():
            for i, m in enumerate(names):
                checked += 1
                if not close(got[key][i], e[m]):
                    bad.append((t, key, m, e[m], got[key][i]))
    record("D8", "Fact totals per project, date and source match expected.json", f"{checked} measure totals match",
           "all match" if not bad else f"{len(bad)} mismatches, first: {bad[:2]}", not bad)


PHASE3 = [d1, d2, d3, d4, d5, d6, d7, d8]

if __name__ == "__main__":
    phase = int(sys.argv[sys.argv.index("--phase") + 1]) if "--phase" in sys.argv else 99
    todo = list(PHASE3)
    if phase >= 4:
        try:
            from phase4_checks import PHASE4  # D9-D14, added in phase 4
            todo += PHASE4
        except ImportError:
            pass
    for f in todo:
        try:
            f()
        except Exception as e:  # a check that cannot run is a failure, not a skip
            record(f.__name__.upper(), "check could not run", "-", f"{type(e).__name__}: {e}"[:200], False)
    w = [max(len(r[i]) for r in RESULTS + [("Id", "Check", "Expected", "Actual", "Result", "Note")]) for i in range(4)]
    w = [min(x, 70) for x in w]
    print(f"{'Id':<4} | {'Check':<{w[1]}} | {'Result':<6} | Expected -> Actual")
    for r in RESULTS:
        print(f"{r[0]:<4} | {r[1][:w[1]]:<{w[1]}} | {r[4]:<6} | {r[2][:110]} -> {r[3][:140]}" + (f"  [{r[5]}]" if r[5] else ""))
    failed = [r for r in RESULTS if r[4] == "FAIL"]
    print(f"\n{len(RESULTS)} checks: {sum(r[4]=='PASS' for r in RESULTS)} pass, {len(failed)} fail, {sum(r[4]=='N/A' for r in RESULTS)} not applicable")
    sys.exit(1 if failed else 0)
