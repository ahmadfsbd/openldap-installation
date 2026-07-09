---
name: openldap-operations
description: Use when deploying, reviewing, hardening, troubleshooting, or operating this OpenLDAP on OpenStack repository.
---

# OpenLDAP Operations

Use this skill for repository tasks involving Terraform, Ansible, OpenLDAP
configuration, replication, user/group operations, production readiness, or
client integration.

## Workflow

1. Identify the task area:
   - Terraform/OpenStack infrastructure.
   - Ansible/OpenLDAP configuration.
   - LDAP data operations such as users, groups, and service accounts.
   - Production readiness, TLS, monitoring, backup/restore, or failover.
   - Client integration such as Rancher or other LDAP consumers.

2. Read the relevant docs before changing behavior:
   - `README.md`
   - `docs/ARCHITECTURE.md`
   - `docs/PRODUCTION.md`
   - `docs/OPERATIONS.md`
   - `docs/CLIENT_INTEGRATION.md`
   - `docs/LDAP_INTRO.md` when LDAP concepts are unclear.

3. Preserve the current baseline unless the user explicitly asks to harden it:
   - Trusted-network LDAP on `389/tcp`.
   - One load-balancer DNS name for clients.
   - Private backend LDAP VMs.
   - One writable provider and one or more read replicas.
   - Writes target the provider, not the round-robin load balancer.

4. For Terraform work:
   - Run `terraform fmt -check -recursive terraform`.
   - Run `terraform validate` from `terraform/` after provider init exists.
   - Never run `apply`, `destroy`, or state operations unless explicitly asked.
   - Check CIDR/security-group changes carefully because this baseline has no
     TLS.

5. For Ansible work:
   - Run `ansible-playbook -i ansible/inventory.example.ini ansible/playbooks/site.yml --syntax-check`.
   - Keep secrets in ignored local vars or Ansible Vault.
   - Do not print or commit LDAP passwords, replication credentials, or
     generated hashes from real deployments.

6. For LDAP data operations:
   - Use `ldapsearch` for reads.
   - Use `ldapadd`, `ldapmodify`, `ldapdelete`, or `ldappasswd` for changes.
   - Generate LDAP password hashes with `slappasswd`.
   - Prefer `PASSWORD_HASH_FILE` over passing hashes directly on the command
     line.
   - Use `WRITE_SERVER_URL` for writes and keep it pointed at the provider.

7. For production-readiness reviews, always check:
   - TLS or StartTLS plan.
   - Network restrictions and no broad CIDRs unless explicitly demo-only.
   - Off-host encrypted backups and tested restore.
   - Monitoring for LDAP bind/search, `slapd`, disk, backup freshness,
     replication `contextCSN`, and certificate expiry when TLS is enabled.
   - Manual provider promotion runbook.
   - Client schema mapping verified by LDAP searches.

## Useful Commands

```bash
terraform fmt -check -recursive terraform
cd terraform && terraform validate
ansible-playbook -i ansible/inventory.example.ini ansible/playbooks/site.yml --syntax-check
make help
make show-config
```
