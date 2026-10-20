# -----------------------------------------------------------------------------
# Observability: kube-prometheus-stack (Prometheus Operator + Grafana +
# node-exporter + kube-state-metrics + Alertmanager)
# -----------------------------------------------------------------------------
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

resource "random_password" "grafana_admin" {
  length  = 24
  special = false
}

resource "helm_release" "kube_prometheus_stack" {
  name       = "kps"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "65.1.1" # pin; `helm search repo prometheus-community/kube-prometheus-stack --versions`

  timeout = 900
  wait    = true

  # Same values file the kubeadm side uses — see monitoring/README notes.
  values = [file("${path.module}/../../monitoring/kube-prometheus-stack-values.yaml")]

  set_sensitive {
    name  = "grafana.adminPassword"
    value = random_password.grafana_admin.result
  }
}

# Gitea dashboard, picked up by the Grafana sidecar via the label.
resource "kubernetes_config_map" "gitea_dashboard" {
  metadata {
    name      = "gitea-dashboard"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    labels = {
      grafana_dashboard = "1"
    }
  }
  data = {
    "gitea-lab.json" = file("${path.module}/../../monitoring/gitea-dashboard.json")
  }
  depends_on = [helm_release.kube_prometheus_stack]
}

# Allow Prometheus (monitoring ns) through the gitea namespace default-deny
# to scrape /metrics on 3000. Delete this policy → targets go DOWN → runbook 03b.
resource "kubernetes_network_policy" "gitea_allow_prometheus" {
  metadata {
    name      = "allow-prometheus-scrape"
    namespace = kubernetes_namespace.gitea.metadata[0].name
  }
  spec {
    pod_selector {
      match_labels = { "app.kubernetes.io/name" = "gitea" }
    }
    policy_types = ["Ingress"]
    ingress {
      from {
        namespace_selector {
          match_labels = { "kubernetes.io/metadata.name" = "monitoring" }
        }
      }
      ports {
        port     = "3000"
        protocol = "TCP"
      }
    }
  }
}

output "grafana_admin_password" {
  value     = random_password.grafana_admin.result
  sensitive = true
  # kubectl -n monitoring port-forward svc/kps-grafana 3001:80  → http://localhost:3001
}
