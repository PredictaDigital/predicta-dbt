# SEO dashboard (snapshot)

A single self-contained HTML page (no internet needed) built from the Cube views:
traffic, search, Lighthouse, with a date-range filter, light/dark theme and a table view for every chart.

    dashboard.template.html   the page (HTML, CSS, SVG charts, no libraries)
    build_dashboard.py        queries Cube, embeds the results -> dashboard.html
    dashboard.html            generated snapshot (not committed)

Refresh the numbers (Cube must be running; the secret comes from the environment):

    set CUBEJS_API_SECRET=<signing secret>      # PowerShell: $env:CUBEJS_API_SECRET='...'
    python sl_test/dashboard/build_dashboard.py

Notes: GA4 sessions and Search Console clicks are different measures and are never added together.
Period-over-period changes are hidden when the earlier window is not fully covered by data.
