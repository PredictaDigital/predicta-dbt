"""Build the SEO dashboard: query the Cube views, embed the results in one HTML file.

Reads CUBEJS_API_SECRET (and optionally CUBE_URL, default http://localhost:4000) from
the environment and signs a short-lived token for the project below. Nothing secret is
written to the output. Re-run this script to refresh the snapshot.

Usage:  python sl_test/dashboard/build_dashboard.py
"""
import datetime as dt
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "tests"))
import cube_client as cc  # noqa: E402

CUSTOMER, PROJECT = "cust_predicta", "proj_pa"
TOK = cc.token({"customer_id": CUSTOMER, "project_ids": [PROJECT]}, ttl=1800)
RANGES = {"7d": 7, "14d": 14, "28d": 28, "all": None}


def q(query, tries=5):
    """Run a Cube query. The shared ClickHouse server occasionally aborts a query when it
    is near its memory cap, so retry a few times with a growing pause before giving up."""
    for attempt in range(1, tries + 1):
        st, js = cc.load(query, TOK)
        if st == 200:
            return js["data"]
        if attempt == tries:
            raise RuntimeError(f"Cube {st}: {str(js)[:300]}")
        time.sleep(3 * attempt)


def num(row, key):
    v = row.get(key)
    return float(v) if v not in (None, "") else 0.0


def day(s):
    return str(s)[:10]


def window(end, n, back=0):
    """[start, end] covering n days, shifted `back` windows into the past."""
    e = end - dt.timedelta(days=n * back)
    return [str(e - dt.timedelta(days=n - 1)), str(e)]


def span(view):
    rows = q({"measures": [f"{view}.{'ga4_sessions' if view == 'seo_traffic' else 'gsc_clicks'}"],
              "timeDimensions": [{"dimension": f"{view}.date", "granularity": "day"}], "order": {f"{view}.date": "asc"}})
    days = [day(r[f"{view}.date.day"]) for r in rows]
    return days[0], days[-1], rows


def rng(view, win):
    return [{"dimension": f"{view}.date", "dateRange": win}] if win else []


def totals(view, measures, win):
    rows = q({"measures": [f"{view}.{m}" for m in measures], "timeDimensions": rng(view, win)})
    return {m: num(rows[0], f"{view}.{m}") if rows else 0.0 for m in measures}


def grouped(view, dims, measures, win, order, limit=5000):
    rows = q({"measures": [f"{view}.{m}" for m in measures], "dimensions": [f"{view}.{d}" for d in dims],
              "timeDimensions": rng(view, win), "order": {f"{view}.{order}": "desc"}, "limit": limit})
    return [{**{d: r.get(f"{view}.{d}") for d in dims}, **{m: num(r, f"{view}.{m}") for m in measures}} for r in rows]


GA4_M = ["ga4_sessions", "ga4_engaged_sessions", "ga4_new_users", "ga4_pageviews", "ga4_engagement_rate",
         "ga4_pageviews_per_session", "ga4_avg_session_duration_sec"]
GSC_M = ["gsc_clicks", "gsc_impressions", "gsc_ctr", "gsc_avg_position"]


def build():
    g_min, g_max, g_rows = span("seo_traffic")
    s_min, s_max, s_rows = span("seo_search_site")
    g_end, s_end = dt.date.fromisoformat(g_max), dt.date.fromisoformat(s_max)
    data = {"generated_at": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
            "project": PROJECT, "customer": CUSTOMER,
            "coverage": {"ga4": [g_min, g_max], "gsc": [s_min, s_max]}, "ranges": {}}

    # daily series (whole history; the page slices it to the chosen window)
    ga_daily = {}
    for r in q({"measures": ["seo_traffic.ga4_sessions", "seo_traffic.ga4_pageviews", "seo_traffic.ga4_new_users"],
                "timeDimensions": [{"dimension": "seo_traffic.date", "granularity": "day"}], "order": {"seo_traffic.date": "asc"}}):
        ga_daily[day(r["seo_traffic.date.day"])] = [num(r, "seo_traffic.ga4_sessions"), num(r, "seo_traffic.ga4_pageviews"), num(r, "seo_traffic.ga4_new_users")]
    gs_daily = {}
    for r in q({"measures": ["seo_search_site.gsc_clicks", "seo_search_site.gsc_impressions"],
                "timeDimensions": [{"dimension": "seo_search_site.date", "granularity": "day"}], "order": {"seo_search_site.date": "asc"}}):
        gs_daily[day(r["seo_search_site.date.day"])] = [num(r, "seo_search_site.gsc_clicks"), num(r, "seo_search_site.gsc_impressions")]
    data["daily"] = {"ga4": ga_daily, "gsc": gs_daily}

    for key, n in RANGES.items():
        print("range", key, flush=True)
        if n:
            gw, gp = window(g_end, n), window(g_end, n, 1)
            sw, sp = window(s_end, n), window(s_end, n, 1)
            gw[0], sw[0] = max(gw[0], g_min), max(sw[0], s_min)
            # A delta is only honest if the whole prior window has data. Data starts on
            # g_min / s_min, so a window that reaches before it would compare against a part-empty period.
            gp = gp if gp[0] >= g_min else None
            sp = sp if sp[0] >= s_min else None
        else:
            gw, gp, sw, sp = [g_min, g_max], None, [s_min, s_max], None
        r = {"ga4_window": gw, "gsc_window": sw}
        r["ga4"] = totals("seo_traffic", GA4_M, gw)
        r["ga4_prev"] = totals("seo_traffic", GA4_M, gp) if gp else None
        r["channels"] = grouped("seo_traffic", ["channel_group"], ["ga4_sessions", "ga4_engagement_rate"], gw, "ga4_sessions")
        r["channels_prev"] = grouped("seo_traffic", ["channel_group"], ["ga4_sessions"], gp, "ga4_sessions") if gp else None
        r["sources"] = grouped("seo_traffic", ["source", "medium"], ["ga4_sessions", "ga4_engagement_rate", "ga4_pageviews_per_session"], gw, "ga4_sessions", 10)
        r["ga4_pages"] = grouped("seo_pages", ["page_url"], ["ga4_page_pageviews"], gw, "ga4_page_pageviews", 10)
        r["gsc"] = totals("seo_search_site", GSC_M, sw)
        r["gsc_prev"] = totals("seo_search_site", GSC_M, sp) if sp else None
        r["devices"] = grouped("seo_search_devices", ["device"], GSC_M, sw, "gsc_clicks")
        r["search_types"] = grouped("seo_search_site", ["search_type"], ["gsc_clicks", "gsc_impressions"], sw, "gsc_clicks")
        queries = grouped("seo_search_queries", ["query"], GSC_M, sw, "gsc_clicks", 5000)
        pages = grouped("seo_search_pages", ["page_url"], GSC_M, sw, "gsc_clicks", 5000)
        r["queries"], r["queries_distinct"] = queries[:15], len(queries)
        r["pages"], r["pages_distinct"] = pages[:10], len(pages)
        data["ranges"][key] = r

    lh_meas = ["lh_runs", "lh_avg_performance", "lh_avg_accessibility", "lh_avg_best_practices", "lh_avg_seo", "lh_avg_fcp_ms",
               "lh_avg_speed_index_ms", "lh_avg_lcp_ms", "lh_avg_tti_ms", "lh_avg_tbt_ms", "lh_avg_cls"]
    rows = q({"measures": [f"seo_lighthouse_runs.{m}" for m in lh_meas], "dimensions": ["seo_lighthouse_runs.strategy", "seo_lighthouse_runs.page_url"],
              "timeDimensions": [{"dimension": "seo_lighthouse_runs.date", "granularity": "day"}], "order": {"seo_lighthouse_runs.date": "desc"}})
    data["lighthouse"] = [{"strategy": r["seo_lighthouse_runs.strategy"], "page_url": r["seo_lighthouse_runs.page_url"],
                           "date": day(r["seo_lighthouse_runs.date.day"]), **{m: num(r, f"seo_lighthouse_runs.{m}") for m in lh_meas}} for r in rows]
    rows = q({"measures": ["seo_lighthouse_audits.lh_audits_failed", "seo_lighthouse_audits.lh_audits_scored"],
              "dimensions": ["seo_lighthouse_audits.audit_title", "seo_lighthouse_audits.strategy", "seo_lighthouse_audits.page_url"],
              "order": {"seo_lighthouse_audits.lh_audits_failed": "desc"}, "limit": 5000})
    data["audits"] = [{"audit": r["seo_lighthouse_audits.audit_title"], "strategy": r["seo_lighthouse_audits.strategy"], "page_url": r["seo_lighthouse_audits.page_url"],
                       "failed": num(r, "seo_lighthouse_audits.lh_audits_failed"), "scored": num(r, "seo_lighthouse_audits.lh_audits_scored")} for r in rows]
    return data


if __name__ == "__main__":
    data = build()
    tpl = open(os.path.join(HERE, "dashboard.template.html"), encoding="utf-8").read()
    html = tpl.replace("/*__DATA__*/null", json.dumps(data, separators=(",", ":")).replace("</", "<\\/"))
    out = os.path.join(HERE, "dashboard.html")
    open(out, "w", encoding="utf-8").write(html)
    json.dump(data, open(os.path.join(HERE, "dashboard_data.json"), "w", encoding="utf-8"), indent=1)
    print("wrote", out, f"({len(html)//1024} KB)")
