"""Cube checks C1-C9 for the sl_test SEO semantic layer.

Needs a running Cube (CUBE_URL, default http://localhost:4000) and, from the
environment: CUBEJS_API_SECRET (signing secret), and CH_HOST, CH_PORT, CH_SECURE,
CH_DBT_USER, CH_DBT_PASSWORD for the ClickHouse comparison (C9). Secrets and tokens
are never printed. Exits non-zero if any check fails.

Usage:  python sl_test/tests/run_cube_checks.py
"""
import base64
import glob
import json
import os
import sys
import urllib.request

import yaml

import cube_client as cc

HERE = os.path.dirname(os.path.abspath(__file__))
MODEL = os.path.join(HERE, "..", "cube", "model")
EXP = json.load(open(os.path.join(HERE, "..", "golden", "expected.json"), encoding="utf-8"))
TP = EXP["totals_project"]
RESULTS = []
P, C = "proj_pa", "cust_predicta"
GOOD = None  # token for the real project
# SL_BYPASS_ROLLUPS=1 adds the project_name dimension to every query. No rollup carries it, so the query
# runs straight against ClickHouse. Use it when the target Cube has no working rollup builds.
BYPASS = os.environ.get("SL_BYPASS_ROLLUPS", "") == "1"


def visible(meta):
    """Cubes the caller may use. Some Cube versions list hidden cubes in /meta flagged
    public:false / isVisible:false, so filter on the flags and not only on presence."""
    return [c for c in meta["cubes"] if c.get("isVisible", True) and c.get("public", True)]


def cload(query, tok):
    if BYPASS and query.get("measures"):
        view = query["measures"][0].split(".")[0]
        query = dict(query, dimensions=list(query.get("dimensions", [])) + [f"{view}.project_name"])
    return cc.load(query, tok, tries=8, timeout=60)


def record(cid, what, expected, actual, ok, note=""):
    RESULTS.append((cid, what, str(expected), str(actual), "PASS" if ok is True else ("N/A" if ok is None else "FAIL"), note))


def close(a, b, tol=1e-6):
    return abs(float(a) - float(b)) <= tol * max(1.0, abs(float(b)))


def load(query, tok=None):
    return cload(query, tok or GOOD)


def one(measures, view, tok=None):
    st, js = load({"measures": [f"{view}.{m}" for m in measures]}, tok)
    if st != 200 or not js.get("data"):
        return st, None
    return st, {m: float(js["data"][0].get(f"{view}.{m}") or 0) for m in measures}


# ----------------------------------------------------------- expectations (from the golden file)
def exp_measures():
    t = TP
    ga, gp = t["fct_ga4__traffic_daily"], t["fct_ga4__page_daily"]
    lh, au = t["fct_lighthouse__report_daily"], t["fct_lighthouse__audit_daily"]
    out = {"seo_traffic": {"ga4_sessions": ga["sessions"], "ga4_engaged_sessions": ga["engaged_sessions"], "ga4_user_days": ga["total_users"],
                           "ga4_new_users": ga["new_users"], "ga4_pageviews": ga["pageviews"],
                           "ga4_engagement_rate": ga["engaged_sessions"] / ga["sessions"],
                           "ga4_pageviews_per_session": ga["pageviews"] / ga["sessions"],
                           "ga4_avg_session_duration_sec": ga["session_duration_sec"] / ga["sessions"]},
           "seo_pages": {"ga4_page_pageviews": gp["pageviews"]}}
    for view, fact in [("seo_search_site", "fct_gsc__site_daily"), ("seo_search_pages", "fct_gsc__page_daily"),
                       ("seo_search_devices", "fct_gsc__device_daily"), ("seo_search_queries", "fct_gsc__query_daily")]:
        g = t[fact]
        out[view] = {"gsc_clicks": g["clicks"], "gsc_impressions": g["impressions"], "gsc_ctr": g["clicks"] / g["impressions"],
                     "gsc_avg_position": g["sum_position"] / g["position_impressions"]}
    runs = lh["runs"]
    out["seo_lighthouse_runs"] = {"lh_runs": runs, "lh_avg_performance": lh["performance_score"] / runs, "lh_avg_accessibility": lh["accessibility_score"] / runs,
                                  "lh_avg_best_practices": lh["best_practices_score"] / runs, "lh_avg_seo": lh["seo_score"] / runs,
                                  "lh_avg_fcp_ms": lh["first_contentful_paint_ms"] / runs, "lh_avg_speed_index_ms": lh["speed_index_ms"] / runs,
                                  "lh_avg_lcp_ms": lh["largest_contentful_paint_ms"] / runs, "lh_avg_tti_ms": lh["time_to_interactive_ms"] / runs,
                                  "lh_avg_tbt_ms": lh["total_blocking_time_ms"] / runs, "lh_avg_cls": lh["cumulative_layout_shift"] / runs}
    out["seo_lighthouse_audits"] = {"lh_audits_scored": au["audit_scored"], "lh_audits_failed": au["audit_failed"],
                                    "lh_audit_failure_rate": au["audit_failed"] / au["audit_scored"]}
    return out


# ----------------------------------------------------------- C1 / C2
def c1_c2():
    st, meta = cc.meta(GOOD)
    public = {c["name"]: [m["name"].split(".")[1] for m in c["measures"]] for c in visible(meta)}
    exp = exp_measures()
    additive_bad, ratio_bad, uncovered = [], [], []
    ratios = {"ga4_engagement_rate", "ga4_pageviews_per_session", "ga4_avg_session_duration_sec", "gsc_ctr", "gsc_avg_position", "lh_audit_failure_rate"} | \
             {m for v in exp.values() for m in v if m.startswith("lh_avg_")}
    n1 = n2 = 0
    for view, ms in public.items():
        for m in ms:
            if m not in exp.get(view, {}):
                uncovered.append(f"{view}.{m}")
                continue
            st, got = one([m], view)
            ok = got is not None and close(got[m], exp[view][m])
            if m in ratios:
                n2 += 1
                if not ok:
                    ratio_bad.append((view, m, exp[view][m], None if got is None else got[m]))
            else:
                n1 += 1
                if not ok:
                    additive_bad.append((view, m, exp[view][m], None if got is None else got[m]))
    record("C1", "Every public additive measure through the REST API equals expected.json", f"{n1} measures match",
           "all match" if not additive_bad else additive_bad[:3], not additive_bad and not uncovered,
           f"uncovered public measures: {uncovered}" if uncovered else "")
    record("C2", "ctr, avg position, engagement rate, averages equal the ratio of the golden sums", f"{n2} ratios match",
           "all match" if not ratio_bad else ratio_bad[:3], not ratio_bad)


# ----------------------------------------------------------- C3
def c3():
    names = {c["name"] for c in visible(cc.meta(GOOD)[1])}
    hidden = {"ga4_traffic", "ga4_page", "gsc_site", "gsc_page", "gsc_device", "gsc_query", "lighthouse_report", "lighthouse_audit"}
    st, js = load({"measures": ["ga4_traffic.ga4_sessions"]})
    ok = not (names & hidden) and st >= 400
    record("C3", "A source cube requested with a normal token is not available", "not in meta, query refused",
           f"visible source cubes={sorted(names & hidden)}, query status={st}", ok)


# ----------------------------------------------------------- C4 / C5 / C6
def cubes_yaml():
    out = {}
    for f in glob.glob(os.path.join(MODEL, "cubes", "*.yml")):
        for c in yaml.safe_load(open(f, encoding="utf-8"))["cubes"]:
            out[c["name"]] = c
    return out


def c4():
    cubes = cubes_yaml()
    facts = {n for n, c in cubes.items() if str(c.get("sql_table", "")).split(".")[-1].startswith("fct_")}
    bad = [(n, j["name"]) for n in facts for j in cubes[n].get("joins", []) if j["name"] in facts]
    bad += [(n, j["name"]) for n in facts for j in cubes[n].get("joins", []) if not j["name"].startswith("dim_")]
    record("C4", "Model scan: no cube joins one fact cube to another", "0 fact-to-fact joins", f"{len(bad)}: {bad}" if bad else "0", not bad)


def c5():
    cubes = cubes_yaml()
    pa = [(n, p["name"], p) for n, c in cubes.items() for p in c.get("pre_aggregations", [])]
    bad = [(n, name) for n, name, p in pa if "CUBE.project_id" not in p.get("dimensions", [])]
    record("C5", "Model scan: every rollup lists project_id", f"{len(pa)} rollups list project_id", "all do" if not bad else bad, not bad and len(pa) > 0)


def c6():
    cubes = visible(cc.meta(GOOD)[1])
    bad = []
    n = 0
    for c in cubes:
        for kind in ("measures", "dimensions"):
            for m in c[kind]:
                n += 1
                if len(str(m.get("description", "")).split()) < 3:
                    bad.append(m["name"])
    record("C6", "Every public measure and dimension has a description of at least three words", f"{n} members described", "all do" if not bad else bad[:5], not bad)


# ----------------------------------------------------------- C7 / C8
def count(tok, view="seo_traffic", extra=None):
    q = {"measures": [f"{view}.ga4_sessions"]}
    if extra:
        q.update(extra)
    st, js = cload(q, tok)
    if st != 200:
        return st, None
    rows = js.get("data", [])
    return st, float(rows[0].get(f"{view}.ga4_sessions") or 0) if rows else 0.0


def c7():
    t_same_cust_other_proj = cc.token({"customer_id": C, "project_ids": ["proj_other"]})
    t_other_cust_real_proj = cc.token({"customer_id": "cust_other", "project_ids": [P]})
    t_other_cust = cc.token({"customer_id": "cust_other", "project_ids": ["proj_x"]})
    t_multi = cc.token({"customer_id": C, "project_ids": [P, "proj_other"]})
    t_noclaims = cc.token({})
    t_badsig = cc.token({"customer_id": C, "project_ids": [P]}, secret="not-the-secret")
    _, own = count(GOOD)
    _, multi = count(t_multi)
    # forged filter: a token for another project asks explicitly for the real project
    forged = {"filters": [{"member": "seo_traffic.project_id", "operator": "equals", "values": [P]}]}
    rows = {
        "own project sees its data": own and own > 0,
        "same customer, other project sees nothing": count(t_same_cust_other_proj)[1] == 0,
        "other customer, real project id sees nothing": count(t_other_cust_real_proj)[1] == 0,
        "other customer sees nothing": count(t_other_cust)[1] == 0,
        "forged project filter returns nothing": count(t_same_cust_other_proj, extra=forged)[1] == 0,
        "token listing two projects sees only existing data": multi == own,
        "token without claims is refused": count(t_noclaims)[0] >= 400,
        "bad signature is rejected": count(t_badsig)[0] in (401, 403),
    }
    bad = [k for k, v in rows.items() if not v]
    record("C7", "Isolation matrix (own, other project, other customer, forged filter, no claims, bad signature)", f"{len(rows)} cases behave",
           "all behave" if not bad else bad, not bad)


def c8():
    tA = GOOD
    tB = cc.token({"customer_id": C, "project_ids": ["proj_b"]})
    _, a1 = count(tA)
    _, b1 = count(tB)       # warm cache: same widget query, other project
    _, a2 = count(tA)
    ok = a1 and a1 > 0 and b1 == 0 and a2 == a1
    record("C8", "Cache isolation: same widget query as token A then B with a warm cache", "B never receives A's rows",
           f"A={a1}, B={b1}, A again={a2}", ok,
           "Rollup use not testable here: the scratch Cube ran without rollups (Cube Store build fails on Windows). usedPreAggregations = none.")


# ----------------------------------------------------------- R1 (rollup status)
def r1():
    q = {"measures": ["seo_traffic.ga4_sessions"], "dimensions": ["seo_traffic.channel_group"]}   # served by the ga4_traffic_daily rollup
    t0 = __import__("time").time()
    st, js = cc.load(q, GOOD, tries=3, timeout=60)
    waited = round(__import__("time").time() - t0)
    used = js.get("usedPreAggregations") if isinstance(js, dict) else None
    ok = st == 200 and bool(used)
    record("R1", "A rollup-eligible query is answered from a built rollup within about 3 minutes", "200 with usedPreAggregations",
           f"status {st} after {waited}s, usedPreAggregations={list(used) if used else None}" + ("" if ok else f", error: {str(js.get('error', ''))[:110]}"), ok)


# ----------------------------------------------------------- C9
CHURL = f"{'https' if os.environ.get('CH_SECURE', 'True').lower() == 'true' else 'http'}://{os.environ.get('CH_HOST', '')}:{os.environ.get('CH_PORT', '443')}/"
CHAUTH = "Basic " + base64.b64encode(f"{os.environ.get('CH_DBT_USER', '')}:{os.environ.get('CH_DBT_PASSWORD', '')}".encode()).decode()


def ch(sql):
    req = urllib.request.Request(CHURL, data=(sql + " FORMAT JSONCompact").encode(), headers={"Authorization": CHAUTH})
    return json.loads(urllib.request.urlopen(req, timeout=300).read().decode())["data"]


QUERIES = [
    ("sessions by channel group", {"measures": ["seo_traffic.ga4_sessions"], "dimensions": ["seo_traffic.channel_group"]},
     "select dc.channel_group, sum(f.sessions) from sl_test.fct_ga4__traffic_daily f left join sl_test.dim_channel dc on f.source = dc.source and f.medium = dc.medium where f.project_id = 'proj_pa' group by 1"),
    ("sessions by month", {"measures": ["seo_traffic.ga4_sessions"], "timeDimensions": [{"dimension": "seo_traffic.date", "granularity": "month"}]},
     "select formatDateTime(toStartOfMonth(date), '%Y-%m-%dT00:00:00.000'), sum(sessions) from sl_test.fct_ga4__traffic_daily where project_id = 'proj_pa' group by 1"),
    ("sessions by source and medium", {"measures": ["seo_traffic.ga4_sessions"], "dimensions": ["seo_traffic.source", "seo_traffic.medium"]},
     "select source, medium, sum(sessions) from sl_test.fct_ga4__traffic_daily where project_id = 'proj_pa' group by 1, 2"),
    ("gsc clicks and impressions by search type", {"measures": ["seo_search_site.gsc_clicks", "seo_search_site.gsc_impressions"], "dimensions": ["seo_search_site.search_type"]},
     "select search_type, sum(clicks), sum(impressions) from sl_test.fct_gsc__site_daily where project_id = 'proj_pa' group by 1"),
    ("gsc clicks by page", {"measures": ["seo_search_pages.gsc_clicks"], "dimensions": ["seo_search_pages.page_url"]},
     "select dp.page_url, sum(f.clicks) from sl_test.fct_gsc__page_daily f left join sl_test.dim_page dp on f.project_id = dp.project_id and f.page_key = dp.page_key where f.project_id = 'proj_pa' group by 1"),
    ("gsc avg position by device", {"measures": ["seo_search_devices.gsc_avg_position"], "dimensions": ["seo_search_devices.device"]},
     "select device, sum(sum_position) / sum(position_impressions) from sl_test.fct_gsc__device_daily where project_id = 'proj_pa' group by 1"),
    ("gsc clicks by query", {"measures": ["seo_search_queries.gsc_clicks"], "dimensions": ["seo_search_queries.query"]},
     "select query, sum(clicks) from sl_test.fct_gsc__query_daily where project_id = 'proj_pa' group by 1"),
    ("ga4 page views by page", {"measures": ["seo_pages.ga4_page_pageviews"], "dimensions": ["seo_pages.page_url"]},
     "select dp.page_url, sum(f.pageviews) from sl_test.fct_ga4__page_daily f left join sl_test.dim_page dp on f.project_id = dp.project_id and f.page_key = dp.page_key where f.project_id = 'proj_pa' group by 1"),
    ("lighthouse avg performance by strategy", {"measures": ["seo_lighthouse_runs.lh_avg_performance", "seo_lighthouse_runs.lh_avg_lcp_ms"], "dimensions": ["seo_lighthouse_runs.strategy"]},
     "select strategy, sum(performance_score) / sum(runs), sum(largest_contentful_paint_ms) / sum(runs) from sl_test.fct_lighthouse__report_daily where project_id = 'proj_pa' group by 1"),
    ("lighthouse failed audits by title", {"measures": ["seo_lighthouse_audits.lh_audits_failed"], "dimensions": ["seo_lighthouse_audits.audit_title"]},
     "select da.audit_title, sum(f.audit_failed) from sl_test.fct_lighthouse__audit_daily f left join sl_test.dim_audit da on f.audit_id = da.audit_id where f.project_id = 'proj_pa' group by 1"),
]


def c9():
    bad = []
    for name, q, sql in QUERIES:
        q = dict(q, limit=50000)
        st, js = load(q)
        if st != 200:
            bad.append((name, f"cube status {st}"))
            continue
        keys = q.get("dimensions", []) + [t["dimension"] + "." + t["granularity"] for t in q.get("timeDimensions", [])]
        ms = q["measures"]
        cube = {}
        for r in js["data"]:
            cube[tuple(str(r.get(k)) for k in keys)] = [float(r.get(m) or 0) for m in ms]
        chd = {}
        for r in ch(sql):
            chd[tuple(str(x) for x in r[:len(keys)])] = [float(x or 0) for x in r[len(keys):]]
        if set(cube) != set(chd):
            bad.append((name, f"row keys differ: cube {len(cube)} vs clickhouse {len(chd)}"))
            continue
        if any(not close(a, b) for k in cube for a, b in zip(cube[k], chd[k])):
            bad.append((name, "values differ"))
    record("C9", "Cube against ClickHouse for ten representative queries", "10 identical results",
           "all identical" if not bad else bad, not bad)


if __name__ == "__main__":
    GOOD = cc.token({"customer_id": C, "project_ids": [P]})
    for f in (c1_c2, c3, c4, c5, c6, c7, c8, c9, r1):
        try:
            f()
        except Exception as e:
            record(f.__name__.upper(), "check could not run", "-", f"{type(e).__name__}: {e}"[:200], False)
    print(f"{'Id':<4} | {'Check':<92} | Result | Expected -> Actual")
    for r in RESULTS:
        print(f"{r[0]:<4} | {r[1][:92]:<92} | {r[4]:<6} | {r[2][:60]} -> {r[3][:150]}" + (f"  [{r[5]}]" if r[5] else ""))
    failed = [r for r in RESULTS if r[4] == "FAIL"]
    print(f"\n{len(RESULTS)} checks: {sum(r[4] == 'PASS' for r in RESULTS)} pass, {len(failed)} fail, {sum(r[4] == 'N/A' for r in RESULTS)} not applicable")
    sys.exit(1 if failed else 0)
