# OpenLDAP Repository Instructions

This repository builds a production-shaped OpenLDAP deployment on OpenStack.
The current baseline is trusted-network LDAP on `389/tcp` with no TLS. Treat
LDAPS on `636/tcp` or StartTLS as the production hardening path before broader
exposure.

## Project Shape

- `terraform/` creates OpenStack LDAP VMs, backend security-group rules, an
  Octavia TCP load balancer, listener, pool, monitor, outputs, and optional
  floating IP.
- `ansible/` installs and configures OpenLDAP, ACLs, one writable provider,
  read replicas with `syncrepl`, service accounts, and local `slapcat` backups.
- `scripts/` contains helper scripts for the Ansible virtualenv and generated
  inventory.
- `docs/` contains LDAP concepts, architecture, production, client integration,
  and operations guidance.
- `Makefile` wraps LDAP search and simple user/group management commands.

## Rules

- Backend LDAP VMs stay private.
- Clients connect through the load-balancer DNS name, not backend VM IPs.
- Administrative writes must target the provider node or local `ldapi:///`, not
  the round-robin load balancer.
- Search helpers may use `SERVER_URL`; write helpers must use
  `WRITE_SERVER_URL`.
- Do not commit real tfvars, Terraform state, Ansible inventories with sensitive
  IPs, Vault files unless intentionally encrypted, LDAP passwords, replication
  credentials, TLS private material, or LDAP backup exports.
- Keep changes scoped and prefer the existing Terraform, Ansible, shell, and
  Markdown patterns in the repo.

## Checks

```bash
terraform fmt -check -recursive terraform
cd terraform && terraform validate
ansible-playbook -i ansible/inventory.example.ini ansible/playbooks/site.yml --syntax-check
make help
```
