# OpenLDAP Project Context

This project is a production-style OpenLDAP deployment for OpenStack VMs.

## Goal

Build an OpenLDAP service that trusted LDAP clients can use through a stable
load-balancer DNS name. The current implementation is a trusted-network
`ldap://` baseline on `389/tcp`; the production hardening path is LDAPS on
`636/tcp` or StartTLS on `389/tcp`.

Current shape:

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

## Key Decisions

- Backend LDAP VMs should stay private.
- Expose LDAP through an OpenStack Octavia TCP load balancer.
- The current baseline uses plain LDAP on `389/tcp` and must be restricted to
  trusted networks.
- Prefer LDAPS on `636/tcp` or StartTLS before broader production exposure.
- Restrict external access with listener `allowed_cidrs` and security groups.
- LDAP clients should connect to the load balancer DNS name, not directly to
  backend VMs.
- Administrative writes should target the provider node, not the round-robin
  load balancer.

## Current Structure

Existing structure:

- `terraform/`: OpenStack VM, security group, Octavia LB, listener, pool,
  monitor, outputs, and optional floating IP scaffold.
- `ansible/`: OpenLDAP package/bootstrap, ACL, replication, and backup scaffold.
- `scripts/`: Ansible virtualenv and inventory generation helpers.
- `docs/`: architecture, client integration, and operations notes.
- `Makefile`: LDAP search and simple user/group management helpers.

The baseline is usable for trusted-network testing, but is not fully
production-complete until the hardening checklist in `docs/PRODUCTION.md` has
been implemented and tested.

## Do Not Commit

Never commit:

- `terraform/terraform.tfvars`
- Terraform state or plans.
- Ansible inventory with real IPs if sensitive.
- Ansible Vault files unless intentionally encrypted and expected.
- LDAP admin passwords.
- Read-only bind account passwords.
- TLS private keys, certificates, or CA material.
- Replication credentials.

See `.gitignore`.

## Production Gaps To Finish

Before real use, implement and test:

- TLS certificate issuance and renewal.
- LDAPS or StartTLS listener and client configuration.
- Provider-only write tooling and documented operational process.
- Off-host encrypted LDAP data/config backups and tested restore.
- Monitoring and alerting.
- Certificate expiry checks.
- Replication health checks and provider promotion drills.
- Upgrade and patching process.
- Exact client schema mapping for users and groups.

## Client Integration Reminder

LDAP client configuration will need values like:

```text
Hostname/IP: ldap.example.com
Port: 389
TLS/LDAPS: disabled in the current trusted-network baseline
Bind DN: cn=ldap-readonly,ou=service-accounts,dc=example,dc=org
User Search Base: ou=users,dc=example,dc=org
Group Search Base: ou=groups,dc=example,dc=org
```

## Useful Checks

Terraform formatting:

```bash
terraform fmt -check -recursive terraform
```

Ansible syntax, once inventory/vars are prepared:

```bash
ansible-playbook -i ansible/inventory.ini ansible/playbooks/site.yml --syntax-check
```

LDAP connectivity from a client:

```bash
nc -vz ldap.example.com 389
```

LDAP bind/search once credentials exist:

```bash
ldapsearch -x -H ldap://ldap.example.com:389 \
  -D "cn=ldap-readonly,ou=service-accounts,dc=example,dc=org" \
  -W \
  -b "dc=example,dc=org" \
  "(uid=<username>)"
```

## Current Philosophy

Keep this project infrastructure-focused and production-shaped. Avoid adding
temporary demo LDAP users/passwords or fake lab manifests unless they are clearly
isolated from the production path.
