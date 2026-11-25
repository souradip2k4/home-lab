# Reading Terraform plans: replacements, `user_data`, and attribute symbols

Notes from adding cloud-init (Tailscale) to `arm-flex-vps`, written to revise later. All examples
come from real `terraform plan` output for this stack (long OCIDs shortened).

Related: [terraform-lessons.md](terraform-lessons.md) covers plan basics, deferred data sources and
the first-deployment errors.

---

## 1. What happened

1. cloud-init was added to the instance as `metadata.user_data` (see section 2).
2. `lifecycle { ignore_changes = [metadata["user_data"]] }` was commented out as an experiment.
3. A plain `terraform plan`, with no `-replace`, then wanted to **rebuild the VPS**:

```
  # module.compute.oci_core_instance.this must be replaced
-/+ resource "oci_core_instance" "this" {
      ...
      ~ metadata = { # forces replacement
          + "user_data"           = (sensitive value)
            # (1 unchanged element hidden)
        }
      ...
Plan: 1 to add, 1 to change, 1 to destroy.
```

The rest of this document explains each part of that output.

---

## 2. What `user_data` is

`user_data` is one key in the instance's `metadata` map. It carries the **cloud-init script** to the VM.

```hcl
metadata = {
  ssh_authorized_keys = var.ssh_authorized_keys
  user_data = base64encode(templatefile("${path.module}/cloud-init.yaml", {
    tailscale_auth_key = var.tailscale_auth_key
    hostname           = var.name
  }))
}
```

How it reaches the VM:

```
cloud-init.yaml          template: install Tailscale, run tailscale up
   │ templatefile()      fills in ${tailscale_auth_key} and ${hostname}
   ▼
#cloud-config text
   │ base64encode()      OCI requires user_data in base64
   ▼
metadata["user_data"]    sent to OCI when the instance is created
   │
   ▼
metadata service         http://169.254.169.254/opc/v2/instance/ (reachable only from inside the VM)
   │
   ▼
cloud-init               runs it once, on the first boot
```

Each part of the plan line:

| Part | Meaning |
|---|---|
| `+ "user_data"` | The running VPS was created without `user_data`. The code now has it, so it's an addition. |
| `(sensitive value)` | It contains `var.tailscale_auth_key` (marked `sensitive`), so Terraform hides it. |
| `(1 unchanged element hidden)` | `ssh_authorized_keys`, which didn't change. |
| `# forces replacement` | In the OCI provider, `user_data` can't be changed on a running instance. A change means a new instance. |

Check what an instance received (run this on the VPS):

```sh
curl -s -H "Authorization: Bearer Oracle" \
  http://169.254.169.254/opc/v2/instance/metadata/user_data | base64 -d
```

> The output includes the auth key. Any process on the VM can read it, and it's also stored in
> `terraform.tfstate`. That's why a **one-time** Tailscale key is used: once used, it's worthless.

---

## 3. `ignore_changes`: why it's needed here

```hcl
lifecycle {
  ignore_changes = [metadata["user_data"]]
}
```

| | With `ignore_changes` | Without it |
|---|---|---|
| `terraform plan` | `No changes` | `must be replaced` (rebuild!) |
| `terraform plan -replace=...` | Rebuild, using the current `user_data` | Rebuild |
| Removing the used key from `tfvars` | Nothing happens | **Another rebuild** |

- `ignore_changes` only stops **updates** caused by that attribute. A **newly created** instance
  (first apply or `-replace`) still gets the full config, including the current `user_data`.
- Without it, every plain `terraform apply` would rebuild the VPS and wipe its boot volume.

### Two kinds of replacement header

| Header | Cause |
|---|---|
| `will be replaced, as requested` | You used `-replace=<address>` |
| `must be replaced` | Terraform decided: an attribute marked `# forces replacement` changed |

**Lesson:** when you see `must be replaced` and didn't expect it, search the plan for
`# forces replacement`. That line names the cause.

---

## 4. Why a replacement plan is so long

Replacing means planning a **brand-new object**. Every value that **OCI generates** (IDs,
timestamps, hardware details) can't be known until the new object exists, so it's shown as
`(known after apply)`.

That's noise, not real change. In a replacement plan, look for only:

1. The header: `as requested` or `must be replaced`
2. Lines marked `# forces replacement`
3. The totals: `Plan: X to add, Y to change, Z to destroy`

Examples from this plan:

| Line | Why it's shown | Real change? |
|---|---|---|
| `~ id`, `boot_volume_id`, `time_created` → `(known after apply)` | New object, new values from OCI | New IDs only |
| `~ image = "ocid1.image..." -> (known after apply)` | Read back from OCI after create | No, same `source_id` in code |
| `~ private_ip = "10.0.0.150" -> (known after apply)` | Read back after create | No, code sets `10.0.0.150` |
| `~ public_ip = "129.225.79.8" -> (known after apply)` | The instance's view of its public IP | No, the reserved IP is reattached |
| `~ defined_tags` `Oracle-Tags.CreatedBy/CreatedOn` | OCI adds these on every create | New timestamp only |
| `~ shape_config { vcpus = 4 -> (known after apply) ... }` | Hardware details reported by OCI | No, still 4 OCPU / 24 GB |
| Reserved IP `~ private_ip_id -> (known after apply)` | Points at the new instance's private IP | Same IP address, reattached |

Data sources are also postponed, this time for a different reason than in
[terraform-lessons.md](terraform-lessons.md):

```
  # module.compute.data.oci_core_vnic_attachments.this will be read during apply
  # (config refers to values not yet known)
      + instance_id = (known after apply)
```

On an **update**, the instance ID is known (`depends on a resource ... with changes pending`).
On a **replacement**, the new instance ID is itself unknown (`config refers to values not yet known`).

---

## 5. Attribute symbols

The symbol in front of an attribute compares the **old value (state)** with the **new value
(plan)**. It does **not** tell you whether the field is in your code.

| Symbol | Old value | New value | Example |
|---|---|---|---|
| `+` | null | something, or `(known after apply)` | `+ capacity_reservation_id = (known after apply)` |
| `~` | a value | a different value, or `(known after apply)` | `~ private_ip = "10.0.0.150" -> (known after apply)` |
| `-` | a value | null | `- assign_private_dns_record = false -> null` |
| *(hidden)* | a value | the same value | `# (7 unchanged attributes hidden)` |

Proof that the symbol isn't about "in code or not": `user_data` **is** in the code and still shows
`+`, because the old instance had no `user_data`.

If you set a field in your code:

- **Same value as now** → hidden (e.g. `shape`, `display_name`, `fault_domain`)
- **Different value** → `~ old -> new`
- **No value now** → `+ new`

---

## 6. Optional vs Optional + Computed

Each attribute in the provider schema is one of these. It decides what the plan shows when **your
code doesn't set it**:

| Schema | Meaning | Not set in code, so the plan shows |
|---|---|---|
| **Optional** | Only you set it | `null` (Terraform plans exactly what the code says) |
| **Optional + Computed** | You may set it, otherwise OCI decides | `(known after apply)` (Terraform waits for OCI) |
| **Computed** only | Always set by OCI (IDs, timestamps) | `(known after apply)` on create |

From the same block in this plan:

```
~ create_vnic_details {
    ~ assign_ipv6ip             = false -> (known after apply)   # Optional + Computed
    - assign_private_dns_record = false -> null                  # Optional only
```

### `- field = false -> null` doesn't remove anything

`null` means "not set in code", so Terraform doesn't send the field when creating the instance. OCI
then applies its default (`false`), and the new VNIC ends up the same as the old one.
`- is_preserve_boot_volume_enabled = false -> null` in `source_details` is the same case.

This never appeared in normal plans because, on an **update**, the provider doesn't treat "unset"
and `false` as different. A **replacement** plans the whole object from code, so it shows up there.

---

## 7. `null` vs `(known after apply)`

| | Meaning |
|---|---|
| `null` | **No value.** The feature isn't used, or the field is unset. |
| `(known after apply)` | **There may be a value, but it isn't known yet.** OCI decides during apply. |

The current VPS runs fine with these fields null, because they're optional features it doesn't use:

| Field | Has a value only when... |
|---|---|
| `capacity_reservation_id` | The instance launches into reserved capacity |
| `dedicated_vm_host_id` | It runs on a dedicated host |
| `compute_cluster_id` | It's part of an HPC/RDMA cluster |
| `instance_configuration_id` | It was created from an instance configuration or pool |
| `ipxe_script` | It network-boots with iPXE |
| `time_maintenance_reboot_due` | OCI has scheduled a maintenance reboot |

`+ capacity_reservation_id = (known after apply)` doesn't mean the value is needed. It means:
"null on the old instance, and I'll find out what OCI reports for the new one". After the rebuild,
these stay null and stop appearing.

---

## 8. Rule: when does an unused field appear?

For a field that's **null on the current resource**:

| Plan type | OCI can fill it in (Computed)? | Shown as |
|---|---|---|
| Update in place | — | Hidden |
| Create / replace | Yes | `+ field = (known after apply)` |
| Create / replace | No | Hidden (null → null) |

For a field that **has a value now** but isn't in your code, during a replacement:

| OCI can fill it in (Computed)? | Shown as |
|---|---|
| Yes | `~ field = old -> (known after apply)` (e.g. `private_ip`) |
| No | `- field = old -> null` (e.g. `assign_private_dns_record`) |

---

## 9. Data sources always show `+`, never `~`

```
  # module.compute.data.oci_core_private_ips.primary will be read during apply
  # (config refers to values not yet known)
 <= data "oci_core_private_ips" "primary" {
      + id          = (known after apply)
      + private_ips = (known after apply)
      + vnic_id     = (known after apply)
    }
```

The state file has a value from the last read, so why `+` and not `~`?

| | Resource | Data source |
|---|---|---|
| What it is | An object Terraform owns and changes | A lookup: a query sent to OCI |
| Plan compares | Old state value → new value (`~`) | Nothing. Every read is a fresh answer. |
| Shown in the plan | Only attributes that differ | The whole result, shown as new |

- A data source has no "update". Terraform **reads it again and discards the old result**.
- **`<=`** on the block is the action: read this lookup during apply.
- **`+`** on its attributes has no "old → new" meaning. It's how Terraform displays a result that
  doesn't exist yet.
- You'll never see `~` or `-` inside a `<=` block, even if the read returns the same value as last
  time (as it did here: the same private IP).

---

## 10. Checklist before applying a replacement

```sh
terraform plan -replace=module.compute.oci_core_instance.this -out=tfplan
terraform show tfplan | grep -E "^  # "      # list only the resource headers
```

- [ ] The headers list only the expected resources (here: the instance replaced, the reserved IP
      updated, two data sources read). Nothing under `module.network`.
- [ ] The totals are exactly what you expect (here: `1 to add, 1 to change, 1 to destroy`).
- [ ] Every `# forces replacement` line is one you understand.
- [ ] Anything on the boot volume that you need is backed up. A replaced instance gets a new boot volume.
- [ ] `ignore_changes` is back in place before any later plain `apply`.

Then: `terraform apply tfplan`.
