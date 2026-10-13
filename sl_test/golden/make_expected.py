"""Compute the golden numbers for the sl_test SEO models, independently of ClickHouse.

Reads the original Airbyte CSV files from S3, applies the documented rules in plain
Python (latest _airbyte_extracted_at wins per natural key, URL normalisation, the
same derived measures) and writes expected.json next to this file.

Credentials come from the environment (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY,
optional AWS_REGION and SL_S3_BUCKET). Nothing secret is printed or written.
"""
import collections
import csv
import io
import json
import math
import os
import re
import sys
from datetime import date, datetime, timezone

import boto3

csv.field_size_limit(sys.maxsize)
BUCKET = os.environ.get("SL_S3_BUCKET", "pa-poc-airbyte-data")
PREFIX = "airbyte/raw/airbyte_raw/"
PROJECT = "proj_pa"  # all PA data maps to one project (see seeds/sl_test/sl_connections.csv)

s3 = boto3.client(
    "s3",
    aws_access_key_id=os.environ["AWS_ACCESS_KEY_ID"],
    aws_secret_access_key=os.environ["AWS_SECRET_ACCESS_KEY"],
    region_name=os.environ.get("AWS_REGION", "us-east-1"),
)


def rows_of(table):
    """Every raw record of a stream: dicts with payload, extracted_at and file."""
    out = []
    for p in s3.get_paginator("list_objects_v2").paginate(Bucket=BUCKET, Prefix=f"{PREFIX}{table}/"):
        for o in p.get("Contents", []):
            body = s3.get_object(Bucket=BUCKET, Key=o["Key"])["Body"].read().decode()
            for i, r in enumerate(csv.DictReader(io.StringIO(body))):
                out.append({"d": json.loads(r["_airbyte_data"] or "{}"),
                            "ext": int(r["_airbyte_extracted_at"] or 0),
                            "file": o["Key"], "i": i})
    return out


def latest(rows, keyfn):
    """Keep the record with the highest extracted-at per natural key."""
    best = {}
    for r in rows:
        k = keyfn(r["d"])
        if k not in best or (r["ext"], r["file"], r["i"]) > (best[k]["ext"], best[k]["file"], best[k]["i"]):
            best[k] = r
    return best


def norm_url(u):
    u = u.strip().lower()
    u = re.sub(r"[#].*$", "", u)
    u = re.sub(r"[?].*$", "", u)
    return re.sub(r"/+$", "", u)


def half_up(x):
    return int(math.floor(x + 0.5))


def parse_ms(x):
    """Lighthouse timings arrive as display strings ('2.6 s', '0 ms'); return milliseconds."""
    if isinstance(x, (int, float)):
        return float(x)
    t = str(x).replace(" ", " ").strip()
    n = float(re.search(r"[0-9][0-9,.]*", t).group().replace(",", ""))
    if t.endswith("ms"):
        return n
    return n * 1000 if t.endswith("s") else n


def iso(d):
    d = str(d)
    return f"{d[0:4]}-{d[4:6]}-{d[6:8]}" if re.fullmatch(r"\d{8}", d) else d


def add(acc, key, vals):
    a = acc.setdefault(key, collections.defaultdict(float))
    for k, v in vals.items():
        a[k] += v


def finish(acc):
    return {k: {m: (round(v, 6) if isinstance(v, float) else v) for m, v in vals.items()} for k, vals in acc.items()}


exp = {"meta": {"generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                "source": f"s3://{BUCKET}/{PREFIX}", "project_id": PROJECT},
       "staging_rows": {}, "fact_rows": {}, "totals_by_date": {}, "totals_project": {}, "extra": {}}

# ---------------- GA4 traffic ----------------
raw = rows_of("GA4_PA_traffic_sources")
best = latest(raw, lambda d: (iso(d["date"]), d["sessionSource"], d["sessionMedium"]))
exp["staging_rows"]["stg_ga4__traffic_sources"] = len(best)
exp["fact_rows"]["fct_ga4__traffic_daily"] = len(best)
by_date, total = {}, collections.defaultdict(float)
for k, r in best.items():
    d = r["d"]
    s = int(d["sessions"])
    v = {"sessions": s, "engaged_sessions": half_up(s * (1 - float(d["bounceRate"]))),
         "total_users": int(d["totalUsers"]), "new_users": int(d["newUsers"]),
         "pageviews": int(d["screenPageViews"]), "session_duration_sec": float(d["averageSessionDuration"]) * s}
    add(by_date, k[0], v)
    for m, x in v.items():
        total[m] += x
exp["totals_by_date"]["fct_ga4__traffic_daily"] = finish(by_date)
exp["totals_project"]["fct_ga4__traffic_daily"] = finish({"all": total})["all"]
# D2: keys re-sent with a different value; the latest extract must win in the fact
seen = collections.defaultdict(list)
for r in raw:
    seen[(iso(r["d"]["date"]), r["d"]["sessionSource"], r["d"]["sessionMedium"])].append(r)
restated = []
for k, lst in seen.items():
    vals = {int(x["d"]["sessions"]) for x in lst}
    if len(lst) > 1 and len(vals) > 1:
        win = best[k]
        restated.append({"date": k[0], "source": k[1], "medium": k[2],
                         "latest_sessions": int(win["d"]["sessions"]),
                         "other_sessions": sorted(vals - {int(win["d"]["sessions"])})})
exp["extra"]["ga4_traffic_restated"] = restated
exp["extra"]["ga4_traffic_raw_rows"] = len(raw)

# ---------------- GA4 pages ----------------
raw = rows_of("GA4_PA_pages")
best = latest(raw, lambda d: (iso(d["date"]), d["hostName"], d["pagePathPlusQueryString"]))
exp["staging_rows"]["stg_ga4__pages"] = len(best)
groups, by_date, total = {}, {}, collections.defaultdict(float)
for k, r in best.items():
    url = norm_url("https://" + k[1] + k[2])
    g = (k[0], url)
    groups[g] = groups.get(g, 0) + int(r["d"]["screenPageViews"])
for (dt, url), pv in groups.items():
    add(by_date, dt, {"pageviews": pv})
    total["pageviews"] += pv
exp["fact_rows"]["fct_ga4__page_daily"] = len(groups)
exp["totals_by_date"]["fct_ga4__page_daily"] = finish(by_date)
exp["totals_project"]["fct_ga4__page_daily"] = finish({"all": total})["all"]
exp["extra"]["ga4_pages_collapse"] = {"natural_keys": len(best), "fact_keys": len(groups),
                                       "distinct_raw_paths": len({k[2] for k in best}),
                                       "distinct_normalised_urls": len({u for _, u in groups})}


# ---------------- GSC ----------------
def gsc(table, stg, fact, dimfn, factkey):
    raw = rows_of(table)
    best = latest(raw, lambda d: (d["date"], d["search_type"]) + dimfn(d))
    exp["staging_rows"][stg] = len(best)
    groups, by_date, total = {}, {}, collections.defaultdict(float)
    for k, r in best.items():
        d = r["d"]
        imp = int(d["impressions"])
        has = "position" in d
        v = {"clicks": int(d["clicks"]), "impressions": imp,
             "sum_position": (float(d["position"]) * imp) if has else 0.0,
             "position_impressions": imp if has else 0}
        gk = factkey(k)
        a = groups.setdefault(gk, collections.defaultdict(float))
        for m, x in v.items():
            a[m] += x
    for gk, v in groups.items():
        add(by_date, f"{gk[0]}|{gk[1]}", v)  # date|search_type
        for m, x in v.items():
            total[m] += x
    exp["fact_rows"][fact] = len(groups)
    exp["totals_by_date"][fact] = finish(by_date)
    exp["totals_project"][fact] = finish({"all": total})["all"]


gsc("GSC_PA_search_analytics_by_date", "stg_gsc__search_by_date", "fct_gsc__site_daily", lambda d: (), lambda k: k)
gsc("GSC_PA_search_analytics_by_page", "stg_gsc__search_by_page", "fct_gsc__page_daily",
    lambda d: (d["page"],), lambda k: (k[0], k[1], norm_url(k[2])))
gsc("GSC_PA_search_analytics_by_device", "stg_gsc__search_by_device", "fct_gsc__device_daily",
    lambda d: (d["device"].lower(),), lambda k: k)
gsc("GSC_PA_search_analytics_by_query", "stg_gsc__search_by_query", "fct_gsc__query_daily", lambda d: (d["query"],), lambda k: k)

# ---------------- Lighthouse ----------------
raw = rows_of("Lighthouse_PA_lighthouse_report")
best = latest(raw, lambda d: (d["fetch_date"], norm_url(d["url"]), d["strategy"].lower()))
exp["staging_rows"]["stg_lighthouse__report"] = len(best)
exp["fact_rows"]["fct_lighthouse__report_daily"] = len(best)
by_date, total = {}, collections.defaultdict(float)
for k, r in best.items():
    d = r["d"]
    v = {"runs": 1, "performance_score": float(d["performance_score"]), "accessibility_score": float(d["accessibility_score"]),
         "best_practices_score": float(d["best_practices_score"]), "seo_score": float(d["seo_score"]),
         "first_contentful_paint_ms": parse_ms(d["first_contentful_paint"]), "speed_index_ms": parse_ms(d["speed_index"]),
         "largest_contentful_paint_ms": parse_ms(d["largest_contentful_paint"]), "time_to_interactive_ms": parse_ms(d["time_to_interactive"]),
         "total_blocking_time_ms": parse_ms(d["total_blocking_time"]), "cumulative_layout_shift": float(d["cumulative_layout_shift"])}
    add(by_date, f"{k[0]}|{k[2]}", v)
    for m, x in v.items():
        total[m] += x
exp["totals_by_date"]["fct_lighthouse__report_daily"] = finish(by_date)
exp["totals_project"]["fct_lighthouse__report_daily"] = finish({"all": total})["all"]

raw = rows_of("Lighthouse_PA_lighthouse_audit")
best = latest(raw, lambda d: (d["fetch_date"], norm_url(d["url"]), d["strategy"].lower(), d["id"]))
exp["staging_rows"]["stg_lighthouse__audit"] = len(best)
exp["fact_rows"]["fct_lighthouse__audit_daily"] = len(best)
by_date, total = {}, collections.defaultdict(float)
for k, r in best.items():
    sc = r["d"].get("score")
    score = float(sc) if sc is not None else -1.0
    v = {"audits": 1, "score": score, "audit_failed": 1 if 0 <= score < 1 else 0, "audit_scored": 1 if score >= 0 else 0}
    add(by_date, f"{k[0]}|{k[2]}", v)
    for m, x in v.items():
        total[m] += x
exp["totals_by_date"]["fct_lighthouse__audit_daily"] = finish(by_date)
exp["totals_project"]["fct_lighthouse__audit_daily"] = finish({"all": total})["all"]

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "expected.json")
json.dump(exp, open(out, "w", encoding="utf-8"), indent=1, sort_keys=True)
print("wrote", out)
print({k: v for k, v in exp["staging_rows"].items()})
print("restated GA4 keys:", len(exp["extra"]["ga4_traffic_restated"]))
