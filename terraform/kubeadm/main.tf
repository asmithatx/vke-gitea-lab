# -----------------------------------------------------------------------------
# Everything VKE did for us, done by hand. Compare against terraform/vke:
# that file has one cluster resource; this one has instances, a VPC, a
# firewall, and an SSH key — and still no Kubernetes until Ansible runs.
# -----------------------------------------------------------------------------

resource "vultr_ssh_key" "admin" {
  name    = "${var.cluster_label}-admin"
  ssh_key = file(pathexpand(var.ssh_public_key_path))
}

# Private network for node-to-node traffic (kubelet, etcd, pod overlay).
resource "vultr_vpc" "cluster" {
  region      = var.region
  description = "${var.cluster_label}-vpc"
}

# -----------------------------------------------------------------------------
# Firewall — VKE's enable_firewall=true builds this for you.
# -----------------------------------------------------------------------------
resource "vultr_firewall_group" "cluster" {
  description = "${var.cluster_label}-fw"
}

resource "vultr_firewall_rule" "ssh" {
  for_each          = toset(var.admin_cidrs)
  firewall_group_id = vultr_firewall_group.cluster.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = cidrhost(each.value, 0)
  subnet_size       = tonumber(split("/", each.value)[1])
  port              = "22"
  notes             = "ssh from admin"
}

resource "vultr_firewall_rule" "apiserver" {
  for_each          = toset(var.admin_cidrs)
  firewall_group_id = vultr_firewall_group.cluster.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = cidrhost(each.value, 0)
  subnet_size       = tonumber(split("/", each.value)[1])
  port              = "6443"
  notes             = "kube-apiserver from admin"
}

# NodePort range — Vultr LBs created by the CCM forward to NodePorts on the
# public IPs. Without this rule LB health checks fail (runbook 04b).
resource "vultr_firewall_rule" "nodeport" {
  firewall_group_id = vultr_firewall_group.cluster.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "30000:32767"
  notes             = "NodePort range for Vultr LB backends"
}

# -----------------------------------------------------------------------------
# Instances
# -----------------------------------------------------------------------------
resource "vultr_instance" "controlplane" {
  region            = var.region
  plan              = var.controlplane_plan
  os_id             = var.os_id
  label             = "${var.cluster_label}-cp-1"
  hostname          = "${var.cluster_label}-cp-1"
  tags              = [var.cluster_label, "controlplane"]
  ssh_key_ids       = [vultr_ssh_key.admin.id]
  vpc_ids           = [vultr_vpc.cluster.id]
  firewall_group_id = vultr_firewall_group.cluster.id
  enable_ipv6       = false
  backups           = "disabled"
  activation_email  = false
}

resource "vultr_instance" "worker" {
  count             = var.worker_count
  region            = var.region
  plan              = var.worker_plan
  os_id             = var.os_id
  label             = "${var.cluster_label}-w-${count.index + 1}"
  hostname          = "${var.cluster_label}-w-${count.index + 1}"
  tags              = [var.cluster_label, "worker"]
  ssh_key_ids       = [vultr_ssh_key.admin.id]
  vpc_ids           = [vultr_vpc.cluster.id]
  firewall_group_id = vultr_firewall_group.cluster.id
  enable_ipv6       = false
  backups           = "disabled"
  activation_email  = false
}

# -----------------------------------------------------------------------------
# Hand off to Ansible
# -----------------------------------------------------------------------------
resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../../ansible/inventory/hosts.ini"
  file_permission = "0644"
  content = templatefile("${path.module}/inventory.tftpl", {
    controlplane = vultr_instance.controlplane
    workers      = vultr_instance.worker
    region       = var.region
    vpc_id       = vultr_vpc.cluster.id
  })
}
