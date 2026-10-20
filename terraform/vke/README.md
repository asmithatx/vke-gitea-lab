# Gitea on VKE — Terraform sketch

Stands up a 3-node Vultr Kubernetes Engine cluster, a Vultr Managed PostgreSQL
instance, and deploys Gitea via the official Helm chart with:

- external Postgres (Managed DB) — `gitea` db + user created by Terraform
- in-cluster Valkey for cache/session
- 10 GiB `vultr-block-storage` PVC (RWO, by design)
- two Vultr Load Balancers: HTTP (port 80, HTTP health check on `/api/healthz`)
  and SSH (port 22, TCP health check)
- Calico NetworkPolicies: default-deny ingress + explicit allows
- Gitea `/metrics` enabled, ServiceMonitor left off until kube-prometheus-stack lands

## Apply order

The Managed DB trusted-IP list needs the node IPs, which don't exist until the
cluster does, so this is a two-step apply on first run:

```bash
export VULTR_API_KEY=...
terraform init
terraform apply -target=vultr_kubernetes.lab -target=vultr_database.pg
terraform output -raw kubeconfig > ~/.kube/gitea-lab
export KUBECONFIG=~/.kube/gitea-lab
kubectl get nodes -o wide          # collect EXTERNAL-IP values
# put them in terraform.tfvars: pg_trusted_ips = ["1.2.3.4/32", ...]
terraform apply
kubectl -n gitea get svc           # LB IPs appear here once the CCM finishes
```

Alternatively, leave `pg_trusted_ips` empty, run one full apply, and watch
Gitea fail to reach Postgres — that's the first runbook.

## Things to verify before trusting this

This is a sketch, not a tested module. Specifically check:

- `k8s_version` against `vultr-cli kubernetes versions` (format is `v1.xx.y+N`)
- `pg_plan` against `vultr-cli database plans` — plan IDs change
- Gitea chart version (`helm search repo gitea-charts/gitea --versions`) and
  whether the `valkey` / `valkey-cluster` subchart keys match that version
- That `GITEA__database__*` env vars injected via `extraEnvFrom` are honored
  by the chart's init container (they are for current chart versions; the
  chart's `gitea.config` and env-based config merge at startup)
- Whether the Managed DB can be attached to the cluster's VPC instead of
  using public host + trusted IPs (cleaner, and a better production answer)

## Teardown

```bash
terraform destroy
```

`terraform destroy` won't remove LBs the CCM created from Services unless the
Services are deleted first (Helm uninstall handles that). If you see orphaned
LBs or Block Storage volumes in the console after destroy, that's runbook
material too.
