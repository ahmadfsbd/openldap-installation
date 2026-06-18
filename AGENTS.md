# OpenLDAP Project Context

This project is a production-style OpenLDAP deployment for OpenStack VMs.

## Goal

Build an OpenLDAP service that trusted LDAP clients can use through a stable,
private-or-controlled LDAPS endpoint.

Target shape:

```text
trusted LDAP clients
        |
        | ldaps://ldap.example.com:636
        v
OpenStack Octavia TCP load balancer
        |
        v
private OpenLDAP VMs
```

## Key Decisions

- Backend LDAP VMs should stay private.
- Expose LDAP through an OpenStack Octavia TCP load balancer.
- Prefer LDAPS on `636/tcp`.
- Use `389/tcp` only for internal/admin traffic or StartTLS if explicitly
  required.
- Restrict external access with listener `allowed_cidrs` and security groups.
- LDAP clients should connect to the load balancer DNS name, not directly to
  backend VMs.

## Current Scaffold

Existing structure:

- `terraform/`: OpenStack VM, security group, Octavia LB, listener, pool,
  monitor, and optional floating IP scaffold.
- `ansible/`: initial OpenLDAP package/bootstrap scaffold.
- `docs/`: architecture, client integration, and operations notes.

The scaffold is not production-complete yet.

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
- OpenLDAP secure configuration and ACLs.
- Password hashing/bootstrap workflow.
- Dedicated admin and read-only bind accounts.
- LDAP data/config backup and tested restore.
- Multi-node replication, if HA is required.
- Monitoring and alerting.
- Certificate expiry checks.
- Upgrade and patching process.
- Exact client schema mapping for users and groups.

## Client Integration Reminder

LDAP client configuration will need values like:

```text
Hostname/IP: ldap.example.com
Port: 636
TLS/LDAPS: enabled
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

LDAPS connectivity from a client:

```bash
nc -vz ldap.example.com 636
```

LDAP bind/search once credentials exist:

```bash
ldapsearch -x -H ldaps://ldap.example.com:636 \
  -D "cn=ldap-readonly,ou=service-accounts,dc=example,dc=org" \
  -W \
  -b "dc=example,dc=org" \
  "(uid=<username>)"
```

## Current Philosophy

Keep this project infrastructure-focused and production-shaped. Avoid adding
temporary demo LDAP users/passwords or fake lab manifests unless they are clearly
isolated from the production path.
