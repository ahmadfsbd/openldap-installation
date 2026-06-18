# OpenLDAP On OpenStack

Trusted-network OpenLDAP deployment for shared LDAP access on OpenStack VMs.

This repository builds an LDAP service with one client-facing DNS record:

```text
trusted LDAP clients
        |
        | ldap://ldap.example.com:389
        v
OpenStack Octavia TCP load balancer
        |
        +-- openldap-1, writable provider
        +-- openldap-2, read replica / consumer
        `-- openldap-N, read replica / consumer
```

## Current Baseline

This baseline intentionally uses plain LDAP on `389/tcp` with no TLS.

Use it only when LDAP traffic is restricted to trusted networks. LDAP bind
passwords and replication credentials are plaintext on the network.

Key decisions:

- One DNS record only: `ldap.example.com` points to the load balancer VIP.
- Backend LDAP VMs stay private and do not need DNS records.
- Ansible connects to backend VMs by private IP.
- OpenLDAP replication uses private IP LDAP URIs on `389/tcp`.
- Normal clients use the load balancer for bind/search traffic.
- Administrative writes target the current provider node, not the round-robin
  load balancer.

For broader exposure, use LDAPS on `636/tcp` or StartTLS on `389/tcp` instead
of this no-TLS baseline.

## What This Repo Builds

Terraform creates:

- Private OpenStack LDAP VMs. `instance_count` controls the total number of
  backend VMs: one provider plus one or more read replicas.
- A backend VM security group with SSH and LDAP rules.
- Octavia TCP load balancer on `389/tcp`.
- Listener source CIDR restrictions.
- Backend pool members.
- Optional floating IP for the load balancer.

Security rule inputs:

- `ldap_allowed_cidrs` controls who can reach the Octavia listener. Octavia
  listener allowlists are CIDR-based.
- `ssh_allowed_cidrs` or `ssh_allowed_security_group_ids` control SSH to LDAP
  VMs.
- `backend_allowed_cidrs` or `backend_allowed_security_group_ids` control direct
  LDAP access to backend VMs.

The load balancer front door is restricted by Octavia listener `allowed_cidrs`.
The backend VM ports use the LDAP backend security group. In production, clients
should enter through the load balancer, while backend VM `389/tcp` stays limited
to the load-balancer/backend network and LDAP peer nodes.

Ansible configures:

- `slapd` / OpenLDAP on each VM.
- LDAP and LDAPI listeners.
- MDB backend settings, indexes, limits, and ACLs.
- One writable provider and one or more read replicas with `syncrepl`.
- Read-only application bind account.
- Replication bind account.
- Optional initial directory bootstrap.
- Local `slapcat` backups for LDAP data and `cn=config`.

This repo does not install a web login page or LDAP web admin UI. Browser-based
applications use LDAP behind the scenes, but LDAP itself is a network protocol.

## Read The Docs In Order

1. [docs/LDAP_INTRO.md](docs/LDAP_INTRO.md)  
   LDAP basics: DNs, OUs, object classes, bind users, search bases, ports, and
   backend database concepts.

2. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)  
   Infrastructure shape: OpenStack VMs, load balancer, ports, one DNS record,
   private backend IPs, and HA model.

3. [docs/PRODUCTION.md](docs/PRODUCTION.md)  
   Deployment baseline: security boundary, provider/consumer replication,
   required inputs, Ansible flow, verification, and failover notes.

4. [docs/CLIENT_INTEGRATION.md](docs/CLIENT_INTEGRATION.md)  
   Values to give applications that need LDAP authentication or lookup.

5. [docs/OPERATIONS.md](docs/OPERATIONS.md)  
   Secrets, backup/restore, monitoring, replication checks, and change safety.

## Repository Layout

- `terraform/`: OpenStack VMs, security group rules, Octavia load balancer,
  listener, pool members, outputs, and example variables.
- `ansible/`: inventory example, OpenLDAP variables, playbook, LDIF templates,
  and backup timer templates.
- `scripts/`: local helper scripts for the Ansible virtualenv and generated
  inventory.
- `docs/`: LDAP intro, architecture, production flow, client integration, and
  operations runbook.

## Deployment Workflow

1. Copy Terraform variables:

   ```bash
   cp terraform/terraform.tfvars.example terraform/terraform.tfvars
   $EDITOR terraform/terraform.tfvars
   ```

2. Deploy infrastructure:

   ```bash
   cd terraform
   terraform init
   terraform plan
   terraform apply
   ```

3. Create one DNS record:

   ```text
   ldap.example.com -> <ldap_load_balancer_ip>
   ```

4. Build an Ansible inventory from Terraform outputs:

   ```bash
   cd ..
   ANSIBLE_SSH_PRIVATE_KEY_FILE=~/.ssh/id_rsa scripts/render-ansible-inventory.sh
   ```

   The generated inventory makes `openldap-1` the writable provider and every
   later host, such as `openldap-2` or `openldap-3`, a read replica.

5. Copy Ansible variables and prepare secrets:

   ```bash
   cp ansible/group_vars/openldap.example.yml ansible/group_vars/openldap.yml
   $EDITOR ansible/group_vars/openldap.yml
   ```

   Use Ansible Vault for secrets. Generate LDAP password hashes with
   `slappasswd`; do not store plaintext LDAP account passwords in git. For the
   first deployment only, set `ldap_apply_bootstrap_data: true` after the
   password hashes are final.

6. Run Ansible:

   ```bash
   source scripts/setup-ansible-venv.sh
   ansible-playbook -i ansible/inventory.ini ansible/playbooks/site.yml
   ```

   Add `--ask-vault-pass` only when `ansible/group_vars/openldap.yml` is
   encrypted with Ansible Vault.

   Ubuntu 24.04 targets use Python 3.12. If an older Ansible controller fails
   during fact gathering with `No module named 'ansible.module_utils.six.moves'`,
   run the setup script above so `ansible-core>=2.16` is used.

7. After the first successful bootstrap, set `ldap_apply_bootstrap_data: false`
   and rerun Ansible once. This leaves future runs in normal steady-state mode.

## Scaling Read Replicas

To add more read replicas, increase `instance_count` in
`terraform/terraform.tfvars`, then apply Terraform:

```hcl
instance_count = 3
```

```bash
cd terraform
terraform apply
cd ..
ANSIBLE_SSH_PRIVATE_KEY_FILE=~/.ssh/id_rsa scripts/render-ansible-inventory.sh
source scripts/setup-ansible-venv.sh
ansible-playbook -i ansible/inventory.ini ansible/playbooks/site.yml
```

The first inventory host stays the writable provider. Each additional backend VM
is configured as a read replica with its own `olcServerID`, LDAP listener URI,
and `syncrepl` consumer config.

## Teardown And Fresh Start

Preferred teardown is Terraform-managed:

```bash
cd terraform
terraform destroy
```

If resources are deleted manually in OpenStack, also clear the matching local
Terraform state before the next deployment. Otherwise Terraform may try to
refresh resources that no longer exist:

```bash
cd terraform
terraform state list
terraform state rm <resource-address> ...
```

If everything was deleted manually, it is also fine to remove the ignored local
state files `terraform/terraform.tfstate*`. After a fresh `terraform apply`,
regenerate `ansible/inventory.ini` with `scripts/render-ansible-inventory.sh`.

## Client Connection Values

Applications should connect through the single load balancer DNS name. The
full client field list is in
[docs/CLIENT_INTEGRATION.md](docs/CLIENT_INTEGRATION.md).

Quick connectivity check:

```bash
nc -vz ldap.example.com 389
```

Quick bind/search check:

```bash
ldapsearch -x -H ldap://ldap.example.com:389 \
  -D "cn=ldap-readonly,ou=service-accounts,dc=example,dc=org" \
  -W \
  -b "ou=users,dc=example,dc=org" \
  "(uid=<username>)"
```

## Safety Notes

Terraform accepts broad CIDRs such as `0.0.0.0/0`. With no TLS, broad LDAP
access exposes plaintext bind traffic on `389/tcp`; use only throwaway demo
credentials/data when opening access widely.

Do not commit:

- `terraform/terraform.tfvars`
- Terraform state or plans.
- Ansible inventory with sensitive real IPs.
- Ansible Vault files unless intentionally encrypted and expected.
- LDAP admin passwords.
- Read-only bind account passwords.
- Replication credentials.
- LDAP backup exports.

Before real use, finish and test:

- Restore drills from `slapcat` backups.
- Monitoring and alerting.
- Replication health checks.
- Provider promotion/failover runbook.
- Exact client schema mapping for users and groups.
- Patch and upgrade procedure.
- Network controls proving only trusted clients can reach `389/tcp`.

## Useful Checks

Terraform formatting:

```bash
terraform fmt -check -recursive terraform
```

Terraform validation, after provider installation:

```bash
cd terraform
terraform init
terraform validate
```

Ansible syntax, once Ansible is installed:

```bash
ansible-playbook -i ansible/inventory.example.ini ansible/playbooks/site.yml --syntax-check
```
