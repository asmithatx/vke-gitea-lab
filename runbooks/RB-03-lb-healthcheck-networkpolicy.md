# RB-03 — Load Balancer health checks failing; site unreachable

| | |
|---|---|
| **Cluster** | both |
| **Layer** | Network (Calico NetworkPolicy ↔ Vultr LB) |
| **Concept demonstrated** | NetworkPolicy is enforced by the CNI at the pod; LB health checks are just another ingress source and get blocked like any other |
| **Severity** | P1 |

## Symptom
"The Gitea URL times out. The Vultr console shows the Load Balancer with 0 healthy backends."

## Reproduce
```
kubectl -n gitea delete networkpolicy allow-gitea-ingress
```
(default-deny-ingress is still in place)

## Diagnose
```
curl -m 5 -I http://<lb-ip>/                                  # 01-symptom
vultr-cli load-balancer get <lb-id>                            # 02-lb-side (health check status)
kubectl -n gitea get svc gitea-http -o yaml | grep -A8 annotations   # 03-annotations (path/port/protocol sane?)
kubectl -n gitea get endpoints gitea-http                      # 04-endpoints (pod IPs present → Service is fine)
kubectl -n gitea get pods -o wide                              # 05-pods-ready
kubectl -n gitea exec deploy/gitea -- curl -s localhost:3000/api/healthz   # 06-app-healthy-locally
kubectl -n gitea get networkpolicy                             # 07-policies
kubectl run -n default tester --rm -it --image=curlimages/curl -- curl -m 3 http://<gitea-pod-ip>:3000/api/healthz  # 08-cross-ns-blocked
```
Order matters: 03–06 rule out the LB config, the Service, the pod, and the app. 07–08 isolate the policy.

## Root cause
`default-deny-ingress` applies to every pod in the namespace. The LB health check arrives via NodePort → kube-proxy → pod, so from Calico's point of view it's ingress to the Gitea pod, and nothing allows it.

## Fix
```
kubectl apply -f helm/gitea-networkpolicies.yaml   # (or terraform apply on VKE)
watch 'vultr-cli load-balancer get <lb-id>'          # 09-fixed (healthy backends return)
```

## Prevention / what I'd tell the customer
When adding default-deny, write the allow for the LB/health-check path first and apply them together. Health-check "0 healthy" with a reachable pod is almost always policy or firewall, not the app.

## Variant (RB-03b)
Delete `allow-prometheus-scrape` instead → Gitea target goes DOWN in Prometheus but the site stays up. Same mechanism, observability-only impact. Capture `targets` page before/after.

## Evidence captured
- [ ] 01, 02, 04, 06, 08, 09
