# -----------------------------------------------------------------------------
# Gitea via the official Helm chart
# -----------------------------------------------------------------------------
# External Postgres (Vultr Managed DB), in-cluster Valkey for cache/sessions,
# Block Storage PVC for repos, and two Vultr Load Balancers: HTTP and SSH.
resource "helm_release" "gitea" {
  name       = "gitea"
  namespace  = kubernetes_namespace.gitea.metadata[0].name
  repository = "https://dl.gitea.com/charts/"
  chart      = "gitea"
  # Pin the chart too — same reasoning as the k8s version.
  version = "11.0.1"

  timeout = 600
  wait    = true

  values = [yamlencode({
    # --- bundled dependencies -------------------------------------------
    postgresql      = { enabled = false } # using Vultr Managed DB
    "postgresql-ha" = { enabled = false }
    "valkey-cluster" = { enabled = false }
    valkey = {
      enabled = true
      primary = {
        persistence = { enabled = false } # cache only; losing it is fine
      }
    }

    # --- gitea app config -------------------------------------------------
    gitea = {
      admin = {
        existingSecret = kubernetes_secret.gitea_admin.metadata[0].name
      }
      # DB settings come in as GITEA__database__* env vars via extraEnvFrom below
      config = {
        server = {
          DOMAIN     = var.gitea_domain
          ROOT_URL   = "http://${var.gitea_domain}/"
          SSH_DOMAIN = var.gitea_domain
          SSH_PORT   = 22
        }
        metrics = { ENABLED = true } # exposes /metrics for Prometheus (part 5)
        service = { DISABLE_REGISTRATION = true }
      }
      metrics = {
        enabled = true
        # Needs the ServiceMonitor CRD, hence depends_on kube_prometheus_stack.
        serviceMonitor = { enabled = true }
      }
    }

    # Pull every GITEA__* key from the db secret into the container env
    extraEnvFrom = [{ secretRef = { name = kubernetes_secret.gitea_db.metadata[0].name } }]

    # --- storage -------------------------------------------------------------
    # vultr-block-storage is the VKE default StorageClass (NVMe, RWO).
    # RWO is deliberate: scaling replicaCount to 2 produces the Multi-Attach
    # error — break/fix scenario for the storage runbook.
    persistence = {
      enabled      = true
      size         = "10Gi" # NVMe block storage minimum
      storageClass = "vultr-block-storage"
      accessModes  = ["ReadWriteOnce"]
    }
    replicaCount = 1

    # --- services → Vultr Load Balancers ------------------------------------
    service = {
      http = {
        type = "LoadBalancer"
        port = 80
        annotations = {
          "service.beta.kubernetes.io/vultr-loadbalancer-label"                = "${var.cluster_label}-http"
          "service.beta.kubernetes.io/vultr-loadbalancer-protocol"             = "http"
          "service.beta.kubernetes.io/vultr-loadbalancer-healthcheck-protocol" = "http"
          "service.beta.kubernetes.io/vultr-loadbalancer-healthcheck-path"     = "/api/healthz"
          "service.beta.kubernetes.io/vultr-loadbalancer-healthcheck-check-interval"     = "10"
          "service.beta.kubernetes.io/vultr-loadbalancer-healthcheck-response-timeout"   = "5"
          "service.beta.kubernetes.io/vultr-loadbalancer-healthcheck-unhealthy-threshold" = "3"
          "service.beta.kubernetes.io/vultr-loadbalancer-healthcheck-healthy-threshold"   = "3"
        }
      }
      ssh = {
        type = "LoadBalancer"
        port = 22
        annotations = {
          "service.beta.kubernetes.io/vultr-loadbalancer-label"                = "${var.cluster_label}-ssh"
          "service.beta.kubernetes.io/vultr-loadbalancer-protocol"             = "tcp"
          "service.beta.kubernetes.io/vultr-loadbalancer-healthcheck-protocol" = "tcp"
        }
      }
    }

    # No ingress for the first pass — a raw LB keeps the health-check story
    # simple. Phase 2: ingress-nginx + cert-manager and collapse to one LB.
    ingress = { enabled = false }

    # Allow the kube-prometheus-stack scrape later without a NetworkPolicy fight
    podAnnotations = {
      "prometheus.io/scrape" = "true"
      "prometheus.io/port"   = "3000"
    }
  })]

  depends_on = [
    vultr_database_db.gitea,
    vultr_database_user.gitea,
    helm_release.kube_prometheus_stack, # ServiceMonitor CRD must exist first
  ]
}

# -----------------------------------------------------------------------------
# Baseline NetworkPolicies (Calico is the VKE CNI, so these are enforced)
# -----------------------------------------------------------------------------
# Default-deny ingress in the namespace, then allow only what Gitea needs.
# Removing the second policy is the network break/fix scenario.
resource "kubernetes_network_policy" "gitea_default_deny" {
  metadata {
    name      = "default-deny-ingress"
    namespace = kubernetes_namespace.gitea.metadata[0].name
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy" "gitea_allow" {
  metadata {
    name      = "allow-gitea-ingress"
    namespace = kubernetes_namespace.gitea.metadata[0].name
  }
  spec {
    pod_selector {
      match_labels = { "app.kubernetes.io/name" = "gitea" }
    }
    policy_types = ["Ingress"]
    # LB health checks arrive from node IPs; an empty `from` allows all sources
    # on these ports, which is what a public git host needs anyway.
    ingress {
      ports {
        port     = "3000"
        protocol = "TCP"
      }
      ports {
        port     = "22"
        protocol = "TCP"
      }
    }
  }
}

resource "kubernetes_network_policy" "valkey_allow" {
  metadata {
    name      = "allow-gitea-to-valkey"
    namespace = kubernetes_namespace.gitea.metadata[0].name
  }
  spec {
    pod_selector {
      match_labels = { "app.kubernetes.io/name" = "valkey" }
    }
    policy_types = ["Ingress"]
    ingress {
      from {
        pod_selector {
          match_labels = { "app.kubernetes.io/name" = "gitea" }
        }
      }
      ports {
        port     = "6379"
        protocol = "TCP"
      }
    }
  }
}
