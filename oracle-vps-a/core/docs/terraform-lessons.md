# Terraform lessons: real issues from deploying `oracle-vps-a/core`

Notes from the first deployment of this stack, written to revise later. Each section covers
what happened, why, and the Terraform concept behind it.

---

## 1. `terraform plan` showed changes right after a successful `apply`

### What I saw

`terraform apply` created everything. Without touching the code, I ran `terraform plan` again
and got this:

```
Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the
following symbols:
  ~ update in-place
 <= read (data resources)

Terraform will perform the following actions:

  # module.compute.data.oci_core_private_ips.primary will be read during apply
  # (config refers to values not yet known)
 <= data "oci_core_private_ips" "primary" {
      + id          = (known after apply)
      + private_ips = (known after apply)
      + vnic_id     = (known after apply)
    }

  # module.compute.data.oci_core_vnic_attachments.this will be read during apply
  # (depends on a resource or a module with changes pending)
 <= data "oci_core_vnic_attachments" "this" {
      + compartment_id   = "ocid1.tenancy.oc1..aaaaaaaa2mfn..."
      + id               = (known after apply)
      + instance_id      = "ocid1.instance.oc1.ap-hyderabad-1.anuhsljrrmawioqcnewcas..."
      + vnic_attachments = (known after apply)
    }

  # module.compute.oci_core_instance.this will be updated in-place
  ~ resource "oci_core_instance" "this" {
        id                          = "ocid1.instance.oc1.ap-hyderabad-1.anuhsljrrmawioqcnewcas..."
        # (24 unchanged attributes hidden)

      ~ launch_options {
          ~ is_pv_encryption_in_transit_enabled = false -> true
            # (6 unchanged attributes hidden)
        }

        # (6 unchanged blocks hidden)
    }

  # module.compute.oci_core_public_ip.reserved will be updated in-place
  ~ resource "oci_core_public_ip" "reserved" {
        id                   = "ocid1.publicip.oc1.ap-hyderabad-1.amaaaaaarmawioqafu6wings..."
      ~ private_ip_id        = "ocid1.privateip.oc1.ap-hyderabad-1.abuhsljr52lg3rv3kgns..." -> (known after apply)
        # (11 unchanged attributes hidden)
    }

Plan: 0 to add, 2 to change, 0 to destroy.
```

There were four blocks but only **one real problem**. Everything else followed from it.

### Background: what `terraform plan` actually does

```
1. Load      read the .tf code + terraform.tfstate
2. Refresh   call the OCI API for the real current values of every resource in state
             ("Refreshing state... [id=...]" lines)
3. Read data run data sources (lookups) whose inputs are known and not waiting on a pending change
             ("data.x: Reading... / Read complete" lines)
4. Diff      compare the code (desired) with the refreshed reality (actual) and print only the differences
```

- The state file maps each resource address to a real object
  (`module.compute.oci_core_instance.this` → `ocid1.instance...`). It tells Terraform *which*
  objects to check. The comparison is made against **reality from the refresh**, not just the file.
- `plan` writes nothing to OCI and nothing to `terraform.tfstate`.

Symbols in the plan:

| Symbol | Meaning |
|---|---|
| `+` | create |
| `-` | destroy |
| `~` | update in place |
| `-/+` | destroy then re-create (replace) |
| `<=` | read a data source, shown only when the read is **postponed to apply time** |

### Block by block

#### A. `oci_core_instance.this`: `is_pv_encryption_in_transit_enabled = false -> true` (the real change)

- `~ resource "oci_core_instance" "this"` is only the header: "this resource will be updated".
  The actual change is the one attribute underneath; everything else is hidden as "unchanged".
- The OCI provider has **two fields with the same name**:

  | Field | Applied by OCI |
  |---|---|
  | top-level `is_pv_encryption_in_transit_enabled` | **only at create** |
  | `launch_options { is_pv_encryption_in_transit_enabled }` | **only on update** (marked "Deprecated during create") |

- The original code set only the `launch_options` field. OCI ignored it during create, so the VPS
  was created with encryption **off**.
- On the next plan, step 2 (refresh) read `false` from OCI, step 4 compared that with `true` in the
  code, and the result was `false -> true`.
- **Lesson:** the plan doesn't say "a line is missing". It says "this line says X, but reality is Y".
  Here the cause was a field the provider ignores during create.

#### B. `data.oci_core_vnic_attachments.this`: postponed (`depends on a resource ... with changes pending`)

- Data sources are normally read silently during plan and **don't appear in the action list**.
  They only show up (with `<=`) when Terraform has to wait until apply to read them.
- This lookup takes `instance_id = oci_core_instance.this.id`. The instance had a pending change
  (A), so Terraform refused to read data based on a resource that is about to change, because the
  result could be stale.
- `instance_id` **is printed with a real value**. The plan shows **resolved values, not
  expressions**, so you see `ocid1.instance...`, not `oci_core_instance.this.id`. The value was
  known; the delay came from the dependency's *pending change*.
- `instance_id` isn't *compared* with anything. It's an input to a lookup. Only attributes of
  `resource` blocks are compared.

#### C. `data.oci_core_private_ips.primary`: postponed (`config refers to values not yet known`)

- Its input `vnic_id` comes from the result of lookup B. B was postponed, so `vnic_id` was really
  unknown at plan time (`vnic_id = (known after apply)`), and this lookup had to wait too.
- The two comments give **two different reasons** for postponing:
  - `depends on a resource ... with changes pending`: the input is known, but a dependency is about to change.
  - `config refers to values not yet known`: the input itself is unknown.

#### D. `oci_core_public_ip.reserved`: `private_ip_id -> (known after apply)` (not a real change)

- The reserved IP takes `private_ip_id` from lookup C. C's result was unknown at plan time, so
  Terraform couldn't prove the value would stay the same. It marked it `(known after apply)` and
  counted it as an update.
- During apply the lookups returned **the same private IP**, so nothing changed on the IP.
- This is Terraform being cautious ("might change"), not detecting a real change.

### The whole chain

```
oci_core_instance.this          real change: encryption false -> true
  └─▶ data.oci_core_vnic_attachments   postponed: depends on a resource with pending changes
        └─▶ data.oci_core_private_ips  postponed: its input (vnic_id) is unknown
              └─▶ oci_core_public_ip.reserved   private_ip_id -> (known after apply) → counted as "update"

"2 to change" = 1 real change + 1 cautious change that follows from it
```

### Fix

Added the create-time flag in `modules/compute/main.tf` and kept the update-time one:

```hcl
resource "oci_core_instance" "this" {
  # ...
  is_pv_encryption_in_transit_enabled = true   # honoured at create

  launch_options {
    # ...
    is_pv_encryption_in_transit_enabled = true # honoured on update
  }
}
```

Editing a `.tf` file changes **nothing** in OCI. Only `terraform apply` does. After
`plan` → `apply`, a final `terraform plan` printed:

```
No changes. Your infrastructure matches the configuration.
```

With nothing pending on the instance, lookups B and C run normally during plan, D's value is
known and identical, and all four blocks disappear.

### Takeaways

- **Always run `terraform plan` right after the first `apply`.** It's the quickest way to catch
  provider fields that don't do what they appear to do.
- When a plan has many changes, **find the real one first**. Postponed data sources (`<=`) and
  `(known after apply)` values are often just side effects of it.
- Read the provider docs for **(Updatable)** and **"only during create"**. Fields that can't be
  updated force a **replace** (`-/+`).
- `terraform graph` shows the dependency edges that the plan output doesn't.

---

## 2. `Reference to undeclared resource`

```
Error: Reference to undeclared resource
  on main.tf line 18, in module "compute":
  18:   availability_domain = data.oci_identity_availability_domains.this.availability_domains[0].name
A data resource "oci_identity_availability_domains" "this" has not been declared in the root module.
```

- **Cause:** `data.tf` declared `oci_identity_availability_domain` (singular), but `main.tf`
  referenced `oci_identity_availability_domains` (plural). These are **two different data
  sources** with different arguments and outputs.
- **Fix:** use the singular one consistently. It needs `ad_number` (or `id`) and exposes `.name`:
  ```hcl
  data "oci_identity_availability_domain" "this" {
    compartment_id = var.compartment_ocid
    ad_number      = 1
  }
  # main.tf
  availability_domain = data.oci_identity_availability_domain.this.name
  ```
- **Lesson:** `terraform validate` catches broken references without calling OCI. Run it before
  `plan`. A reference has the form `data.<TYPE>.<NAME>.<ATTRIBUTE>`, and the type must match the
  declaration exactly.

---

## 3. `did not find a proper configuration for private key`

```
Error: can not create client, bad configuration: did not find a proper configuration for private key
  with provider["registry.terraform.io/oracle/oci"], on providers.tf line 4
```

- **Cause:** the API key `~/.oci/oci_api_key.pem` was in **encrypted PKCS#8** format
  (`-----BEGIN ENCRYPTED PRIVATE KEY-----`). The `oci` CLI (Python) can read it. The Terraform
  provider (Go) cannot, **even with the correct passphrase**. The passphrase was already set
  correctly in `terraform.tfvars`, which ruled that out.
- **Fix:** re-save the **same key** in traditional RSA format, here without a passphrase:
  ```sh
  cp ~/.oci/oci_api_key.pem ~/.oci/oci_api_key.pem.pkcs8.bak
  openssl rsa -in ~/.oci/oci_api_key.pem.pkcs8.bak -out ~/.oci/oci_api_key.pem -traditional
  chmod 600 ~/.oci/oci_api_key.pem
  head -1 ~/.oci/oci_api_key.pem      # -----BEGIN RSA PRIVATE KEY-----
  ```
- Check that the key is the same by comparing fingerprints:
  ```sh
  openssl rsa -in ~/.oci/oci_api_key.pem -pubout -outform DER | openssl md5 -c
  grep fingerprint ~/.oci/config
  ```
  - A fingerprint of `d4:1d:8c:d9:8f:00:b2:04:e9:80:09:98:ec:f8:42:7e` is the **MD5 of empty
    input**. It means `openssl rsa` failed (for example, a wrong passphrase) and `2>/dev/null` hid
    the error. Don't hide stderr while checking.
- **Why no passphrase is asked any more:** the passphrase locks the **file**, not the key. `openssl`
  used it once to decrypt the old file, then wrote the key to the new file without encryption
  (no `-aes256`). Same key, same fingerprint, still accepted by OCI. The file is now protected
  only by `chmod 600`.
- The OCI CLI then warned about a missing `OCI_API_KEY` label. Console-generated keys end with that
  line, and `openssl` dropped it. Add it back with `echo "OCI_API_KEY" >> ~/.oci/oci_api_key.pem`
  (Terraform ignores anything after the `END` line).
- `oci_private_key_password` was removed from `terraform.tfvars`. Its default of `null` means
  "no passphrase".

---

## Quick command reference

```sh
terraform validate                 # syntax and references, no API calls
terraform plan -out=tfplan         # refresh + diff, saved to a file
terraform show tfplan              # re-read the saved plan
terraform apply tfplan             # apply exactly that plan
terraform plan                     # afterwards: expect "No changes"
terraform plan -refresh-only       # show drift only (changes made outside Terraform)
terraform plan -refresh=false      # diff against the state file only (fast, may be stale)
terraform state show <address>     # what Terraform knows about one resource
terraform graph | dot -Tsvg > graph.svg   # dependency graph
```
