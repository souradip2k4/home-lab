variable "compartment_id" {
  description = "OCID of the compartment for all network resources."
  type        = string
}

variable "vcn_cidr" {
  description = "CIDR block of the VCN."
  type        = string
}

variable "public_subnet_cidr" {
  description = "CIDR block of the public subnet."
  type        = string
}

variable "private_subnet_cidr" {
  description = "CIDR block of the private subnet."
  type        = string
}

variable "service_id" {
  description = "OCID of the Oracle Services Network service the service gateway connects to."
  type        = string
}

variable "service_cidr_block" {
  description = "Service CIDR label (e.g. all-hyd-services-in-oracle-services-network) routed through the service gateway."
  type        = string
}

variable "vps_ingress_ports" {
  description = "TCP ports opened to 0.0.0.0/0 on the VPS network security group."
  type = list(object({
    port        = number
    description = string
  }))
  default = []
}

variable "freeform_tags" {
  description = "Free-form tags applied to every resource."
  type        = map(string)
  default     = {}
}
