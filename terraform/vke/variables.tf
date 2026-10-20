variable "vultr_api_key" {
  type      = string
  sensitive = true
  default   = null # falls back to VULTR_API_KEY env var
}

variable "region" {
  type    = string
  default = "dfw" # Dallas — closest to Austin
}

variable "cluster_label" {
  type    = string
  default = "gitea-lab"
}

# Pin this. Letting it float is itself a break/fix scenario (surprise upgrade).
# `vultr-cli kubernetes versions` lists what's currently offered.
variable "k8s_version" {
  type    = string
  default = "v1.37.1+2"
}

variable "node_plan" {
  type    = string
  default = "vc2-2c-4gb" # 2 vCPU / 4 GB; enough for Gitea + Valkey + monitoring on 3 nodes
}

variable "node_count" {
  type    = number
  default = 3
}

variable "pg_plan" {
  type    = string
  default = "vultr-dbaas-startup-cc-1-55-2" # smallest managed Postgres plan
}

variable "pg_version" {
  type    = string
  default = "16"
}

# Managed DB only accepts connections from these IPs/CIDRs.
# Leaving this empty on purpose is break/fix candidate #1 — Gitea pods
# will fail to connect and the fix is adding the node IPs (see outputs).
variable "pg_trusted_ips" {
  type    = list(string)
  default = []
}

variable "gitea_admin_username" {
  type    = string
  default = "gitea-admin"
}

variable "gitea_domain" {
  type        = string
  description = "Hostname Gitea will advertise; point an A record here after the LB comes up."
  default     = "git.lab.example.com"
}
