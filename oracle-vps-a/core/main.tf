module "network" {
  source = "./modules/network"

  compartment_id      = var.compartment_ocid
  vcn_cidr            = var.vcn_cidr
  public_subnet_cidr  = var.public_subnet_cidr
  private_subnet_cidr = var.private_subnet_cidr
  service_id          = data.oci_core_services.all.services[0].id
  service_cidr_block  = data.oci_core_services.all.services[0].cidr_block
  vps_ingress_ports   = var.vps_ingress_ports
  freeform_tags       = local.common_tags
}

module "compute" {
  source = "./modules/compute"

  compartment_id          = var.compartment_ocid
  availability_domain     = data.oci_identity_availability_domain.this.name
  fault_domain            = var.fault_domain
  subnet_id               = module.network.public_subnet_id
  nsg_ids                 = [module.network.vps_nsg_id]
  private_ip              = var.instance_private_ip
  image_id                = var.instance_image_id
  shape                   = var.instance_shape
  ocpus                   = var.instance_ocpus
  memory_in_gbs           = var.instance_memory_in_gbs
  boot_volume_size_in_gbs = var.boot_volume_size_in_gbs
  boot_volume_vpus_per_gb = var.boot_volume_vpus_per_gb
  ssh_authorized_keys     = file(pathexpand(var.ssh_public_key_path))
  freeform_tags           = local.common_tags
}
