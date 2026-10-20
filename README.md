# vke-gitea-lab

Gitea deployed two ways on Vultr — managed (VKE) and self-managed (kubeadm
on Compute) — with the same observability layer on both, plus a set of
break/fix runbooks written the way support KB articles should be.

```
terraform/vke/        VKE cluster, Managed Postgres, Gitea, kube-prometheus-stack, NetworkPolicies
terraform/kubeadm/    3 Compute instances, VPC, firewall → Ansible inventory
ansible/              00-common → 01-controlplane → 02-workers → 03-vultr-integrations → 04-monitoring → 05-gitea
helm/                 shared Gitea values + NetworkPolicies for the kubeadm side
monitoring/           shared kube-prometheus-stack values + Gitea Grafana dashboard
runbooks/             RB-01 … RB-06 break/fix runbooks; evidence/ holds captures
IMPLEMENTATION-GUIDE.md   stage-by-stage build with concept + proof checkpoints
```

Start with `IMPLEMENTATION-GUIDE.md`.

Status: scaffold — not yet applied against a real account. Version pins and
a handful of provider/chart details are flagged for verification in
`IMPLEMENTATION-GUIDE.md` §0 and `terraform/vke/README.md`.
