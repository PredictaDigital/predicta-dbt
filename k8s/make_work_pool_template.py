"""Build the Prefect Kubernetes work-pool template used by the dbt deployments.

Starts from Prefect's own default template (so it matches your installed
version) and adds two things the default lacks:
  * envFrom -> the Secret created by k8s/external-secret-dbt.yaml
  * nodeSelector -> keeps dbt jobs off the controller node

Usage:
    python k8s/make_work_pool_template.py [pool_label_key=value] > k8s/work-pool-template.json
    prefect work-pool create predicta-k8s --type kubernetes \\
        --base-job-template k8s/work-pool-template.json

Dev note: a node label key holds ONE value. If the single worker node must
host several pools, label by separate keys (e.g. predicta.io/ingest=true)
and pass that here instead of predicta.io/pool=ingest.
"""
import json
import subprocess
import sys

selector = sys.argv[1] if len(sys.argv) > 1 else "predicta.io/pool=ingest"
key, value = selector.split("=", 1)

raw = subprocess.run(
    ["prefect", "work-pool", "get-default-base-job-template", "--type", "kubernetes"],
    capture_output=True, text=True, check=True,
).stdout
# The CLI may print log lines before the JSON; take from the first brace.
template = json.loads(raw[raw.index("{"):])

pod_spec = template["job_configuration"]["job_manifest"]["spec"]["template"]["spec"]
pod_spec["nodeSelector"] = {key: value}
pod_spec["containers"][0]["envFrom"] = [
    {"secretRef": {"name": "dbt-clickhouse-credentials"}}
]

print(json.dumps(template, indent=2))
