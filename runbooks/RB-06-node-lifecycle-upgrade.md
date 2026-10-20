# RB-06 — Node pool scaling and cluster upgrade (VKE vs kubeadm)

| | |
|---|---|
| **Cluster** | both |
| **Layer** | Compute / Control plane |
| **Concept demonstrated** | Managed lifecycle vs manual: node pools, cordon/drain, PodDisruptionBudgets, control-plane upgrade ordering |
| **Severity** | n/a — planned change, but produces real tickets when it goes wrong |

This one is less "break/fix" and more "do the same operation both ways and capture the difference".

## Part A — add a node
**VKE**
```
terraform apply -var=node_count=4            # 01-vke-scale (or: edit pool in console)
kubectl get nodes -w                          # 02-vke-node-joins (Ready in ~2–3 min, CCM/CSI already there)
```
**kubeadm**
```
terraform apply -var=worker_count=3           # 03-kubeadm-instance
ansible-playbook 00-common.yml 02-workers.yml --limit <new-host>   # 04-kubeadm-join
kubectl get nodes -o json | jq '.items[-1].spec.taints'            # 05-taint-then-cleared
```
Capture: the kubeadm node is NotReady + tainted until the (already-running) CCM initializes it. Same taint as stage 3, now in the normal workflow.

## Part B — drain a node with a stateful pod on it
```
kubectl -n gitea get pod -o wide              # 06-where-is-gitea
kubectl drain <that-node> --ignore-daemonsets --delete-emptydir-data   # 07-drain
kubectl -n gitea get pod -o wide -w           # 08-reschedule (RWO volume detaches/reattaches — ~30–60s of downtime)
kubectl uncordon <node>
```
Talking point: a PodDisruptionBudget would block this drain; without one, the single replica just goes down. Both correct, different intent.

## Part C — upgrade one minor version
**VKE**
```
terraform apply -var='k8s_version=v1.32.x+1'  # 09-vke-upgrade (or console → Upgrade)
kubectl get nodes -w                          # 10-vke-rolling (Vultr replaces nodes one at a time)
```
**kubeadm** (abbreviated — follow the official kubeadm upgrade doc for the real steps)
```
apt-mark unhold kubeadm && apt install kubeadm=1.32.x-* && apt-mark hold kubeadm
kubeadm upgrade plan                          # 11-upgrade-plan
kubeadm upgrade apply v1.32.x                 # 12-cp-upgrade
# then per worker: drain → upgrade kubelet/kubectl → restart kubelet → uncordon
```
Capture: time taken, number of commands, what the VKE version did to the control plane that you never saw.

## Prevention / what I'd tell the customer
Pin versions in IaC; upgrade one minor at a time; set a PDB on anything with a single replica before touching nodes; on self-managed, the control plane always goes first.

## Evidence captured
- [ ] 02, 05, 08, 10, 11, 12
