output "reserved_public_ip" {
  description = "Reserved public IP address attached to the VPS."
  value       = module.compute.reserved_public_ip
}

output "reserved_public_ip_id" {
  description = "OCID of the reserved public IP."
  value       = module.compute.reserved_public_ip_id
}

output "instance_id" {
  description = "OCID of the VPS instance."
  value       = module.compute.instance_id
}

output "instance_private_ip" {
  description = "Private IP of the VPS."
  value       = module.compute.private_ip
}

output "ssh_command" {
  description = "Command to SSH into the VPS (pass your private key with -i if it is not the default)."
  value       = "ssh ${var.ssh_user}@${module.compute.reserved_public_ip}"
}

output "vcn_id" {
  description = "OCID of the VCN."
  value       = module.network.vcn_id
}

output "public_subnet_id" {
  description = "OCID of the public subnet."
  value       = module.network.public_subnet_id
}

output "private_subnet_id" {
  description = "OCID of the private subnet."
  value       = module.network.private_subnet_id
}
