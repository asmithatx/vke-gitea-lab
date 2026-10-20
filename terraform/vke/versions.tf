terraform {
  required_version = ">= 1.6"

  required_providers {
    vultr = {
      source  = "vultr/vultr"
      version = "~> 2.21"
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

# The cluster resource exports the pieces of its kubeconfig directly,
# so the k8s/helm providers can target the cluster in the same apply.
provider "kubernetes" {
  host                   = vultr_kubernetes.lab.endpoint
  client_certificate     = base64decode(vultr_kubernetes.lab.client_certificate)
  client_key             = base64decode(vultr_kubernetes.lab.client_key)
  cluster_ca_certificate = base64decode(vultr_kubernetes.lab.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = vultr_kubernetes.lab.endpoint
    client_certificate     = base64decode(vultr_kubernetes.lab.client_certificate)
    client_key             = base64decode(vultr_kubernetes.lab.client_key)
    cluster_ca_certificate = base64decode(vultr_kubernetes.lab.cluster_ca_certificate)
  }
}
