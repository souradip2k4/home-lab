# -----------------------------------------------------------------------------
# Instance
# -----------------------------------------------------------------------------

resource "oci_core_instance" "this" {
  compartment_id      = var.compartment_id
  display_name        = var.name
  availability_domain = var.availability_domain
  fault_domain        = var.fault_domain
  shape               = var.shape
  freeform_tags       = var.freeform_tags

  # In-transit encryption for paravirtualized volume attachments. OCI only honours this
  # top-level flag at create time; launch_options.is_pv_encryption_in_transit_enabled
  # below is the field used for later updates. Both are set so create and update agree.
  is_pv_encryption_in_transit_enabled = true

  shape_config {
    ocpus         = var.ocpus
    memory_in_gbs = var.memory_in_gbs
  }

  source_details {
    source_type             = "image"
    source_id               = var.image_id
    boot_volume_size_in_gbs = var.boot_volume_size_in_gbs
    boot_volume_vpus_per_gb = var.boot_volume_vpus_per_gb
  }

  create_vnic_details {
    display_name           = var.name
    hostname_label         = var.name
    subnet_id              = var.subnet_id
    private_ip             = var.private_ip
    nsg_ids                = var.nsg_ids
    skip_source_dest_check = false

    # No ephemeral IP: the reserved public IP below is attached instead.
    assign_public_ip = false
  }

  metadata = {
    ssh_authorized_keys = var.ssh_authorized_keys
  }

  agent_config {
    are_all_plugins_disabled = false
    is_management_disabled   = false
    is_monitoring_disabled   = false

    dynamic "plugins_config" {
      for_each = var.agent_plugins
      content {
        name          = plugins_config.key
        desired_state = plugins_config.value
      }
    }
  }

  availability_config {
    recovery_action = "RESTORE_INSTANCE"
  }

  instance_options {
    are_legacy_imds_endpoints_disabled = true
  }

  launch_options {
    boot_volume_type                    = "PARAVIRTUALIZED"
    firmware                            = "UEFI_64"
    network_type                        = "PARAVIRTUALIZED"
    remote_data_volume_type             = "PARAVIRTUALIZED"
    is_consistent_volume_naming_enabled = true
    is_pv_encryption_in_transit_enabled = true
  }
}

# -----------------------------------------------------------------------------
# Reserved public IP
# -----------------------------------------------------------------------------

# Look up the primary private IP that OCI created together with the primary VNIC.
data "oci_core_vnic_attachments" "this" {
  compartment_id = var.compartment_id
  instance_id    = oci_core_instance.this.id
}

data "oci_core_private_ips" "primary" {
  vnic_id = data.oci_core_vnic_attachments.this.vnic_attachments[0].vnic_id
}

# RESERVED lifetime: the address is owned by us, survives instance replacement,
# and is simply re-assigned to the new instance's private IP.
resource "oci_core_public_ip" "reserved" {
  compartment_id = var.compartment_id
  display_name   = "${var.name}-reserved-ip"
  lifetime       = "RESERVED"
  private_ip_id  = data.oci_core_private_ips.primary.private_ips[0].id
  freeform_tags  = var.freeform_tags

  lifecycle {
    # Guards against accidentally releasing the address. Remove this before a
    # deliberate `terraform destroy` of the whole stack.
    prevent_destroy = true
  }
}
