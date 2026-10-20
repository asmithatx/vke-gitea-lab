# -----------------------------------------------------------------------------
# VKE cluster
# -----------------------------------------------------------------------------
# One default node pool is required at create time. Additional pools (e.g. a
# tainted "monitoring" pool later) go in vultr_kubernetes_node_pools.
resource "vultr_kubernetes" "lab" {
  region  = var.region
  label   = var.cluster_label
  version = var.k8s_version

  # HA control plane is extra cost; leave off for the lab, but this is a
  # good talking point for the self-managed-vs-VKE comparison.
  ha_controlplanes = false

  # Firewall-managed cluster: VKE creates a firewall group and opens what
  # the CCM needs. Turn it on so Network Policy vs. Firewall is demonstrable.
  enable_firewall = true

  node_pools {
    node_quantity = var.node_count
    plan          = var.node_plan
    label         = "${var.cluster_label}-default"
    auto_scaler   = true
    min_nodes     = var.node_count
    max_nodes     = var.node_count + 2
  }
}

# -----------------------------------------------------------------------------
# Managed PostgreSQL
# -----------------------------------------------------------------------------
resource "vultr_database" "pg" {
  database_engine         = "pg"
  database_engine_version = var.pg_version
  region                  = var.region
  plan                    = var.pg_plan
  label                   = "${var.cluster_label}-pg"
  cluster_time_zone       = "UTC"
  trusted_ips             = var.pg_trusted_ips
}

resource "vultr_database_db" "gitea" {
  database_id = vultr_database.pg.id
  name        = "gitea"
}

resource "random_password" "gitea_db" {
  length  = 32
  special = false
}

resource "vultr_database_user" "gitea" {
  database_id = vultr_database.pg.id
  username    = "gitea"
  password    = random_password.gitea_db.result
}

# -----------------------------------------------------------------------------
# Namespace + secrets handed to the Helm chart
# -----------------------------------------------------------------------------
resource "kubernetes_namespace" "gitea" {
  metadata {
    name = "gitea"
    labels = {
      "app.kubernetes.io/part-of" = "gitea-lab"
    }
  }
}

resource "random_password" "gitea_admin" {
  length  = 24
  special = false
}

resource "kubernetes_secret" "gitea_admin" {
  metadata {
    name      = "gitea-admin"
    namespace = kubernetes_namespace.gitea.metadata[0].name
  }
  data = {
    username = var.gitea_admin_username
    password = random_password.gitea_admin.result
  }
}

# The Gitea chart can read DB settings from a secret via
# gitea.additionalConfigFromEnvs; keeps the DSN out of the values file.
resource "kubernetes_secret" "gitea_db" {
  metadata {
    name      = "gitea-db"
    namespace = kubernetes_namespace.gitea.metadata[0].name
  }
  data = {
    GITEA__database__DB_TYPE = "postgres"
    GITEA__database__HOST    = "${vultr_database.pg.host}:${vultr_database.pg.port}"
    GITEA__database__NAME    = vultr_database_db.gitea.name
    GITEA__database__USER    = vultr_database_user.gitea.username
    GITEA__database__PASSWD  = vultr_database_user.gitea.password
    GITEA__database__SSL_MODE = "require"
  }
}
