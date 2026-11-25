output "instance_id" {
  description = "OCID of the instance."
  value       = oci_core_instance.this.id
}

output "private_ip" {
  description = "Primary private IP of the instance."
  value       = oci_core_instance.this.private_ip
}

output "reserved_public_ip" {
  description = "Reserved public IP address attached to the instance."
  value       = oci_core_public_ip.reserved.ip_address
}

output "reserved_public_ip_id" {
  description = "OCID of the reserved public IP."
  value       = oci_core_public_ip.reserved.id
}
