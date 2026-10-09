"""
Prefect flow that runs dbt for one platform.

Prefect is the ONLY trigger. dbt never schedules itself and no second
scheduler (cron, Airflow) is involved.

    shared build  ->  platform build (dbt build = run + test, in dependency order)
                  ->  (hook) Cube pre-aggregation refresh, e2e checks

Two failure types are kept apart on purpose:
  * DbtBuildError - a model errored or a test failed. The DATA is wrong.
                    Never retried; retrying cannot fix it. Fails the flow loudly.
  * DbtInfraError - dbt could not run (ClickHouse unreachable, timeout, no
                    run_results.json). Retried once.
"""
from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path
from typing import Any

from prefect import flow, get_run_logger, task
from prefect.artifacts import create_markdown_artifact
from prefect.concurrency.sync import concurrency

DBT_DIR = Path(os.environ.get("DBT_PROJECT_DIR", "/app/predicta_dbt"))
DEFAULT_TARGET = os.environ.get("DBT_TARGET", "dev")
# A build must never run unguarded. With strict=True Prefect raises if the
# global concurrency limit does not exist, instead of silently running without
# one. Create it once:  prefect gcl create dbt-ga4 --limit 1
STRICT_CONCURRENCY = os.environ.get("DBT_STRICT_CONCURRENCY", "true").lower() == "true"
# Longer than the slowest expected build, so the slot is not released mid-run.
LEASE_SECONDS = float(os.environ.get("DBT_CONCURRENCY_LEASE_SECONDS", "3600"))

BAD_STATUSES = {"error", "fail", "runtime error"}


class DbtBuildError(RuntimeError):
    """A model failed or a data test failed. Do not retry."""


class DbtInfraError(RuntimeError):
    """dbt could not run to completion. Safe to retry."""


def _retry_only_infra(task, task_run, state) -> bool:  # noqa: ARG001
    try:
        state.result()
    except DbtInfraError:
        return True
    except Exception:
        return False
    return False


def _read_run_results() -> dict[str, Any] | None:
    path = DBT_DIR / "target" / "run_results.json"
    if not path.exists():
        return None
    return json.loads(path.read_text())


def _summarise(results: dict[str, Any]) -> tuple[dict[str, int], list[dict[str, Any]]]:
    counts: dict[str, int] = {}
    bad: list[dict[str, Any]] = []
    for r in results.get("results", []):
        status = str(r.get("status", "unknown")).lower()
        counts[status] = counts.get(status, 0) + 1
        if status in BAD_STATUSES:
            bad.append(
                {
                    "node": r.get("unique_id"),
                    "status": status,
                    "message": (r.get("message") or "")[:300],
                    "failures": r.get("failures"),
                }
            )
    return counts, bad


@task(retries=1, retry_delay_seconds=60, retry_condition_fn=_retry_only_infra)
def dbt_build(
    select: str,
    *,
    target: str = DEFAULT_TARGET,
    full_refresh: bool = False,
    extra_vars: dict[str, Any] | None = None,
) -> dict[str, int]:
    """Run `dbt build --select <select>` and fail loudly on any problem.

    `select` is a dbt selector such as "tag:ga4" or "tag:shared".
    """
    log = get_run_logger()
    lock = f"dbt-{select.removeprefix('tag:')}"  # one dbt run per platform at a time

    cmd = [
        "dbt", "--no-use-colors", "build",
        "--select", select,
        "--target", target,
        "--project-dir", str(DBT_DIR),
        "--profiles-dir", str(DBT_DIR),
        "--fail-fast",
    ]
    if full_refresh:
        cmd.append("--full-refresh")
    if extra_vars:
        cmd += ["--vars", json.dumps(extra_vars)]

    # Remove any stale results so we never read a previous run's file.
    stale = DBT_DIR / "target" / "run_results.json"
    stale.unlink(missing_ok=True)

    with concurrency(lock, occupy=1, strict=STRICT_CONCURRENCY, lease_duration=LEASE_SECONDS):
        log.info("Running: %s", " ".join(cmd))
        proc = subprocess.run(cmd, capture_output=True, text=True)

    log.info(proc.stdout[-4000:])  # tail only; full log is in the pod logs

    results = _read_run_results()
    if results is None:
        raise DbtInfraError(f"dbt produced no run_results.json (exit {proc.returncode}): "
                            f"{(proc.stderr or proc.stdout)[-1500:]}")

    counts, bad = _summarise(results)
    lines = [f"**select:** `{select}`  **target:** `{target}`  **full_refresh:** `{full_refresh}`",
             "", "| status | nodes |", "|---|---|"]
    lines += [f"| {k} | {v} |" for k, v in sorted(counts.items())]
    if bad:
        lines += ["", "### Failures", "", "| node | status | message |", "|---|---|---|"]
        lines += [f"| `{b['node']}` | {b['status']} | {b['message'].replace('|', '/')} |" for b in bad]
    create_markdown_artifact(
        key=f"dbt-{select.removeprefix('tag:')}".replace("_", "-"),
        markdown="\n".join(lines),
        description=f"dbt build results for {select}",
    )

    if bad:
        raise DbtBuildError(
            f"dbt build {select} failed: "
            + "; ".join(f"{b['node']} [{b['status']}] {b['message'][:120]}" for b in bad)
        )
    if proc.returncode != 0:
        raise DbtInfraError(f"dbt exited {proc.returncode} with no failed nodes: {proc.stderr[-1500:]}")

    log.info("dbt build %s OK: %s", select, counts)
    return counts


@task
def dbt_source_freshness(target: str = DEFAULT_TARGET) -> None:
    """Warn (never fail the flow) when raw data is older than the 26 h target."""
    log = get_run_logger()
    proc = subprocess.run(
        ["dbt", "--no-use-colors", "source", "freshness", "--target", target,
         "--project-dir", str(DBT_DIR), "--profiles-dir", str(DBT_DIR)],
        capture_output=True, text=True,
    )
    (log.warning if proc.returncode != 0 else log.info)(proc.stdout[-1500:])


@flow(name="dbt-transform", log_prints=True)
def transform_platform(
    platform: str = "ga4",
    include_shared: bool = True,
    full_refresh: bool = False,
    target: str = DEFAULT_TARGET,
    extra_vars: dict[str, Any] | None = None,
) -> dict[str, dict[str, int]]:
    """Build staging, dimensions and facts for one platform, all tenants at once.

    include_shared: also rebuild dim_date / dim_tenant / dim_channel first.
        True for the PoC. At scale set it False here and run a separate daily
        "shared" deployment, so platform flows never contend over shared tables.
    full_refresh: rebuild incremental facts from scratch. REQUIRED after rows
        are deleted or corrected by removal in raw, because incremental models
        never remove rows whose source disappeared.
    extra_vars: e.g. {"tenant_id": "t_acme"} for a debugging backfill only.
    """
    summary: dict[str, dict[str, int]] = {}
    dbt_source_freshness(target)
    if include_shared:
        summary["shared"] = dbt_build("tag:shared", target=target, full_refresh=full_refresh,
                                      extra_vars=extra_vars)
    summary[platform] = dbt_build(f"tag:{platform}", target=target, full_refresh=full_refresh,
                                  extra_vars=extra_vars)

    # Next hooks (add as the pipeline matures; deliberately not stubbed with
    # invented calls): refresh Cube pre-aggregations for this platform, then
    # run the e2e-validation comparison of ClickHouse vs the Cube API.
    return summary


@flow(name="dbt-shared", log_prints=True)
def refresh_shared(
    full_refresh: bool = False,
    target: str = DEFAULT_TARGET,
) -> dict[str, int]:
    """Rebuild only the shared dimensions (dim_date, dim_tenant, dim_channel).

    Use this once a day at scale, with transform_platform(include_shared=False)
    for every platform, so platform flows never contend over shared tables.
    """
    return dbt_build("tag:shared", target=target, full_refresh=full_refresh)


if __name__ == "__main__":
    transform_platform()
