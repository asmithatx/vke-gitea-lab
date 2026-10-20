terraform {
  required_version = ">= 1.6"

  required_providers {
    vultr = {
      source  = "vultr/vultr"
      version = ">= 2.33.0, < 3.0" # 2.33.0 added vultr_kubernetes_kubeconfig
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
    random = {
      source  = "random"
      version = "~> 3.6"
    }
  }
}

provider "vultr" {
  api_key     = var.vultr_api_key # or export VULTR_API_KEY
  rate_limit  = 700
  retry_limit = 3
}

# Provider >= 2.33.0 moved kubeconfig out of the vultr_kubernetes resource
# into this data source. Parse the kubeconfig YAML itself so we don't depend
# on which individual fields the provider exposes.
data "vultr_kubernetes_kubeconfig" "lab" {
  cluster_id = vultr_kubernetes.lab.id
}

locals {
  kubeconfig_raw = base64decode(data.vultr_kubernetes_kubeconfig.lab.kube_config)
  kubeconfig     = yamldecode(local.kubeconfig_raw)
  kube_host      = local.kubeconfig.clusters[0].cluster.server
  kube_ca        = base64decode(local.kubeconfig.clusters[0].cluster["certificate-authority-data"])
  kube_user      = local.kubeconfig.users[0].user

  # VKE kubeconfigs may carry a bearer token OR a client cert/key pair.
  # Whichever is present is used; the others resolve to null, which the
  # providers treat as unset.
  kube_token = try(local.kube_user.token, null)
  kube_cert  = try(base64decode(local.kube_user["client-certificate-data"]), null)
  kube_key   = try(base64decode(local.kube_user["client-key-data"]), null)
}

provider "kubernetes" {
  host                   = local.kube_host
  cluster_ca_certificate = local.kube_ca
  token                  = local.kube_token
  client_certificate     = local.kube_cert
  client_key             = local.kube_key
}

provider "helm" {
  kubernetes {
    host                   = local.kube_host
    cluster_ca_certificate = local.kube_ca
    token                  = local.kube_token
    client_certificate     = local.kube_cert
    client_key             = local.kube_key
  }
}
