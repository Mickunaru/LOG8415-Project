output "gatekeeper_instance_id" {
  value = module.gatekeeper.id
}

output "gatekeeper_public_ip" {
  value = module.gatekeeper.public_ip
}

output "proxy_instance_id" {
  value = module.proxy.id
}

output "proxy_private_ip" {
  value = module.proxy.private_ip
}
