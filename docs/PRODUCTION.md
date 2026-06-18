# Trusted-Network Baseline

This project now targets a trusted-network LDAP baseline with a single client
DNS record and no TLS:

```text
trusted LDAP clients
        |
        | ldap://ldap.example.com:389
        v
Octavia TCP load balancer
        |
        +-- openldap-1, writable provider
        +-- openldap-2, read replica / consumer
        `-- openldap-N, read replica / consumer
```

The load balancer is for normal client bind/search traffic. Administrative
writes should go to the provider node, not randomly through the load balancer.

## Security Boundary

This baseline intentionally does not configure TLS. LDAP bind passwords and
replication credentials are sent in plaintext over the network.

Use this only when all of these are true:

- The load balancer listener is restricted to trusted source CIDRs.
- Backend LDAP VMs are private.
- Backend `389/tcp` is reachable only from the load balancer/backend network.
- You accept that traffic inside those networks is not encrypted.

For broader production exposure, use LDAPS on `636/tcp` or StartTLS on
`389/tcp`.

## HA Model

The default model is single-provider replication:

- `openldap-1` is the initial writable provider.
- Other nodes are consumers using `syncrepl` over private LDAP.
- The number of consumers is controlled by Terraform `instance_count`; every
  backend after the first is a read replica.
- All nodes can serve read/search/bind traffic for applications.
- If a consumer fails, the load balancer can continue sending traffic to the
  remaining healthy nodes.
- If the provider fails, read/authentication traffic can continue on consumers,
  but writes are paused until the provider is restored or a replica is promoted.

This avoids split-brain writes. Multi-provider or mirror-mode replication can be
added later, but it must include a clear write-routing design. A round-robin TCP
load balancer alone is not enough for safe active-active writes.

## Backend Database

OpenLDAP stores directory data in a local backend database managed by `slapd`.
For normal modern deployments this is the MDB backend, backed by LMDB.

There are two important local databases:

| Database | Meaning | Backup command |
|----------|---------|----------------|
| `cn=config` | OpenLDAP runtime configuration, schema, ACLs, listener, replication config | `slapcat -n 0` |
| Main MDB database | Directory data such as users, groups, service accounts | `slapcat -n 1` |

This is not usually PostgreSQL or MySQL. The LDAP server itself owns the local
database files, typically under a distro-specific LDAP data directory.

## Deployment Inputs

Before running Ansible, prepare:

- DNS name for the load balancer, for example `ldap.example.com`.
- Private IPs for backend nodes from Terraform outputs, or a generated
  `ansible/inventory.ini` from `scripts/render-ansible-inventory.sh`.
- A modern Ansible controller. Ubuntu 24.04 targets use Python 3.12, so use
  `ansible-core>=2.16` or use an older target image such as Ubuntu 22.04.
- Ansible Vault values for package bootstrap and replication passwords.
- `slappasswd` hashes for LDAP admin, read-only bind, and replication accounts.

Generate password hashes on a trusted machine:

```bash
slappasswd
```

Store the resulting hashes in vaulted Ansible vars:

```yaml
ldap_admin_password_hash: "{SSHA}..."
ldap_readonly_bind_password_hash: "{SSHA}..."
ldap_replication_bind_password_hash: "{SSHA}..."
```

The replication bind password is also needed in plaintext by `syncrepl`, so keep
`ldap_replication_bind_password` in Ansible Vault. OpenLDAP stores that value in
`cn=config` on consumers; protect config backups accordingly. Without TLS, that
password is also sent over the backend network in plaintext.

## Ansible Flow

1. Set up the local Ansible controller:

   ```bash
   source scripts/setup-ansible-venv.sh
   ```

2. Copy variables:

   ```bash
   cp ansible/group_vars/openldap.example.yml ansible/group_vars/openldap.yml
   ```

3. Fill in real values, generate password hashes, and encrypt secrets if this is
   not a throwaway demo:

   ```bash
   ansible-vault encrypt ansible/group_vars/openldap.yml
   ```

   Use `--ask-vault-pass` on later playbook runs only if this file is vaulted.

4. Build inventory from Terraform outputs. The first host is the provider and
   every later host is a read replica. Backend replication uses private IPs, so
   no backend DNS records are required:

   ```bash
   ANSIBLE_SSH_PRIVATE_KEY_FILE=~/.ssh/id_rsa scripts/render-ansible-inventory.sh
   ```

5. For the first deployment only, set `ldap_apply_bootstrap_data: true` after the
   password hashes are final.

6. Run the playbook:

   ```bash
   ansible-playbook -i ansible/inventory.ini ansible/playbooks/site.yml
   ```

   Add `--ask-vault-pass` only when `ansible/group_vars/openldap.yml` is
   encrypted with Ansible Vault.

   If fact gathering fails with `No module named
   'ansible.module_utils.six.moves'`, the controller Ansible is too old for the
   target Python. Run the setup script above, then rerun the playbook.

7. After the first successful bootstrap, set `ldap_apply_bootstrap_data: false`
   and rerun Ansible once to confirm the steady-state path.

## Scaling Replicas

Terraform and Ansible both support more than one read replica.

1. Increase `instance_count` in `terraform/terraform.tfvars`.
2. Run `terraform apply`.
3. Run `scripts/render-ansible-inventory.sh` so the new backend IPs are present
   in `ansible/inventory.ini`.
4. Re-run the Ansible playbook.

The load balancer gets a pool member for every Terraform backend VM. Ansible
configures `groups['openldap'][0]` as the provider and all remaining hosts as
consumers.

## What Ansible Configures

The playbook configures:

- `slapd` package installation using the MDB backend.
- LDAP and LDAPI listeners.
- LDAP admin root DN and password hash.
- MDB size and search indexes.
- ACLs for admin, replication, read-only bind, local root, users, and anonymous
  password authentication.
- `syncprov` overlay on the provider.
- `syncrepl` consumer configuration on replicas.
- Read-only and replication service-account entries, when bootstrap is enabled.
- Local `slapcat` backups of both config and data via a systemd timer.

## Verification

Check the load balancer path:

```bash
nc -vz ldap.example.com 389
```

Check LDAP bind:

```bash
ldapsearch -x -H ldap://ldap.example.com:389 \
  -D "cn=ldap-readonly,ou=service-accounts,dc=example,dc=org" \
  -W \
  -b "ou=users,dc=example,dc=org" \
  "(objectClass=*)"
```

Check replication state on each node:

```bash
sudo ldapsearch -Q -Y EXTERNAL -H ldapi:/// \
  -b "dc=example,dc=org" \
  contextCSN
```

The `contextCSN` values should converge between provider and consumers after
changes replicate.

## Promotion And Failover

Provider failure does not automatically make a consumer writable. That is
intentional for this baseline.

Manual promotion should be documented and tested before real use. At minimum:

1. Stop writes to the old provider.
2. Confirm the chosen replica has the latest data.
3. Reconfigure it as the provider.
4. Repoint `ldap_provider_host` and `ldap_provider_uri`.
5. Re-run Ansible so other consumers replicate from the new provider.
6. Run bind/search tests through the load balancer.
7. Capture a fresh backup.

For automatic write failover, design mirror mode or a proxy layer explicitly.
Do not send arbitrary writes round-robin to multiple writable LDAP nodes.
