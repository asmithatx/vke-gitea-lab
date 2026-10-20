output "cluster_id" {
  value = vultr_kubernetes.lab.id
}

output "kubeconfig" {
  value     = local.kubeconfig_raw
  sensitive = true
  # terraform output -raw kubeconfig > ~/.kube/gitea-lab && export KUBECONFIG=~/.kube/gitea-lab
}

output "node_pool" {
  value = vultr_kubernetes.lab.node_pools
  # Grab node IPs from here (or `kubectl get nodes -o wide`) and feed them
  # back into var.pg_trusted_ips on the second apply.
}

output "pg_host" {
  value = vultr_database.pg.host
}

output "pg_port" {
  value = vultr_database.pg.port
}

output "gitea_admin_password" {
  value     = random_password.gitea_admin.result
  sensitive = true
}

# LB IPs are assigned by the CCM after the Service exists, so read them
# from the cluster rather than from Vultr:
#   kubectl -n gitea get svc gitea-http gitea-ssh -o wide
