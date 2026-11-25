# -----------------------------------------------------------------------------
# Provider / account
# -----------------------------------------------------------------------------

variable "oci_config_profile" {
  description = "Profile name in ~/.oci/config used for authentication."
  type        = string
  default     = "DEFAULT"
}

variable "oci_private_key_password" {
  description = "Passphrase of the OCI API private key. Set via the TF_VAR_oci_private_key_password environment variable; never commit it."
  type        = string
  sensitive   = true
  default     = null
}

variable "region" {
  description = "OCI region to deploy into."
  type        = string
  default     = "ap-hyderabad-1"
}

variable "compartment_ocid" {
  description = "OCID of the compartment that holds every resource (the tenancy OCID for the root compartment)."
  type        = string

  validation {
    condition     = can(regex("^ocid1\\.(tenancy|compartment)\\.", var.compartment_ocid))
    error_message = "compartment_ocid must be a tenancy or compartment OCID."
  }
}

# -----------------------------------------------------------------------------
# Network
# -----------------------------------------------------------------------------

variable "vcn_cidr" {
  description = "CIDR block of the VCN."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block of the public subnet (hosts the VPS)."
  type        = string
  default     = "10.0.0.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block of the private subnet (egress through NAT and the service gateway only)."
  type        = string
  default     = "10.0.1.0/24"
}

variable "vps_ingress_ports" {
  description = "Extra TCP ports opened to the internet on the VPS network security group."
  type = list(object({
    port        = number
    description = string
  }))
  default = [
    { port = 9001, description = "Allow inbound traffic from portainer" },
  ]
}

# -----------------------------------------------------------------------------
# Compute
# -----------------------------------------------------------------------------

variable "instance_image_id" {
  description = "OCID of the image used for the VPS boot volume."
  type        = string
  default     = "ocid1.image.oc1.ap-hyderabad-1.aaaaaaaabzuisrydfrxdompszuk3fecpactpq2k2lm5xwjaijyidwvsetbuq"
}

variable "instance_shape" {
  description = "Compute shape of the VPS."
  type        = string
  default     = "VM.Standard.A1.Flex"
}

variable "instance_ocpus" {
  description = "Number of OCPUs for the flex shape."
  type        = number
  default     = 4
}

variable "instance_memory_in_gbs" {
  description = "Memory in GB for the flex shape."
  type        = number
  default     = 24
}

variable "boot_volume_size_in_gbs" {
  description = "Boot volume size in GB."
  type        = number
  default     = 200
}

variable "boot_volume_vpus_per_gb" {
  description = "Boot volume performance in VPUs per GB (10 = balanced, 20+ = higher performance)."
  type        = number
  default     = 120
}

variable "instance_private_ip" {
  description = "Static private IP of the VPS inside the public subnet."
  type        = string
  default     = "10.0.0.150"
}

variable "fault_domain" {
  description = "Fault domain to place the VPS in."
  type        = string
  default     = "FAULT-DOMAIN-1"
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key authorized on the VPS (e.g. ~/.ssh/oracle-vps-a.pub)."
  type        = string
}

variable "ssh_user" {
  description = "Default login user of the image (ubuntu for Ubuntu images, opc for Oracle Linux). Only used for the ssh_command output."
  type        = string
  default     = "ubuntu"
}

variable "tailscale_auth_key" {
  description = "One-off, pre-approved Tailscale auth key (tskey-auth-...). Read by cloud-init only when the instance is created. Set it in terraform.tfvars just before a rebuild; leave empty otherwise."
  type        = string
  default     = ""
  sensitive   = true
}
