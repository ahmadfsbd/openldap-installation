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

## POSIX User And Group IDs

This baseline supports Linux-style numeric IDs, so user and group entries can
include:

```ldif
uidNumber: 2001
gidNumber: 2001
homeDirectory: /home/bob
```

```ldif
gidNumber: 2001
memberUid: bob
```

The OpenLDAP server loads the POSIX/NIS schema during provisioning, which allows
`posixAccount` and `posixGroup` entries to use these attributes. The helper in
`Makefile` emits the required `posixAccount` values when you pass `UID_NUMBER`
and `GID_NUMBER`, using `/home/<uid>` for `homeDirectory` unless you override it
with `HOME_DIRECTORY`. For group creation, it emits `posixGroup` values when you
pass `GID_NUMBER`.

`homeDirectory` is required by the standard `posixAccount` object class because
it models a Unix-style login account, similar to an `/etc/passwd` entry. The LDAP
value is only a path string, such as `/home/bob`; adding it to LDAP does not
create that directory on any host. If Linux clients use LDAP for logins, the
directory must exist on the login host or be provided by shared storage such as
NFS or autofs. Application-only LDAP users that do not need Unix UID/GID values
can stay as non-POSIX `inetOrgPerson` entries instead.

Example user creation:

```bash
make add-user \
  NAME=bob \
  UID_NUMBER=2001 \
  GID_NUMBER=2001 \
  HOME_DIRECTORY=/home/bob \
  CN="Bob Smith" \
  GIVEN_NAME=Bob \
  SN=Smith \
  MAIL=bob@example.org \
  PASSWORD_HASH_FILE=/tmp/bob.hash
```

Example group creation:

```bash
make add-group \
  NAME=dev \
  GID_NUMBER=2001 \
  MEMBER_NAME=bob
```

Example update of an existing user or group:

```bash
make update-user NAME=bob UID_NUMBER=2501 GID_NUMBER=2501 HOME_DIRECTORY=/home/bob
make update-group NAME=dev GID_NUMBER=3001
```

This is useful for Linux clients and Unix-like apps that need stable numeric
UID/GID values instead of only `inetOrgPerson` and `groupOfNames` entries.

## Read The Docs In Order

1. [docs/LDAP_INTRO.md](docs/LDAP_INTRO.md)  
   LDAP basics: DNs, OUs, object classes, bind users, search bases, ports, and
   backend database concepts.

2. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)  
   Infrastructure shape: OpenStack VMs, load balancer, ports, one DNS record,
   private backend IPs, and HA model.

3. [docs/PRODUCTION.md](docs/PRODUCTION.md)  
   Deployment baseline: security boundary, provider/consumer replication,
   required inputs, Ansible flow, verification, production hardening, and
   failover notes.

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
- `Makefile`: convenience wrappers for LDAP search and simple user/group
  management commands.
- `docs/`: LDAP intro, architecture, production flow, client integration, and
  operations runbook.
- `AGENTS.md`: project instructions for future coding agents.
- `.github/copilot-instructions.md`: GitHub Copilot repository instructions.
- `.github/skills/openldap-operations/SKILL.md`: reusable operations skill for
  LDAP, Terraform, Ansible, and production-readiness work.

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

For repeatable search and simple user/group commands, see the Makefile examples
in [docs/OPERATIONS.md](docs/OPERATIONS.md).

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

Before real use, finish and test the hardening runbook in
[docs/PRODUCTION.md](docs/PRODUCTION.md):

- TLS or StartTLS.
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
