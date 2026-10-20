output "controlplane_public_ip" {
  value = vultr_instance.controlplane.main_ip
}

output "controlplane_private_ip" {
  value = vultr_instance.controlplane.internal_ip
}

output "worker_public_ips" {
  value = vultr_instance.worker[*].main_ip
}

output "vpc_id" {
  value = vultr_vpc.cluster.id
}

output "inventory_path" {
  value = local_file.ansible_inventory.filename
}
