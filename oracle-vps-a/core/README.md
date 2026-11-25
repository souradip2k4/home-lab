# oracle-vps-a / core

Base infrastructure for the `arm-flex-vps` Always Free Ampere A1 VPS in OCI `ap-hyderabad-1`:
the network (VCN, subnets, gateways, route tables, security lists, NSG), the instance, and a
**reserved** public IP attached to it.

Other stacks that run things on this VPS should live next to this one, e.g. `oracle-vps-a/<stack>/`.

## What gets created

| Resource | Name | Notes |
|---|---|---|
| VCN | `oracle-vcn` | `10.0.0.0/16` |
| Internet gateway | `IGW` | used by the public subnet |
| NAT gateway | `NAT` | outbound internet for the private subnet |
| Service gateway | `service-gw` | private access to Oracle services |
| Route table | `public-route-table` | VCN default RT: `0.0.0.0/0 → IGW` |
| Route table | `private-route-table` | `0.0.0.0/0 → NAT`, Oracle services → `service-gw` |
| Security list | `public-security-list` | VCN default SL: SSH from anywhere, ICMP path-MTU |
| Security list | `private-security-list` | SSH from inside the VCN only |
| Subnet | `public-subnet` | `10.0.0.0/24` |
| Subnet | `private-subnet` | `10.0.1.0/24`, no public IPs |
| NSG | `arm-flex-vps-nsg` | TCP 9001 (Portainer) from anywhere |
| Instance | `arm-flex-vps` | `VM.Standard.A1.Flex`, 4 OCPU / 24 GB, 200 GB boot, private IP `10.0.0.150` |
| Public IP | `arm-flex-vps-reserved-ip` | `RESERVED` lifetime, attached to the instance |

## Layout

```
core/
├── versions.tf              # Terraform + provider version constraints
├── providers.tf             # OCI provider (auth from ~/.oci/config)
├── variables.tf             # inputs
├── locals.tf                # shared tags
├── data.tf                  # availability domain + Oracle services lookups
├── main.tf                  # wires the network and compute modules together
├── outputs.tf               # values printed after apply
├── terraform.tfvars.example # copy to terraform.tfvars
└── modules/
    ├── network/             # VCN, gateways, route tables, security lists, subnets, NSG
    └── compute/             # instance + reserved public IP
```

---

## 1. Prerequisites

```sh
terraform version                 # any version >= 1.5
oci iam region list --output table  # proves ~/.oci/config auth works (asks for the key passphrase)
```

Your API key is passphrase-protected. Terraform cannot prompt for it, so export it in the
shell you run Terraform from. `read -s` keeps it out of shell history:

```sh
read -rs TF_VAR_oci_private_key_password && export TF_VAR_oci_private_key_password
```

Any variable named `foo` can be set through an environment variable `TF_VAR_foo`.

SSH key for the VPS. Create one if you don't have one yet:

```sh
ssh-keygen -t ed25519 -f ~/.ssh/arm-flex-vps -C arm-flex-vps
```

## 2. Configure

```sh
cd ~/home-lab/oracle-vps-a/core
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars          # check compartment_ocid and ssh_public_key_path
```

`terraform.tfvars` is loaded automatically and is gitignored.

## 3. Deploy

```sh
terraform fmt -recursive          # rewrite files into canonical style
terraform init                    # download the oracle/oci provider, set up modules, write .terraform.lock.hcl
terraform validate                # check syntax and types without calling OCI
terraform plan -out=tfplan        # compute the changes and save them to a file
terraform show tfplan             # re-read the saved plan (expect 14 to add, 0 to change, 0 to destroy)
terraform apply tfplan            # apply exactly that saved plan, no second confirmation
```

Commit `.terraform.lock.hcl`. It pins the provider version and checksums.

## 4. Inspect

```sh
terraform output                                  # all outputs
terraform output -raw reserved_public_ip          # one output, without quotes
terraform state list                              # every resource Terraform manages
terraform state show module.compute.oci_core_public_ip.reserved   # full attributes of one resource
terraform console                                 # interactive expression shell, e.g. > module.network.vcn_id
terraform graph | dot -Tsvg > graph.svg           # dependency graph (needs graphviz)
```

## 5. Verify

```sh
# The public IP is RESERVED and ASSIGNED
oci network public-ip get \
  --public-ip-id "$(terraform output -raw reserved_public_ip_id)" \
  --query 'data.{ip:"ip-address",lifetime:lifetime,state:"lifecycle-state"}' --output table

# The instance is RUNNING
oci compute instance get \
  --instance-id "$(terraform output -raw instance_id)" \
  --query 'data.{name:"display-name",state:"lifecycle-state",shape:shape}' --output table

# SSH in (use ssh_user = "opc" in tfvars if the image is Oracle Linux)
$(terraform output -raw ssh_command) -i ~/.ssh/arm-flex-vps

# Drift check: the real infrastructure should match the code
terraform plan                    # expect "No changes. Your infrastructure matches the configuration."
```

## 6. Day-2 operations

```sh
# Change something (e.g. a port in vps_ingress_ports), then review and apply
terraform plan -out=tfplan && terraform apply tfplan

# Rebuild only the VPS. The reserved IP is kept and moves to the new instance.
terraform plan  -replace=module.compute.oci_core_instance.this
terraform apply -replace=module.compute.oci_core_instance.this

# Plan or apply just one part
terraform plan -target=module.network

# Refresh state from OCI without changing anything
terraform apply -refresh-only
```

### Rebuilding the VPS with Tailscale (cloud-init)

`modules/compute/cloud-init.yaml` installs Tailscale on the instance's **first boot** and joins your
tailnet. It only runs on a newly created instance, so the instance has to be rebuilt. Only the
instance and its boot volume are replaced. The network and the reserved IP stay; the IP moves to the
new instance.

> All data on the current boot volume is lost. Back up anything you need (Portainer data, configs) first.
> A1 capacity in Hyderabad can be limited. If the create fails with `Out of host capacity`, run
> `terraform apply` again later.

```sh
# 1. Tailscale admin console → Settings → Keys → Generate auth key (one-off, pre-approved).
#    Put it in terraform.tfvars:   tailscale_auth_key = "tskey-auth-..."

# 2. Plan the rebuild. Expect: 1 to add, 1 to change, 1 to destroy
#    (instance replaced, reserved IP's private_ip_id updated in place)
terraform plan -replace=module.compute.oci_core_instance.this -out=tfplan
terraform show tfplan
terraform apply tfplan

# 3. The VPS has new SSH host keys: forget the old one, then log in
ssh-keygen -R "$(terraform output -raw reserved_public_ip)"
$(terraform output -raw ssh_command) -i ~/.ssh/oracle-vps-a

# 4. On the VPS
cloud-init status --long                      # status: done, no errors
sudo tail -n 30 /var/log/cloud-init-output.log
tailscale status                              # lists your tailnet devices
tailscale ip -4                               # the VPS's 100.x.x.x address

# 5. On your laptop
tailscale ping arm-flex-vps
ssh ubuntu@arm-flex-vps                       # Tailscale SSH: no -i key needed (may open a browser to confirm)

# 6. Remove tailscale_auth_key from terraform.tfvars (it's used up). Thanks to
#    ignore_changes on user_data, this does not touch the instance:
terraform plan                                # expect "No changes"
```

Why `-replace` and not `terraform destroy`: `destroy` would remove everything, including the
reserved IP (blocked by `prevent_destroy`), and `-replace` only rebuilds the one resource. Destroy and
create run in that order, so the old 200 GB boot volume is gone before the new one is created, which
keeps you within the Always Free 200 GB.

### Destroying

The reserved IP has `prevent_destroy = true`, so a plain `terraform destroy` fails on purpose.

- **Keep the IP and remove everything else:** run `terraform state rm module.compute.oci_core_public_ip.reserved`
  first. Terraform then stops tracking the IP, and it stays in OCI unassigned. Then run `terraform destroy`.
- **Remove everything, including the IP:** delete the `lifecycle { prevent_destroy = true }` block in
  `modules/compute/main.tf`, then run `terraform destroy`.

## Notes

- **Lessons learned:** [docs/terraform-lessons.md](docs/terraform-lessons.md) walks through the real errors
  and plan diffs from the first deployment, with explanations.
- **Reading plans:** [docs/reading-terraform-plans.md](docs/reading-terraform-plans.md) explains
  replacement plans, `user_data`/cloud-init, `ignore_changes`, and the `+ ~ -` attribute symbols.

- **State** is stored locally in `terraform.tfstate` (gitignored). Back it up. If you lose it,
  Terraform no longer knows about these resources.
- **Image:** `instance_image_id` pins the same image the old VPS used. Image OCIDs are region-specific.
  Find newer ones with:
  `oci compute image list -c <compartment_ocid> --shape VM.Standard.A1.Flex --operating-system "Canonical Ubuntu" --sort-by TIMECREATED --query 'data[0:5].{name:"display-name",id:id}' --output table`.
  Changing the image replaces the instance.
- **Always Free limits:** A1 is 4 OCPU / 24 GB in total per tenancy, and you get 1 reserved public IP.
