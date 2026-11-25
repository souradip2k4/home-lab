# Availability domain names carry a tenancy-specific prefix (e.g. "CpMO:AP-HYDERABAD-1-AD-1"),
# so they are looked up instead of hardcoded. Hyderabad has a single AD.
data "oci_identity_availability_domain" "this" {
  compartment_id = var.compartment_ocid
  ad_number      = 1
}

# "All <region> Services In Oracle Services Network" — used by the service gateway.
data "oci_core_services" "all" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}
