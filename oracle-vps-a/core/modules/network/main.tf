# -----------------------------------------------------------------------------
# VCN
# -----------------------------------------------------------------------------

resource "oci_core_vcn" "this" {
  compartment_id = var.compartment_id
  display_name   = "oracle-vcn"
  dns_label      = "oraclevcn"
  cidr_blocks    = [var.vcn_cidr]
  freeform_tags  = var.freeform_tags
}

# -----------------------------------------------------------------------------
# Gateways
# -----------------------------------------------------------------------------

resource "oci_core_internet_gateway" "this" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "IGW"
  enabled        = true
  freeform_tags  = var.freeform_tags
}

resource "oci_core_nat_gateway" "this" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "NAT"
  block_traffic  = false
  freeform_tags  = var.freeform_tags
}

resource "oci_core_service_gateway" "this" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "service-gw"
  freeform_tags  = var.freeform_tags

  services {
    service_id = var.service_id
  }
}

# -----------------------------------------------------------------------------
# Route tables
# -----------------------------------------------------------------------------

# The VCN's default route table is adopted and used by the public subnet.
resource "oci_core_default_route_table" "public" {
  manage_default_resource_id = oci_core_vcn.this.default_route_table_id
  display_name               = "public-route-table"
  freeform_tags              = var.freeform_tags

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.this.id
  }
}

resource "oci_core_route_table" "private" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "private-route-table"
  freeform_tags  = var.freeform_tags

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.this.id
  }

  route_rules {
    destination       = var.service_cidr_block
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.this.id
  }
}

# -----------------------------------------------------------------------------
# Security lists
# -----------------------------------------------------------------------------

# The VCN's default security list is adopted and used by the public subnet.
resource "oci_core_default_security_list" "public" {
  manage_default_resource_id = oci_core_vcn.this.default_security_list_id
  display_name               = "public-security-list"
  freeform_tags              = var.freeform_tags

  egress_security_rules {
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    protocol         = "all"
  }

  # SSH from anywhere
  ingress_security_rules {
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    protocol    = "6"

    tcp_options {
      min = 22
      max = 22
    }
  }

  # ICMP "fragmentation needed" (path MTU discovery) from anywhere
  ingress_security_rules {
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    protocol    = "1"

    icmp_options {
      type = 3
      code = 4
    }
  }

  # ICMP destination unreachable from inside the VCN
  ingress_security_rules {
    source      = var.vcn_cidr
    source_type = "CIDR_BLOCK"
    protocol    = "1"

    icmp_options {
      type = 3
    }
  }
}

resource "oci_core_security_list" "private" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "private-security-list"
  freeform_tags  = var.freeform_tags

  egress_security_rules {
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    protocol         = "all"
  }

  # SSH only from inside the VCN
  ingress_security_rules {
    source      = var.vcn_cidr
    source_type = "CIDR_BLOCK"
    protocol    = "6"

    tcp_options {
      min = 22
      max = 22
    }
  }

  ingress_security_rules {
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    protocol    = "1"

    icmp_options {
      type = 3
      code = 4
    }
  }

  ingress_security_rules {
    source      = var.vcn_cidr
    source_type = "CIDR_BLOCK"
    protocol    = "1"

    icmp_options {
      type = 3
    }
  }
}

# -----------------------------------------------------------------------------
# Subnets
# -----------------------------------------------------------------------------

resource "oci_core_subnet" "public" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.this.id
  display_name               = "public-subnet"
  dns_label                  = "public"
  cidr_block                 = var.public_subnet_cidr
  route_table_id             = oci_core_default_route_table.public.id
  security_list_ids          = [oci_core_default_security_list.public.id]
  dhcp_options_id            = oci_core_vcn.this.default_dhcp_options_id
  prohibit_public_ip_on_vnic = false
  prohibit_internet_ingress  = false
  freeform_tags              = var.freeform_tags
}

resource "oci_core_subnet" "private" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.this.id
  display_name               = "private-subnet"
  dns_label                  = "private"
  cidr_block                 = var.private_subnet_cidr
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.private.id]
  dhcp_options_id            = oci_core_vcn.this.default_dhcp_options_id
  prohibit_public_ip_on_vnic = true
  prohibit_internet_ingress  = true
  freeform_tags              = var.freeform_tags
}

# -----------------------------------------------------------------------------
# Network security group for the VPS
# -----------------------------------------------------------------------------

resource "oci_core_network_security_group" "vps" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "arm-flex-vps-nsg"
  freeform_tags  = var.freeform_tags
}

resource "oci_core_network_security_group_security_rule" "vps_ingress" {
  for_each = { for rule in var.vps_ingress_ports : tostring(rule.port) => rule }

  network_security_group_id = oci_core_network_security_group.vps.id
  description               = each.value.description
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  stateless                 = false

  tcp_options {
    destination_port_range {
      min = each.value.port
      max = each.value.port
    }
  }
}
