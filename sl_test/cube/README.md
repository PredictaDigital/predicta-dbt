# sl_test Cube model (SEO)

Cube Core semantic layer over the `sl_test` ClickHouse database (GA4, Search Console,
Lighthouse). Widgets and chat read only the **views**; source and dimension cubes are not public.

    sl_test.fct_* / dim_*  ->  source cubes (hidden)  ->  views (public)

## Views (the public surface)
| View | Built on | Use |
|---|---|---|
| `seo_traffic` | `ga4_traffic` + channel, project, date | GA4 sessions, engagement, users by day / source / medium / channel group |
| `seo_pages` | `ga4_page` + page | GA4 page views per page |
| `seo_search_site` | `gsc_site` | Search Console clicks, impressions, CTR, position, whole site |
| `seo_search_pages` | `gsc_page` + page | ... per page |
| `seo_search_devices` | `gsc_device` + device | ... per device |
| `seo_search_queries` | `gsc_query` | ... per search query |
| `seo_lighthouse_runs` | `lighthouse_report` + page | Lighthouse scores and core web vitals (averages) |
| `seo_lighthouse_audits` | `lighthouse_audit` + audit + page | Failed and scored audits |

Rules baked into the model: measures are additive (`sum`); ratios (`gsc_ctr`, `gsc_avg_position`,
`ga4_engagement_rate`, `lh_avg_*`) are calculated measures; non-comparable measures keep their
source in the name (`ga4_sessions` is not `gsc_clicks`); joins go from fact cubes to dimension
cubes only; every view carries `project_id` and `customer_id`.

## Isolation
`cube.js` `queryRewrite` adds `project_id IN token.project_ids` and `customer_id = token.customer_id`
to every view in every query, and refuses a token without both claims. There is one shared set of
rollups with `project_id` as a dimension; no per-project app id or rollup.

## Run locally (no secrets in files)
Set these in your shell, then `npm install` and `npx cubejs-server`:

    CUBEJS_DB_TYPE=clickhouse  CUBEJS_DB_HOST=<clickhouse host>  CUBEJS_DB_PORT=443  CUBEJS_DB_SSL=true
    CUBEJS_DB_NAME=sl_test     CUBEJS_DB_USER=<read-only user>   CUBEJS_DB_PASS=<password>
    CUBEJS_API_SECRET=<signing secret>   PORT=4000   CUBEJS_DEV_MODE=false

The ClickHouse user needs `SELECT` on `sl_test.*` only. Rollups need a Cube Store service
(`CUBEJS_CUBESTORE_HOST`, `CUBEJS_EXTERNAL_DEFAULT=true`, `CUBEJS_REFRESH_WORKER=true`). On the
Windows machine used for this test the standalone Cube Store could not complete a rollup build
(file listing error after upload), so the checks ran against a copy of this model with the
`pre_aggregations` blocks removed. Verify rollup builds in your real environment.

Checks: `python sl_test/tests/run_cube_checks.py` (needs `CUBEJS_API_SECRET` and the `CH_*` variables).
