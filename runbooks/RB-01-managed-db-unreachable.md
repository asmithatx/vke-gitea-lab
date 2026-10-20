# RB-01 — Gitea can't reach Vultr Managed PostgreSQL

| | |
|---|---|
| **Cluster** | VKE |
| **Layer** | Vultr integration / Network |
| **Concept demonstrated** | External managed services have their own allow-lists; a pod's egress path and the DB's trusted-IP list must agree |
| **Severity** | P1 — app down |

## Symptom
"Gitea pod is CrashLoopBackOff after deploy. Logs say `dial tcp ...:16751: i/o timeout`" (or `connection refused` / `no pg_hba.conf entry`).

## Reproduce
First `terraform apply` with `pg_trusted_ips = []` (the default in variables.tf).

## Diagnose
```
kubectl -n gitea get pods                                   # 01-symptom
kubectl -n gitea logs deploy/gitea -c configure-gitea       # 02-init-logs (init container does the DB migration)
kubectl -n gitea describe pod -l app.kubernetes.io/name=gitea | sed -n '/Events/,$p'   # 03-events
kubectl -n gitea get secret gitea-db -o jsonpath='{.data.GITEA__database__HOST}' | base64 -d  # 04-config
kubectl -n gitea run pgtest --rm -it --image=postgres:16 -- \
  psql "postgresql://gitea:<pw>@<host>:<port>/gitea?sslmode=require" -c 'select 1'  # 05-reachability from inside the cluster
vultr-cli database get <db-id> | grep -i trusted               # 06-db-side
kubectl get nodes -o wide                                      # 07-node-egress-ips
```
Step 05 isolates "is it Gitea" from "is it the network". Step 06+07 show the egress IPs aren't trusted.

## Root cause
Vultr Managed Databases reject connections from IPs not in `trusted_ips`. VKE nodes egress from their public IPs, which didn't exist when the DB was created.

## Fix
```
terraform apply -var='pg_trusted_ips=["<node1>/32","<node2>/32","<node3>/32"]'
kubectl -n gitea rollout restart deploy/gitea
kubectl -n gitea get pods -w                                   # 08-fixed
```

## Prevention / what I'd tell the customer
Attach the DB and cluster to the same VPC and use the private host, or trust the node pool's public IPs and remember the autoscaler will add nodes you haven't trusted yet. Treat `trusted_ips` as part of the cluster's definition, not the DB's.

## Evidence captured
- [ ] 01-symptom, 02-init-logs, 03-events, 05-reachability, 06-db-side, 08-fixed
