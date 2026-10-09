# Build from the repo root:  docker build -t <registry>/predicta/dbt-runner:0.1.0 .
FROM python:3.12-slim

# git is needed only at build time, for `dbt deps` (packages come from GitHub).
RUN apt-get update && apt-get install -y --no-install-recommends git \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY orchestration/requirements.txt orchestration/requirements.txt
RUN pip install --no-cache-dir -r orchestration/requirements.txt

COPY predicta_dbt/ predicta_dbt/
COPY orchestration/ orchestration/

# Bake dependencies into the image so runs need no network access to GitHub.
RUN cd predicta_dbt && dbt deps

ENV DBT_PROJECT_DIR=/app/predicta_dbt \
    DBT_PROFILES_DIR=/app/predicta_dbt \
    PYTHONPATH=/app

# dbt writes target/ and logs/ here; give the non-root user ownership.
RUN useradd -u 10001 -m dbt && chown -R dbt /app
USER 10001
