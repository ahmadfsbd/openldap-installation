# Operations

## Secrets

Do not commit:

- LDAP admin passwords.
- Read-only bind account passwords.
- Replication credentials.
- Terraform state or tfvars.

Use environment variables, Ansible Vault, or a secret manager.

Generate LDAP password hashes with `slappasswd` and store the hashes in vaulted
Ansible vars. The `syncrepl` consumer configuration also needs the replication
bind password in plaintext, so protect `cn=config` backups as sensitive.

On Ubuntu/Debian, the `slappasswd` command is provided by the `slapd` package;
there is no separate package named `slappasswd`. Run it on a trusted admin
machine or on an OpenLDAP VM where `slapd` is already installed.

This no-TLS baseline sends bind and replication credentials over the network in
plaintext. Restrict LDAP access to trusted CIDRs and private backend networks.

## LDAP Search And Data Changes

Normal applications should use the read-only bind account through the load
balancer. Administrative data changes should be run on the provider node through
local `ldapi:///` with `sudo`, not through the load balancer.

`ldapsearch` only reads data. Use `ldapadd`, `ldapmodify`, `ldapdelete`, or
`ldappasswd` for changes.

Examples below use the documentation domain. Replace `ldap.example.com` and
`dc=example,dc=org` with the values from `ansible/group_vars/openldap.yml`.

The repository Makefile wraps the common commands. It does not store passwords;
search targets prompt for the read-only bind password, and write targets prompt
for the LDAP admin password.

Search targets use `SERVER_URL`, which can be the load balancer DNS name. Write
targets use `WRITE_SERVER_URL`; for production, set that to the writable
provider node, not the round-robin load balancer.

`WRITE_SERVER_URL` is usually a private OpenStack address. That is intentional:
run write commands from the Ansible/controller machine, a bastion, or another
trusted host that can reach the backend network. If your laptop cannot reach the
private provider IP, do not switch writes to the load balancer; run the command
from a trusted network path instead.

Show the defaults:

```bash
make show-config
```

Search for one user or group:

```bash
make user-search NAME=alice \
  SERVER_URL=ldap://ldap.example.com:389 \
  BASE_DN=dc=example,dc=org

make group-search NAME=rancher-admins \
  SERVER_URL=ldap://ldap.example.com:389 \
  BASE_DN=dc=example,dc=org
```

Add a user, group, and group membership:

```bash
slappasswd > /tmp/alice.hash

make add-user NAME=alice CN="Alice Smith" GIVEN_NAME=Alice SN=Smith \
  MAIL=alice@example.org PASSWORD_HASH_FILE=/tmp/alice.hash \
  SERVER_URL=ldap://ldap.example.com:389 \
  WRITE_SERVER_URL=ldap://openldap-1-private-ip:389 \
  BASE_DN=dc=example,dc=org

make add-group NAME=rancher-admins MEMBER_NAME=alice \
  SERVER_URL=ldap://ldap.example.com:389 \
  WRITE_SERVER_URL=ldap://openldap-1-private-ip:389 \
  BASE_DN=dc=example,dc=org

make add-user-to-group GROUP_NAME=rancher-admins MEMBER_NAME=bob \
  SERVER_URL=ldap://ldap.example.com:389 \
  WRITE_SERVER_URL=ldap://openldap-1-private-ip:389 \
  BASE_DN=dc=example,dc=org
```

Create a service account:

```bash
slappasswd > /tmp/rancher-reader.hash

make add-service-account NAME=rancher-ldap-reader \
  SERVICE_DESCRIPTION="Rancher LDAP reader" \
  PASSWORD_HASH_FILE=/tmp/rancher-reader.hash \
  SERVER_URL=ldap://ldap.example.com:389 \
  WRITE_SERVER_URL=ldap://openldap-1-private-ip:389 \
  BASE_DN=dc=example,dc=org
```

Use `PASSWORD_HASH_FILE` instead of passing `PASSWORD_HASH` directly when you do
not want password hashes in shell history.

Check that the read-only bind account can authenticate:

```bash
ldapwhoami -x \
  -H ldap://ldap.example.com:389 \
  -D "cn=ldap-readonly,ou=service-accounts,dc=example,dc=org" \
  -W
```

Search the user container:

```bash
ldapsearch -x \
  -H ldap://ldap.example.com:389 \
  -D "cn=ldap-readonly,ou=service-accounts,dc=example,dc=org" \
  -W \
  -b "ou=users,dc=example,dc=org" \
  dn uid cn mail
```

Search for one login name:

```bash
ldapsearch -x \
  -H ldap://ldap.example.com:389 \
  -D "cn=ldap-readonly,ou=service-accounts,dc=example,dc=org" \
  -W \
  -b "ou=users,dc=example,dc=org" \
  "(uid=alice)" \
  dn uid cn mail
```

Search groups that contain a user:

```bash
ldapsearch -x \
  -H ldap://ldap.example.com:389 \
  -D "cn=ldap-readonly,ou=service-accounts,dc=example,dc=org" \
  -W \
  -b "ou=groups,dc=example,dc=org" \
  "(member=uid=alice,ou=users,dc=example,dc=org)" \
  dn cn member
```

The read-only bind account is intentionally limited to `ou=users` and
`ou=groups`. A search at `dc=example,dc=org` may return `No such object` because
the ACL hides entries outside the allowed search bases.

To inspect everything as an administrator, SSH to the provider and use local
root access:

```bash
sudo ldapsearch -Q -Y EXTERNAL -H ldapi:/// \
  -b "dc=example,dc=org" \
  dn
```

To add a user, first generate a password hash on a trusted machine:

```bash
slappasswd
```

If that command is missing on Ubuntu/Debian, remember it comes from the `slapd`
package, not from a package named `slappasswd`.

Create a user LDIF on the provider:

```ldif
dn: uid=alice,ou=users,dc=example,dc=org
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
uid: alice
cn: Alice Smith
givenName: Alice
sn: Smith
mail: alice@example.com
userPassword: {SSHA}<hash-from-slappasswd>
```

Apply it on the provider:

```bash
sudo ldapadd -Q -Y EXTERNAL -H ldapi:/// -f alice.ldif
```

To add a group:

```ldif
dn: cn=admins,ou=groups,dc=example,dc=org
objectClass: top
objectClass: groupOfNames
cn: admins
member: uid=alice,ou=users,dc=example,dc=org
```

```bash
sudo ldapadd -Q -Y EXTERNAL -H ldapi:/// -f admins.ldif
```

`groupOfNames` normally requires at least one `member`. Add another user to an
existing group with `ldapmodify`:

```ldif
dn: cn=admins,ou=groups,dc=example,dc=org
changetype: modify
add: member
member: uid=bob,ou=users,dc=example,dc=org
```

```bash
sudo ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f add-bob-to-admins.ldif
```

After adding users or groups, test through the load balancer with the read-only
bind account, then check replication state on each node.

## Backup And Restore

Back up both:

- LDAP data, for example with `slapcat`.
- OpenLDAP configuration database, often `cn=config`.

The Ansible baseline installs `/usr/local/sbin/openldap-backup` and a systemd
timer when `ldap_backup_enabled` is true. It exports:

```text
<backup-dir>/<timestamp>/config.ldif
<backup-dir>/<timestamp>/data.ldif
```

Example manual export on a node:

```bash
sudo slapcat -n 1 > ldap-data.ldif
sudo slapcat -n 0 > ldap-config.ldif
```

Test restore before real use. A backup that has never been restored is
only a hopeful file.

Basic restore shape on a replacement node:

1. Stop `slapd`.
2. Move aside the existing LDAP config and data directories.
3. Restore `cn=config` with `slapadd -n 0`.
4. Restore directory data with `slapadd -n 1`.
5. Fix ownership for the LDAP service user.
6. Start `slapd`.
7. Verify LDAP bind/search and replication state.

## Teardown And Rebuild

Prefer Terraform-managed teardown:

```bash
cd terraform
terraform destroy
```

If resources are deleted manually in OpenStack, the local Terraform state can
still contain the old VMs, ports, security group, load balancer, and floating
IP. Clear those stale state entries before the next fresh deployment:

```bash
cd terraform
terraform state list
terraform state rm <resource-address> ...
```

Do not remove state entries for resources that still exist unless you intend to
make Terraform forget them. After the next `terraform apply`, regenerate the
Ansible inventory from Terraform outputs:

```bash
cd ..
ANSIBLE_SSH_PRIVATE_KEY_FILE=~/.ssh/id_rsa scripts/render-ansible-inventory.sh
```

## Monitoring

At minimum monitor:

- TCP `389` on the load balancer.
- LDAP bind/search health with the read-only account.
- Disk usage.
- Replication health and `contextCSN` convergence.
- Backup freshness.

Replication check:

```bash
sudo ldapsearch -Q -Y EXTERNAL -H ldapi:/// \
  -b "dc=example,dc=org" \
  contextCSN
```

## Replication Operations

The baseline uses one writable provider and one or more consumers. Normal
application clients can bind/search through the load balancer. Writes should be
performed against the provider node.

Provider promotion is manual and must be tested before real use. Do not point
write-heavy clients at a round-robin listener unless the replication topology
has been explicitly designed for safe write routing.

## Change Safety

Before schema, ACL, listener, or replication changes:

1. Export current LDAP data and config.
2. Test the change on a non-production instance.
3. Apply to one node first.
4. Verify bind/search from representative clients.
5. Continue rollout.
