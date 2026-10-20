# Gitea on Vultr: VKE vs self-managed — implementation guide

Two clusters, one workload, one observability layer. The VKE cluster is built
entirely from Terraform. The kubeadm cluster is Terraform for the instances
and Ansible for everything above the OS, run one playbook at a time so each
stage is a checkpoint.

Each stage below has three parts: **Do** (commands), **Concept** (what this
stage proves you understand), and **Capture** (the exact evidence to save).
Save evidence as `runbooks/evidence/<stage>/<nn>-<name>.txt` or `.png`; the
write-up at the end is assembled from those files.

A rule for capture: **screenshots for things with state (Vultr console, Grafana,
Prometheus targets), text files for everything `kubectl` prints.** Text is
grep-able, diff-able, and quotable in the write-up.

---

## 0. Prerequisites (workstation)

```
brew install terraform ansible helm kubectl jq vultr/vultr-cli/vultr-cli   # or your distro's equivalents
ansible-galaxy collection install -r ansible/requirements.yml
export VULTR_API_KEY=...
vultr-cli account info                        # proves the key works
```

Verify the pins before the first apply (these drift):
```
vultr-cli kubernetes versions                 # → terraform/vke/variables.tf k8s_version, ansible group_vars k8s_version (same minor!)
vultr-cli database plans | grep -i pg         # → pg_plan
vultr-cli os list | grep -i 'ubuntu 24'       # → terraform/kubeadm os_id
helm search repo gitea-charts/gitea --versions | head -3
helm search repo prometheus-community/kube-prometheus-stack --versions | head -3
helm show values vultr/vultr-ccm              # confirm whether the chart wants the API key as a value or a pre-made secret
```

**Capture:** `00-prereqs/01-versions.txt` — one file with all the above outputs.
Shows you pin versions and check what the platform currently offers before
building. Small thing, strong signal.

---

## 1. VKE — cluster and database

**Do**
```
cd terraform/vke
terraform init
terraform plan -out=stage1.plan -target=vultr_kubernetes.lab -target=vultr_database.pg
terraform apply stage1.plan
terraform output -raw kubeconfig > ~/.kube/gitea-vke && export KUBECONFIG=~/.kube/gitea-vke
kubectl get nodes -o wide
kubectl -n kube-system get pods                # note: no etcd, no apiserver, no scheduler here
kubectl get sc
kubectl get nodes -o json | jq '.items[].spec.taints'
```

**Concept:** what a managed control plane is. `kube-system` shows the CCM, CSI
and Calico pods already running; there is no `etcd` or `kube-apiserver` pod
because they're not on your nodes. `vultr-block-storage` StorageClass exists
before you've done anything. No taints on the nodes.

**Capture**
- `01-vke/01-plan.txt` — `terraform show stage1.plan` (how little it takes)
- `01-vke/02-nodes.txt`, `03-kube-system.txt`, `04-storageclasses.txt`, `05-taints.txt`
- `01-vke/06-console.png` — Vultr console cluster page showing the managed control plane

---

## 2. VKE — first full apply (deliberately broken)

Leave `pg_trusted_ips` empty.

**Do**
```
terraform apply                                # monitoring + gitea + policies
kubectl -n gitea get pods                      # gitea will CrashLoop / init container fails
```
Now work **RB-01** end to end. Then:
```
kubectl get nodes -o wide                      # collect EXTERNAL-IPs
echo 'pg_trusted_ips = ["a.b.c.d/32","..."]' >> terraform.tfvars
terraform apply
kubectl -n gitea get pods,svc,pvc
```

**Concept:** managed services have their own trust boundaries; Terraform
dependency ordering (DB before cluster → IPs unknown); reading an init
container's logs vs the main container's.

**Capture:** everything RB-01 lists, plus `02-vke-gitea/01-services.txt` showing
two Vultr LBs with EXTERNAL-IPs and `02-vke-gitea/02-lb-console.png`.

---

## 3. VKE — verify the workload and the observability layer

**Do**
```
curl -I http://<http-lb-ip>/
ssh -T -p 22 git@<ssh-lb-ip>                   # "Hi there, You've successfully authenticated" after adding a key
terraform output -raw gitea_admin_password     # log in, create one repo, push one commit over SSH
kubectl -n monitoring port-forward svc/kps-grafana 3001:80 &
kubectl -n monitoring port-forward svc/kps-kube-prometheus-stack-prometheus 9090:9090 &
```
Open http://localhost:9090/targets and http://localhost:3001 (admin / `terraform output -raw grafana_admin_password`).

**Concept:** ServiceMonitor → Prometheus Operator → scrape config, and the
`*SelectorNilUsesHelmValues: false` setting that makes it work. On the
targets page, note what's **missing**: `kube-etcd`, `kube-scheduler`,
`kube-controller-manager` targets are DOWN or absent — VKE hides the control
plane from you. Write that down; it's the hinge of the comparison.

**Capture**
- `03-vke-observe/01-targets.png` — Prometheus targets (Gitea UP, control-plane targets absent)
- `03-vke-observe/02-grafana-gitea.png` — the Gitea Lab dashboard with repo count ≥ 1
- `03-vke-observe/03-ssh-push.txt` — the git push output over the SSH LB

---

## 4. VKE — break/fix runbooks

Run, in this order, capturing per the runbook's checklist:
- **RB-02** (scale to 2 → Multi-Attach)
- **RB-03** (delete allow policy → LB 0 healthy) and **RB-03b** (delete Prometheus allow → target DOWN)
- **RB-05**, VKE variant (5Gi PVC → provisioning error)
- **RB-06** Part A (node pool 3→4) and Part B (drain)

**Concept per runbook** is in each file's header. The pattern across all of
them is the thing to make explicit in the write-up: *symptom → isolate the
layer → read the event/log that names the component → fix → prove*.

---

## 5. kubeadm — instances only

**Do**
```
cd terraform/kubeadm
echo 'admin_cidrs = ["<your-ip>/32"]' > terraform.tfvars
terraform init && terraform apply
cat ../../ansible/inventory/hosts.ini
ssh root@<cp-ip> 'kubeadm version; echo no'   # kubeadm: command not found — nothing is installed yet
```

**Concept:** separation of infrastructure (Terraform) from configuration
(Ansible). Terraform output becomes Ansible input via the inventory template.
Also: the firewall rules you had to write (6443, 22, NodePort range) that
`enable_firewall = true` wrote for you on VKE.

**Capture**
- `05-kubeadm-infra/01-apply.txt`, `02-inventory.txt`
- `05-kubeadm-infra/03-firewall.png` — Vultr console firewall group, side-by-side with the VKE-generated one

---

## 6. kubeadm — bootstrap, one playbook at a time

Run each playbook, then capture **before moving on**. The whole point of
this stage is the intermediate states that VKE never lets you see.

### 6a. `ansible-playbook 00-common.yml`
```
ssh root@<cp-ip> 'kubeadm version -o short; containerd --version; swapon --show; cat /etc/default/kubelet'
```
**Concept:** node prerequisites (cgroup driver, swap, br_netfilter) and
`--cloud-provider=external`.
**Capture:** `06a/01-node-prep.txt`

### 6b. `ansible-playbook 01-controlplane.yml`
```
export KUBECONFIG=ansible/artifacts/kubeconfig-kubeadm
kubectl get nodes                               # 1 node, NotReady
kubectl -n kube-system get pods -o wide         # etcd, apiserver, controller-manager, scheduler as STATIC PODS; coredns Pending
kubectl get nodes -o json | jq '.items[].spec.taints'   # uninitialized taint + control-plane taint
kubectl -n calico-system get pods               # Pending (can't schedule on tainted node)
kubectl get sc                                  # No resources found
ssh root@<cp-ip> 'ls /etc/kubernetes/manifests' # the static pod manifests — this IS the control plane
```
**Concept:** what the control plane physically is (static pod manifests on
disk read by kubelet); the `uninitialized` taint and why nothing schedules;
CNI isn't part of Kubernetes.
**Capture:** `06b/01-nodes-notready.txt`, `02-static-pods.txt`, `03-taints.txt`, `04-calico-pending.txt`, `05-no-storageclass.txt`, `06-manifests-dir.txt`
This is the single most important capture set in the whole exercise.

### 6c. `ansible-playbook 02-workers.yml`
```
kubectl get nodes                               # 3 nodes, all NotReady, all tainted
```
**Concept:** join tokens, bootstrap certs, why a node can be "joined" but useless.
**Capture:** `06c/01-three-nodes-notready.txt`

### 6d. Deliberately wrong order: `ansible-playbook 05-gitea.yml` — expect it to time out
```
kubectl -n gitea get svc,pvc,pods
```
Work **RB-04** (svc `<pending>`) and **RB-05** kubeadm variant (PVC
`storageclass not found`) from these symptoms. Don't fix yet.
**Capture:** per the runbooks. The RB-04 `03-taints` and RB-05 `02-events`
outputs are the proof that `type: LoadBalancer` and `PersistentVolumeClaim`
are *requests* with no fulfilment behind them.

### 6e. `ansible-playbook 03-vultr-integrations.yml`
Watch it live in a second terminal:
```
watch -n2 'kubectl get nodes; echo; kubectl get nodes -o json | jq -c ".items[].spec.taints"; echo; kubectl get sc; echo; kubectl -n gitea get svc,pvc'
```
**Concept:** the CCM initializes nodes (taint removed → Calico schedules →
nodes Ready → coredns Running), then fulfils the pending LoadBalancer Service.
The CSI driver registers the StorageClass and the pending PVC binds with no
other action. Everything that was stuck in 6b–6d resolves from two installs.
**Capture:** `06e/01-watch-before.txt`, `02-watch-after.txt` (or a short screen
recording of the watch), `03-ccm-logs.txt` (`kubectl -n kube-system logs deploy/vultr-ccm | grep -i 'load balancer\|initializ'`), `04-lb-console.png`

### 6f. `ansible-playbook 04-monitoring.yml` then re-run `05-gitea.yml`
```
kubectl -n monitoring port-forward svc/kps-grafana 3002:80 &
kubectl -n monitoring port-forward svc/kps-kube-prometheus-stack-prometheus 9091:9090 &
```
**Concept:** the identical values file produces a *different* targets page:
`kube-etcd`, `kube-scheduler`, `kube-controller-manager` are UP here.
**Capture:** `06f/01-targets.png` — put it next to `03-vke-observe/01-targets.png` in the write-up. `06f/02-grafana-gitea.png`, `03-ssh-push.txt`.

---

## 7. kubeadm — runbooks

- **RB-02**, **RB-03** (same as VKE; confirm identical behavior — that's a finding too)
- **RB-04b** (remove the NodePort firewall rule → LB 0 healthy; VKE can't do this)
- **RB-06** Part A (add a worker: the taint reappears briefly, then clears) and Part C (upgrade — this is where the time/command-count comparison lands)

---

## 8. Teardown

```
# kubeadm first — helm uninstall so the CCM deletes the LBs before the CCM itself goes away
ansible -i ansible/inventory/hosts.ini controlplane -m shell -a 'KUBECONFIG=/etc/kubernetes/admin.conf helm -n gitea uninstall gitea; KUBECONFIG=/etc/kubernetes/admin.conf helm -n monitoring uninstall kps'
cd terraform/kubeadm && terraform destroy
cd ../vke && terraform destroy
vultr-cli load-balancer list; vultr-cli block-storage list   # anything left is a finding (orphaned resources)
```
**Capture:** `08-teardown/01-orphans.txt` — ideally empty; if not, what was
orphaned and why (usually LBs from Services deleted after the CCM was gone).

---

## 9. Assembling the write-up

Suggested structure, each section pointing at specific evidence files:

1. **Goal and setup** — two clusters, one workload. Repo tree. (`00-prereqs`)
2. **What "managed" means** — `01-vke/03-kube-system.txt` vs `06b/02-static-pods.txt` and `06b/06-manifests-dir.txt`. The Prometheus targets pages side by side.
3. **The integration layer** — the 6d→6e sequence: pending Service and PVC, CCM/CSI install, both resolve. This is the narrative centerpiece.
4. **Break/fix catalogue** — one subsection per runbook; symptom, the one diagnostic output that names the cause, the fix. Link the full runbook.
5. **Where support conversations differ** — a table: ticket type / VKE / kubeadm / what you'd ask first.
6. **Operational comparison** — RB-06 numbers: commands and minutes to add a node and to upgrade, both ways.
7. **What I'd do differently in production** — VPC-attached DB, HA control plane, ingress + cert-manager, PDBs, RWX storage for Gitea.

Length target: the write-up should be readable in ten minutes. Everything
else lives in the repo for anyone who wants to go deeper.

---

## Concept map (for the interview, not the write-up)

| Concept | Where it's proven |
|---|---|
| Managed vs self-managed control plane | §1 vs §6b |
| Static pods / what etcd & apiserver physically are | §6b |
| Cloud Controller Manager: node init, taints, LoadBalancer fulfilment | §6b, §6d, §6e, RB-04 |
| CSI / dynamic provisioning / StorageClass | §6e, RB-05 |
| Access modes and stateful scaling | RB-02 |
| CNI and NetworkPolicy enforcement | RB-03, RB-03b |
| Cloud firewall vs NetworkPolicy (different layers) | §5, RB-04b |
| LB health checks and the NodePort path | RB-03, RB-04b |
| Prometheus Operator / ServiceMonitor | §3, §6f |
| Node lifecycle: cordon, drain, PDB, upgrades | RB-06 |
| IaC: Terraform ↔ Ansible handoff | §5 |
| Version pinning and drift | §0 |
| External managed services and trust boundaries | RB-01 |
