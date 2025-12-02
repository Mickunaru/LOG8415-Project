output "gatekeeper_instance_id" {
  value = module.gatekeeper.id
}

output "proxy_instance_id" {
  value = module.proxy.id
}

output "manager_instance_id" {
  value = module.manager.id
}

output "worker1_instance_id" {
  value = module.worker1.id
}

output "worker2_instance_id" {
  value = module.worker2.id
}

output "gatekeeper_public_ip" {
  value = module.gatekeeper.public_ip
}

output "proxy_private_ip" {
  value = module.proxy.private_ip
}

output "manager_private_ip" {
  value = module.manager.private_ip
}

output "worker1_private_ip" {
  value = module.worker1.private_ip
}

output "worker2_private_ip" {
  value = module.worker2.private_ip
}

