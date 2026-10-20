# RB-02 — Second Gitea replica stuck ContainerCreating (Multi-Attach)

| | |
|---|---|
| **Cluster** | both |
| **Layer** | Storage |
| **Concept demonstrated** | PVC access modes; block storage is ReadWriteOnce; scaling a stateful app is an architecture question, not a replica count |
| **Severity** | P3 — no outage, but customer blocked on scaling |

## Symptom
"I scaled Gitea to 2 replicas for HA and the new pod never starts."

## Reproduce
```
kubectl -n gitea scale deploy/gitea --replicas=2
```

## Diagnose
```
kubectl -n gitea get pods -o wide                             # 01-symptom (one Running, one ContainerCreating, different nodes)
kubectl -n gitea describe pod <new-pod> | sed -n '/Events/,$p'  # 02-events → "Multi-Attach error for volume ... Volume is already used by pod(s) ..."
kubectl -n gitea get pvc                                       # 03-pvc (ACCESS MODES = RWO)
kubectl get sc vultr-block-storage -o yaml                     # 04-storageclass (provisioner block.csi.vultr.com)
vultr-cli block-storage list                                   # 05-vultr-side (volume attached to ONE instance)
```
If both pods landed on the same node it would have "worked" — note that: it's the scheduler, not the storage, hiding the problem.

## Root cause
Vultr Block Storage is a block device; it can be attached to one instance at a time. The CSI driver advertises `ReadWriteOnce`. The second pod on a different node asks the CSI to attach the same volume → refused.

## Fix
Pick one, document why:
1. `kubectl -n gitea scale deploy/gitea --replicas=1` — scale the stateless tier later, not this one.
2. Move repo storage to an RWX backend (Vultr File System via NFS, or object storage for LFS) and set `persistence.accessModes: [ReadWriteMany]`.
3. Pin replicas to one node with affinity (demonstrate, then explain why it's a bad answer).
```
kubectl -n gitea get pods -w                                   # 06-fixed
```

## Prevention / what I'd tell the customer
"HA" for Gitea means an HA database and an HA load balancer; the app tier needs shared storage before it can scale horizontally. Check the StorageClass's supported access modes before designing for replicas > 1.

## Evidence captured
- [ ] 01, 02 (the Multi-Attach event is the money shot), 03, 05, 06
