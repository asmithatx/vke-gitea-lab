# RB-04 — LoadBalancer Service stuck at EXTERNAL-IP <pending>

| | |
|---|---|
| **Cluster** | kubeadm (cannot happen on VKE) |
| **Layer** | Vultr integration (CCM) |
| **Concept demonstrated** | `type: LoadBalancer` does nothing by itself; the Cloud Controller Manager is what turns it into a cloud resource |
| **Severity** | P2 |

## Symptom
"I created a LoadBalancer service like the docs say but EXTERNAL-IP has said `<pending>` for an hour."

## Reproduce
Deploy Gitea (05-gitea.yml) **before** running 03-vultr-integrations.yml. Or, on a working cluster:
```
kubectl -n kube-system scale deploy/vultr-ccm --replicas=0
kubectl -n gitea delete svc gitea-http && helm -n gitea upgrade gitea gitea-charts/gitea --reuse-values
```

## Diagnose
```
kubectl -n gitea get svc                                      # 01-symptom
kubectl -n gitea describe svc gitea-http | sed -n '/Events/,$p'   # 02-events (nothing — no controller is acting)
kubectl get nodes -o json | jq '.items[].spec.taints'          # 03-taints (uninitialized taint present if CCM never ran)
kubectl -n kube-system get deploy,pods -l app.kubernetes.io/name=vultr-ccm   # 04-ccm-missing
kubectl -n kube-system logs deploy/vultr-ccm --tail=50         # 05-ccm-logs (if it exists: API key / region errors show here)
kubectl -n kube-system get secret vultr-ccm -o jsonpath='{.data.region}' | base64 -d   # 06-secret
```

## Root cause
No CCM, or CCM can't authenticate to Vultr's API. The Service object is valid Kubernetes; nothing in-cluster knows how to provision a Vultr Load Balancer.

## Fix
```
ansible-playbook 03-vultr-integrations.yml    # or scale the deployment back up
kubectl -n gitea get svc -w                    # 07-fixed (EXTERNAL-IP populates within ~1–2 min)
vultr-cli load-balancer list                   # 08-vultr-side
```

## Variant (RB-04b) — LB exists, 0 healthy backends, kubeadm only
Firewall group missing the NodePort range (30000–32767). `kubectl get svc` shows the NodePort; `vultr-cli firewall rule list` shows no rule for it. VKE opens this automatically.

## Prevention / what I'd tell the customer
On self-managed clusters, verify `kubectl -n kube-system get pods | grep ccm` before anything else when a LoadBalancer or node-init issue comes in. On VKE this class of ticket doesn't exist — that's a selling point worth saying out loud.

## Evidence captured
- [ ] 01, 03, 04, 05, 07, 08
