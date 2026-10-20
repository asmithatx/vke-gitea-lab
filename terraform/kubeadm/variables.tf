variable "vultr_api_key" {
  type      = string
  sensitive = true
  default   = null
}

variable "region" {
  type    = string
  default = "dfw"
}

variable "cluster_label" {
  type    = string
  default = "gitea-kubeadm"
}

# Ubuntu 24.04 LTS. `vultr-cli os list` for current IDs.
variable "os_id" {
  type    = number
  default = 2284
}

# Slightly larger than the VKE workers: the control plane node also runs
# etcd/apiserver, which VKE was hiding from us.
variable "controlplane_plan" {
  type    = string
  default = "vc2-2c-4gb"
}

variable "worker_plan" {
  type    = string
  default = "vc2-2c-4gb"
}

variable "worker_count" {
  type    = number
  default = 2
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}

# Your workstation IP(s). Only these may reach the API server (6443) and SSH.
variable "admin_cidrs" {
  type    = list(string)
  default = [] # e.g. ["203.0.113.10/32"]
}
