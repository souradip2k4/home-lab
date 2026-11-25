# Authentication is read from ~/.oci/config (user, fingerprint, key_file, tenancy).
# The API private key is passphrase-protected, so the passphrase is supplied
# through the sensitive variable below (export TF_VAR_oci_private_key_password).
provider "oci" {
  config_file_profile  = var.oci_config_profile
  region               = var.region
  private_key_password = var.oci_private_key_password
}
