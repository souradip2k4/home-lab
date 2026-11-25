variable "compartment_id" {
  description = "OCID of the compartment for the instance and its reserved public IP."
  type        = string
}

variable "name" {
  description = "Display name and hostname label of the instance."
  type        = string
  default     = "arm-flex-vps"
}

variable "availability_domain" {
  description = "Availability domain name to launch the instance in."
  type        = string
}

variable "fault_domain" {
  description = "Fault domain to place the instance in."
  type        = string
}

variable "subnet_id" {
  description = "OCID of the subnet for the primary VNIC."
  type        = string
}

variable "nsg_ids" {
  description = "Network security group OCIDs attached to the primary VNIC."
  type        = list(string)
  default     = []
}

variable "private_ip" {
  description = "Static private IP for the primary VNIC."
  type        = string
}

variable "image_id" {
  description = "OCID of the boot image."
  type        = string
}

variable "shape" {
  description = "Compute shape."
  type        = string
}

variable "ocpus" {
  description = "OCPUs for the flex shape."
  type        = number
}

variable "memory_in_gbs" {
  description = "Memory in GB for the flex shape."
  type        = number
}

variable "boot_volume_size_in_gbs" {
  description = "Boot volume size in GB."
  type        = number
}

variable "boot_volume_vpus_per_gb" {
  description = "Boot volume VPUs per GB."
  type        = number
}

variable "ssh_authorized_keys" {
  description = "Contents of the SSH public key(s) authorized for the default user."
  type        = string
}

variable "agent_plugins" {
  description = "Oracle Cloud Agent plugins and their desired state (ENABLED or DISABLED)."
  type        = map(string)
  default = {
    "Bastion"                              = "DISABLED"
    "Block Volume Management"              = "DISABLED"
    "Cloud Guard Workload Protection"      = "ENABLED"
    "Compute HPC RDMA Authentication"      = "DISABLED"
    "Compute HPC RDMA Auto-Configuration"  = "DISABLED"
    "Compute Instance Monitoring"          = "ENABLED"
    "Compute Instance Run Command"         = "ENABLED"
    "Compute RDMA GPU Monitoring"          = "DISABLED"
    "Custom Logs Monitoring"               = "ENABLED"
    "Fleet Application Management Service" = "DISABLED"
    "Management Agent"                     = "DISABLED"
    "OS Management Hub Agent"              = "DISABLED"
    "Oracle Java Management Service"       = "DISABLED"
    "Vulnerability Scanning"               = "DISABLED"
    "WebLogic Management Service"          = "DISABLED"
  }

  validation {
    condition     = alltrue([for state in values(var.agent_plugins) : contains(["ENABLED", "DISABLED"], state)])
    error_message = "Each agent plugin state must be ENABLED or DISABLED."
  }
}

variable "freeform_tags" {
  description = "Free-form tags applied to every resource."
  type        = map(string)
  default     = {}
}
