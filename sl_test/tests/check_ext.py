"""Independent checks (E1-E5) for the SMM, PPC and extra SEO facts.

Recomputes per-day totals straight from the original Airbyte CSV files in S3 with plain
Python (latest _airbyte_extracted_at wins per natural key, both stream layouts for the
Facebook and Instagram insights, the same date rules) and compares them with the ClickHouse
fact tables. No ClickHouse is used to produce the expected values.

Needs AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY (S3) and CH_HOST, CH_PORT, CH_SECURE,
CH_DBT_USER, CH_DBT_PASSWORD (ClickHouse). Nothing secret is printed. Exits non-zero on failure.
"""
import base64
import collections
import csv
import io
import json
import os
import re
import sys
import urllib.request
from datetime import datetime, timezone

import boto3

csv.field_size_limit(sys.maxsize)
BUCKET, PREFIX = "pa-poc-airbyte-data", "airbyte/raw/airbyte_raw/"
s3 = boto3.client("s3", aws_access_key_id=os.environ["AWS_ACCESS_KEY_ID"], aws_secret_access_key=os.environ["AWS_SECRET_ACCESS_KEY"], region_name="us-east-1")
URL = f"{'https' if os.environ.get('CH_SECURE', 'True').lower() == 'true' else 'http'}://{os.environ['CH_HOST']}:{os.environ.get('CH_PORT', '443')}/"
AUTH = "Basic " + base64.b64encode(f"{os.environ['CH_DBT_USER']}:{os.environ['CH_DBT_PASSWORD']}".encode()).decode()
RESULTS = []


def ch(sql):
    req = urllib.request.Request(URL, data=(sql + " FORMAT JSONCompact").encode(), headers={"Authorization": AUTH})
    return json.loads(urllib.request.urlopen(req, timeout=300).read().decode())["data"]


def rows_of(table):
    out = []
    for p in s3.get_paginator("list_objects_v2").paginate(Bucket=BUCKET, Prefix=f"{PREFIX}{table}/"):
        for o in p.get("Contents", []):
            body = s3.get_object(Bucket=BUCKET, Key=o["Key"])["Body"].read().decode()
            for i, r in enumerate(csv.DictReader(io.StringIO(body))):
                out.append({"d": json.loads(r["_airbyte_data"] or "{}"), "ext": int(r["_airbyte_extracted_at"] or 0), "file": o["Key"], "i": i})
    return out


def latest(rows, keyfn):
    best = {}
    for r in rows:
        k = keyfn(r)
        if k not in best or (r["ext"], r["file"], r["i"]) > (best[k]["ext"], best[k]["file"], best[k]["i"]):
            best[k] = r
    return best


def ext_date(ms):
    return datetime.fromtimestamp(int(ms) / 1000, tz=timezone.utc).date().isoformat()


def metric_value(v):
    """Same rule as the dbt macro: number, quoted number, or object (use 'total' if present, else sum)."""
    if isinstance(v, bool): return float(v)
    if isinstance(v, (int, float)): return float(v)
    if isinstance(v, dict):
        if "total" in v: return float(v["total"] or 0)
        return float(sum(float(x or 0) for x in v.values() if isinstance(x, (int, float))))
    try: return float(str(v).strip('"'))
    except ValueError: return 0.0


def close(a, b, tol=1e-6): return abs(float(a) - float(b)) <= tol * max(1.0, abs(float(b)))


def compare(cid, what, expected_by_date, fact, measures):
    """expected_by_date: {date: {measure: value}}. Compares per-day sums of the fact."""
    sel = ", ".join(f"sum({m})" for m in measures)
    got = {r[0]: r[1:] for r in ch(f"select toString(date), {sel} from sl_test.{fact} group by date")}
    bad, n = [], 0
    for d in sorted(set(expected_by_date) | set(got)):
        e = expected_by_date.get(d)
        g = got.get(d)
        if e is None or g is None:
            if (e is None and any(float(x or 0) != 0 for x in (g or []))) or (g is None and any(v != 0 for v in e.values())):
                bad.append((d, "missing in " + ("expected" if e is None else "fact")))
            continue
        for i, m in enumerate(measures):
            n += 1
            want = e.get(m, e.get("all", 0))   # a "+"-joined measure is the sum of several metric columns
            if not close(g[i], want):
                bad.append((d, m[:30], want, g[i]))
    RESULTS.append((cid, what, f"{n} daily totals match", "all match" if not bad else f"{len(bad)} differ, first {bad[:2]}", not bad))


def add(acc, d, vals):
    a = acc.setdefault(d, collections.defaultdict(float))
    for k, v in vals.items(): a[k] += v


GA_M = ["impressions", "clicks", "cost_micros", "conversions", "conversions_value"]


def googleads():
    specs = [("GoogleAds_PA_performance", "fct_googleads__performance_daily", lambda d: (d["campaign.id"], d["ad_group.id"], str(d.get("segments.ad_network_type", "")).lower())),
             ("GoogleAds_PA_ad_performance", "fct_googleads__ad_daily", lambda d: (d["campaign.id"], d["ad_group.id"], d["ad_group_ad.ad.id"], str(d.get("segments.device", "")).lower(), str(d.get("segments.ad_network_type", "")).lower())),
             ("GoogleAds_PA_keyword_performance", "fct_googleads__keyword_daily", lambda d: (d["campaign.id"], d["ad_group.id"], d["ad_group_criterion.criterion_id"])),
             ("GoogleAds_PA_search_term_performance", "fct_googleads__search_term_daily", lambda d: (d["campaign.id"], d["ad_group.id"], d["search_term_view.search_term"], d.get("segments.search_term_match_type", ""))),
             ("GoogleAds_PA_device_performance", "fct_googleads__device_daily", lambda d: (d["campaign.id"], d["ad_group.id"], str(d.get("segments.device", "")).lower())),
             ("GoogleAds_PA_age_performance", "fct_googleads__age_daily", lambda d: (d["campaign.id"], d["ad_group.id"], d.get("ad_group_criterion.age_range.type", ""))),
             ("GoogleAds_PA_gender_performance", "fct_googleads__gender_daily", lambda d: (d["campaign.id"], d["ad_group.id"], d.get("ad_group_criterion.gender.type", ""))),
             ("GoogleAds_PA_location_performance", "fct_googleads__location_daily", lambda d: (d["campaign.id"], d["ad_group.id"], d.get("geographic_view.country_criterion_id", ""), d.get("geographic_view.location_type", ""), d.get("segments.geo_target_region", ""), d.get("segments.geo_target_city", "")))]
    for table, fact, keyfn in specs:
        best = latest(rows_of(table), lambda r: (r["d"]["segments.date"],) + tuple(str(x) for x in keyfn(r["d"])))
        acc = {}
        for k, r in best.items():
            d = r["d"]
            add(acc, k[0], {"impressions": d.get("metrics.impressions", 0), "clicks": d.get("metrics.clicks", 0), "cost_micros": d.get("metrics.cost_micros", 0),
                            "conversions": d.get("metrics.conversions", 0), "conversions_value": d.get("metrics.conversions_value", 0)})
        compare("E1", f"Google Ads {fact}: daily impressions, clicks, cost, conversions", acc, fact, GA_M)


def gsc_new():
    GM = ["clicks", "impressions"]
    best = latest(rows_of("GSC_PA_search_analytics_all_fields"), lambda r: tuple(str(r["d"].get(k, "")).lower() if k in ("country", "device") else r["d"].get(k, "") for k in ("date", "search_type", "country", "device", "query", "page")))
    acc = {}
    for k, r in best.items(): add(acc, k[0], {"clicks": int(r["d"]["clicks"]), "impressions": int(r["d"]["impressions"])})
    compare("E2", "Search Console combined report fct_gsc__search_daily: daily clicks and impressions", acc, "fct_gsc__search_daily", GM)
    best = latest(rows_of("GSC_PA_search_analytics_by_country"), lambda r: (r["d"]["date"], r["d"]["search_type"], str(r["d"]["country"]).lower()))
    acc = {}
    for k, r in best.items(): add(acc, k[0], {"clicks": int(r["d"]["clicks"]), "impressions": int(r["d"]["impressions"])})
    compare("E2", "Search Console by country fct_gsc__country_daily: daily clicks and impressions", acc, "fct_gsc__country_daily", GM)
    norm = lambda u: re.sub(r"/+$", "", re.sub(r"[?].*$", "", re.sub(r"[#].*$", "", u.strip().lower())))
    best = latest(rows_of("GSC_PA_url_inspection"), lambda r: (r["d"]["inspected_date"], norm(r["d"]["inspect_url"])))
    acc = {}
    for k, r in best.items(): add(acc, k[0], {"inspections": 1, "passed": 1 if r["d"].get("verdict") == "PASS" else 0})
    compare("E2", "Search Console URL inspections fct_gsc__url_inspection_daily: daily inspections and passes", acc, "fct_gsc__url_inspection_daily", ["inspections", "passed"])


def facebook():
    # page snapshots
    best = latest(rows_of("Facebook_PA_page"), lambda r: (r["d"].get("synced_date") or ext_date(r["ext"]),))
    acc = {k[0]: {"fan_count": int(r["d"].get("fan_count", 0)), "followers_count": int(r["d"].get("followers_count", 0))} for k, r in best.items()}
    compare("E3", "Facebook page fct_facebook__page_daily: daily fans and followers", acc, "fct_facebook__page_daily", ["fan_count", "followers_count"])
    # page insights: both layouts
    PM = ["page_media_view", "page_views_total", "page_follows", "page_video_views", "page_video_views_paid", "page_video_views_organic", "page_video_views_unique", "page_video_view_time",
          "page_video_views_click_to_play", "page_total_actions", "page_post_engagements", "page_daily_follows", "page_daily_follows_unique", "page_daily_unfollows_unique",
          "page_total_media_view_unique", "page_fan_adds_by_paid_non_paid_unique", "page_lifetime_engaged_followers_unique"]
    items = []
    for r in rows_of("Facebook_PA_page_insights"):
        d = r["d"]
        if "metric" in d:
            items.append({**r, "k": (d["end_time"][:10], d["metric"]), "v": metric_value(d.get("value"))})
        else:
            for e in d.get("values", []):
                items.append({**r, "k": (e["end_time"][:10], d["name"]), "v": metric_value(e.get("value"))})
    best = latest(items, lambda r: r["k"])
    acc = {}
    for (dt, m), r in best.items():
        if m in PM: add(acc, dt, {"all": r["v"]})
    compare("E3", "Facebook page insights fct_facebook__page_insights_daily: daily sum of all metrics", acc, "fct_facebook__page_insights_daily", ["+".join(PM)])
    # post insights
    POST = ["post_media_view", "post_total_media_view_unique", "post_clicks", "post_video_views", "post_video_views_unique", "post_video_complete_views_30s",
            "post_clicks_by_type", "post_activity_by_action_type", "post_reactions_by_type_total"]
    items = []
    for r in rows_of("Facebook_PA_post_insights"):
        d = r["d"]
        if "metric" in d:
            items.append({**r, "k": (d.get("synced_date") or ext_date(r["ext"]), d["post_id"], d["metric"]), "v": metric_value(d.get("value"))})
        else:
            vals = d.get("values", [])
            items.append({**r, "k": (ext_date(r["ext"]), d["id"].split("/insights/")[0], d["name"]), "v": metric_value(vals[0].get("value")) if vals else 0.0})
    best = latest(items, lambda r: r["k"])
    acc = {}
    for (dt, pid, m), r in best.items():
        if m in POST: add(acc, dt, {"all": r["v"]})
    compare("E3", "Facebook post insights fct_facebook__post_insights_snapshot: daily sum of all metrics", acc, "fct_facebook__post_insights_snapshot", ["+".join(POST)])


def instagram():
    AM = ["reach", "views", "likes", "comments", "saves", "shares", "reposts", "replies", "profile_views", "accounts_engaged", "website_clicks", "profile_links_taps", "total_interactions"]
    best = latest(rows_of("Instagram_PA_account_insights"), lambda r: (r["d"]["date"][:10], r["d"]["metric"]))
    acc = {}
    for (dt, m), r in best.items():
        if m in AM: add(acc, dt, {"all": metric_value(r["d"].get("value"))})
    compare("E4", "Instagram account insights fct_instagram__account_daily: daily sum of all metrics", acc, "fct_instagram__account_daily", ["+".join(AM)])
    MM = ["reach", "views", "likes", "comments", "shares", "saved", "follows", "reposts", "profile_activity", "profile_visits", "total_interactions"]
    items = []
    for r in rows_of("Instagram_PA_media_insights"):
        d = r["d"]
        if "metric" in d:
            items.append({**r, "k": (d.get("synced_date") or ext_date(r["ext"]), d["media_id"], d["metric"]), "v": metric_value(d.get("value"))})
        else:
            for m in ("reach", "saved", "likes", "comments", "shares", "follows", "profile_visits"):
                items.append({**r, "k": (ext_date(r["ext"]), d["id"], m), "v": float(d.get(m, 0) or 0)})
    best = latest(items, lambda r: r["k"])
    acc = {}
    for (dt, mid, m), r in best.items():
        if m in MM: add(acc, dt, {"all": r["v"]})
    compare("E4", "Instagram media insights fct_instagram__media_insights_snapshot: daily sum of all metrics", acc, "fct_instagram__media_insights_snapshot", ["+".join(MM)])
    best = latest(rows_of("Instagram_PA_reach_by_follow_type"), lambda r: (r["d"]["date"][:10], str(r["d"]["follow_type"]).lower()))
    acc = {}
    for (dt, ft), r in best.items(): add(acc, dt, {"reach": float(r["d"]["value"])})
    compare("E4", "Instagram reach by follow type: daily reach", acc, "fct_instagram__reach_by_follow_type_daily", ["reach"])
    best = latest(rows_of("Instagram_PA_views_by_media_type"), lambda r: (r["d"]["date"][:10], str(r["d"]["media_product_type"]).lower()))
    acc = {}
    for (dt, ft), r in best.items(): add(acc, dt, {"views": float(r["d"]["value"])})
    compare("E4", "Instagram views by media type: daily views", acc, "fct_instagram__views_by_media_type_daily", ["views"])


def linkedin():
    day = lambda d: ext_date(int(d["timeRangeStart"]))
    best = latest(rows_of("LinkedIn_PA_share_statistics_time_bound"), lambda r: (day(r["d"]),))
    acc = {}
    for k, r in best.items():
        s = r["d"]["totalShareStatistics"]
        add(acc, k[0], {"impressions": s.get("impressionCount", 0), "clicks": s.get("clickCount", 0), "likes": s.get("likeCount", 0), "comments": s.get("commentCount", 0), "shares": s.get("shareCount", 0)})
    compare("E5", "LinkedIn share statistics fct_linkedin__share_daily: daily impressions, clicks, likes, comments, shares", acc, "fct_linkedin__share_daily", ["impressions", "clicks", "likes", "comments", "shares"])
    best = latest(rows_of("LinkedIn_PA_follower_statistics_time_bound"), lambda r: (day(r["d"]),))
    acc = {k[0]: {"organic_follower_gain": r["d"]["followerGains"].get("organicFollowerGain", 0), "paid_follower_gain": r["d"]["followerGains"].get("paidFollowerGain", 0)} for k, r in best.items()}
    compare("E5", "LinkedIn follower gains fct_linkedin__follower_gains_daily: daily organic and paid gains", acc, "fct_linkedin__follower_gains_daily", ["organic_follower_gain", "paid_follower_gain"])


if __name__ == "__main__":
    for f in (googleads, gsc_new, facebook, instagram, linkedin):
        try:
            f()
        except Exception as e:
            RESULTS.append((f.__name__.upper(), "check could not run", "-", f"{type(e).__name__}: {e}"[:220], False))
    print(f"{'Id':<4} | {'Check':<108} | Result | Expected -> Actual")
    for r in RESULTS:
        print(f"{r[0]:<4} | {r[1][:108]:<108} | {'PASS' if r[4] else 'FAIL':<6} | {r[2][:40]} -> {r[3][:170]}")
    failed = [r for r in RESULTS if not r[4]]
    print(f"\n{len(RESULTS)} checks: {len(RESULTS) - len(failed)} pass, {len(failed)} fail")
    sys.exit(1 if failed else 0)
