# RB-05 — PVC stuck Pending

| | |
|---|---|
| **Cluster** | both (different causes) |
| **Layer** | Storage (CSI) |
| **Concept demonstrated** | Dynamic provisioning = StorageClass → CSI driver → cloud API; `describe pvc` tells you which link broke |
| **Severity** | P2 |

## Symptom
"Prometheus / Gitea pod is Pending and the PVC never binds."

## Reproduce
- **kubeadm:** run 04-monitoring.yml before 03-vultr-integrations.yml (no CSI → no StorageClass).
- **VKE:** `persistence.size: 5Gi` (below the NVMe Block Storage minimum), or a bogus `storageClassName`.

## Diagnose
```
kubectl -n monitoring get pvc                                 # 01-symptom
kubectl -n monitoring describe pvc <name> | sed -n '/Events/,$p'   # 02-events — THE diagnostic. Read the message:
#   "storageclass.storage.k8s.io "vultr-block-storage" not found"  → CSI/SC missing (kubeadm)
#   "failed to provision volume ... minimum size"                  → size below Vultr minimum (VKE)
#   "waiting for a volume to be created ..." forever               → CSI controller down / API key bad
kubectl get sc                                                 # 03-storageclasses
kubectl -n kube-system get pods | grep csi                     # 04-csi-pods
kubectl -n kube-system logs deploy/csi-vultr-controller -c csi-vultr-plugin --tail=50   # 05-csi-logs
vultr-cli block-storage list                                   # 06-vultr-side
```

## Root cause
Pick from the event message. The common thread: the PVC is a request, the StorageClass names who fulfils it, and the CSI driver is the thing that actually calls Vultr.

## Fix
- kubeadm: `ansible-playbook 03-vultr-integrations.yml`; PVC binds on its own (no pod restart needed).
- VKE size: bump to `10Gi`; delete and recreate the PVC (size on a pending PVC can be edited, but recreating is cleaner for the write-up).
```
kubectl -n monitoring get pvc -w                               # 07-fixed
```

## Prevention / what I'd tell the customer
`kubectl describe pvc` first, always. Then check the StorageClass exists and the CSI controller pod is healthy. Know your provider's minimum volume size.

## Evidence captured
- [ ] 01, 02 (both variants' messages), 03, 05, 07
