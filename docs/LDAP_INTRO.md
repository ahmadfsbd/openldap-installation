# LDAP Intro

This document explains the LDAP basics needed to understand this project and to
configure applications that will use it. It assumes no previous LDAP knowledge.

## What LDAP Is

LDAP is a protocol for reading and updating directory data. A directory is a
tree of entries, commonly used for identities, groups, service accounts, and
other shared lookup data.

In practice, an application usually uses LDAP to answer questions like:

- Can this user authenticate?
- What is this user's username, name, email address, or ID?
- Which groups is this user a member of?
- Is this service account allowed to read user and group data?

OpenLDAP is the LDAP server implementation used by this project.

LDAP is not a browser login page. A browser-based product can use LDAP behind
the scenes, but the product still needs its own web UI. This repo configures the
LDAP service, not an LDAP admin console such as LDAP Account Manager or
phpLDAPadmin.

## LDAP And SSO Systems

LDAP can be the source of users, groups, and password checks, but many companies
put an SSO/MFA product in front of it. A common practical design is:

```text
LDAP/AD = directory source
Okta or another IdP = SSO/MFA/frontend identity provider
Apps = use SAML/OIDC through the IdP where possible
Legacy apps = use LDAP directly
```

Where passwords live depends on the design. If the IdP delegates authentication
to LDAP/AD, passwords live in LDAP/AD. If the IdP is the authority, passwords
live in the IdP and LDAP may only provide users and groups.

## LDAP Names

LDAP data is addressed by names inside the directory tree. These names are not
DNS names, although they often look related.

| Term | Meaning | Example |
|------|---------|---------|
| `dc` | One domain component, usually one DNS label | `dc=company,dc=com` |
| `ou` | Organizational unit, a container | `ou=users` |
| `cn` | Common name | `cn=ldap-readonly` |
| `uid` | User ID/login name | `uid=alice` |
| `dn` | Distinguished name, the full LDAP path to an entry | `uid=alice,ou=users,dc=company,dc=com` |
| `rdn` | Relative distinguished name, one part of a DN | `uid=alice` |

For a company domain such as `company.com`, a common LDAP base DN is:

```text
dc=company,dc=com
```

There are two `dc` parts because `company.com` has two DNS labels:

```text
company -> dc=company
com     -> dc=com
```

For `example.org`, the base DN is commonly `dc=example,dc=org`. For
`dept.company.com`, it could be `dc=dept,dc=company,dc=com`, although many
organizations still choose the simpler company-wide base `dc=company,dc=com`.
The important practical rule is to pick a stable base DN early, because users,
groups, bind accounts, ACLs, and client settings will all refer to it.

This repository uses `example.org` in many examples as a safe placeholder. For a
real `company.com` deployment, replace `dc=example,dc=org` with
`dc=company,dc=com` consistently.

A DN is read from the most specific entry to the broadest parent. For example:

```text
uid=alice,ou=users,dc=company,dc=com
```

means:

```text
alice user entry
inside ou=users
inside dc=company,dc=com
```

The `dc=company,dc=com` part is the base of the directory tree. It is often
derived from the organization's DNS domain, but it is LDAP naming, not a DNS
lookup.

## Common Directory Units

A simple production-shaped directory often has containers like this:

```text
dc=company,dc=com
+-- ou=users
+-- ou=groups
`-- ou=service-accounts
```

In this shape, `ou=groups` is not itself a group. It is a container that holds
group entries. The actual groups are entries inside it, often named with `cn`.

Typical entries:

| Entry type | Example DN | Purpose |
|------------|------------|---------|
| User | `uid=alice,ou=users,dc=company,dc=com` | Human identity |
| Group container | `ou=groups,dc=company,dc=com` | Folder-like container for group entries |
| Group | `cn=admins,ou=groups,dc=company,dc=com` | Actual group entry, usually containing member DNs |
| Service account | `cn=ldap-readonly,ou=service-accounts,dc=company,dc=com` | Application bind identity |

LDAP entries are made of attributes. A user might have attributes such as
`uid`, `cn`, `givenName`, `sn`, `mail`, and `userPassword`. A group might have
`cn` and `member` attributes. The allowed and required attributes are controlled
by object classes and schema.

A group membership may look like this in LDAP data:

```text
dn: cn=admins,ou=groups,dc=company,dc=com
objectClass: groupOfNames
cn: admins
member: uid=alice,ou=users,dc=company,dc=com
```

That means the `admins` group contains the user entry whose DN is
`uid=alice,ou=users,dc=company,dc=com`.

## Object Classes And Schema

LDAP schema is the rulebook for entries. It defines:

- Which object classes exist.
- Which attributes exist.
- Which attributes are required or optional for each object class.

The practical way to think about it:

```text
entry       = one record in the LDAP tree
attribute   = a key/value-like field on that record
objectClass = what kind of thing this entry is
schema      = the rules that say which fields are allowed
```

An LDAP entry is mostly a collection of attributes. Attributes look like
key/value pairs, for example `uid: alice`, `cn: Alice Smith`, or
`mail: alice@company.com`.

`objectClass` is also an attribute, but it is a special one. Its values tell
LDAP what type of entry this is and which other attributes are allowed or
required. An entry normally has one or more `objectClass` values.

Common object classes include:

| Object class | Common use |
|--------------|------------|
| `inetOrgPerson` | A human user/person entry |
| `organizationalUnit` | A folder-like container such as `ou=users` |
| `groupOfNames` | A group where members are listed by full DN in `member` attributes |

For example, a user entry might look like this:

```text
dn: uid=alice,ou=users,dc=company,dc=com
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
uid: alice
cn: Alice Smith
givenName: Alice
sn: Smith
mail: alice@company.com
```

The important bits are:

| Part | Practical meaning |
|------|-------------------|
| `objectClass: ...` | The schema types this entry follows |
| `objectClass: inetOrgPerson` | This entry is ultimately a user/person record |
| `uid: alice` | Alice's login name |
| `cn: Alice Smith` | Alice's common/display name |
| `mail: alice@company.com` | Alice's email address |

A group entry might look like this:

```text
dn: cn=admins,ou=groups,dc=company,dc=com
objectClass: groupOfNames
cn: admins
member: uid=alice,ou=users,dc=company,dc=com
member: uid=bob,ou=users,dc=company,dc=com
```

Here, `objectClass: groupOfNames` says "this is a group", and each `member`
value points at a user by full DN.

Applications ask for schema mapping fields because they need to know which
object classes and attributes your directory uses. For example:

```text
Users Object Class: inetOrgPerson
Login Attribute: uid
Groups Object Class: groupOfNames
Group Member Mapping Attribute: member
```

That means:

| Client setting | What the application will do |
|----------------|------------------------------|
| `Users Object Class: inetOrgPerson` | Treat entries with `objectClass=inetOrgPerson` as users |
| `Login Attribute: uid` | Find users by searching for values like `(uid=alice)` |
| `Groups Object Class: groupOfNames` | Treat entries with `objectClass=groupOfNames` as groups |
| `Group Member Mapping Attribute: member` | Read group membership from the group's `member` values |

Different LDAP deployments can use different shapes. For example, some groups
use `groupOfUniqueNames` with `uniqueMember`, or `posixGroup` with `memberUid`.
That is why client settings must match the actual directory schema. Do not
guess them for production clients; verify them with LDAP searches.

## Bind, Search, And The Bind User

An LDAP bind is a login to the LDAP server. It proves who the client is before
the client performs operations such as searching the directory.

Common bind patterns:

| Pattern | Meaning | Production note |
|---------|---------|-----------------|
| Anonymous bind | No username/password | Usually disabled or heavily restricted |
| User bind | The application binds as the end user | Useful for password checks |
| Service bind | The application binds as a dedicated service account | Common for application lookups |

This project expects a read-only service account such as:

```text
cn=ldap-readonly,ou=service-accounts,dc=example,dc=org
```

That DN is the bind DN. The bind password is a secret and must not be committed
to git.

A common application flow is:

1. Bind as `cn=ldap-readonly,ou=service-accounts,dc=example,dc=org`.
2. Search under `ou=users,dc=example,dc=org` for `(uid=<username>)`.
3. Read the matching user's DN and attributes.
4. Optionally check group membership under `ou=groups,dc=example,dc=org`.
5. If authenticating a password, perform a second bind as the user DN.

The read-only bind account should have only the access it needs. It should be
able to search users and groups, but it should not be able to change directory
data or read sensitive password hashes.

## Search Bases And Filters

A search base tells LDAP where to start searching in the tree. A filter tells it
what to match.

Example user search:

```bash
ldapsearch -x -H ldap://ldap.example.com:389 \
  -D "cn=ldap-readonly,ou=service-accounts,dc=example,dc=org" \
  -W \
  -b "ou=users,dc=example,dc=org" \
  "(uid=alice)"
```

Important parts:

| Part | Meaning |
|------|---------|
| `-H ldap://ldap.example.com:389` | LDAP server URL |
| `-D ...` | Bind DN |
| `-W` | Prompt for bind password |
| `-b ...` | Search base |
| `(uid=alice)` | Search filter |

In client configuration screens, "User Search Base" and "Group Search Base" are
usually these `-b` values.

## Ports And TLS

LDAP is commonly exposed on two TCP ports:

| Port | Name | What it means | Project recommendation |
|------|------|---------------|------------------------|
| `389/tcp` | LDAP | Plain LDAP, or LDAP upgraded with StartTLS | Used by this no-TLS trusted-network baseline |
| `636/tcp` | LDAPS | LDAP wrapped in TLS from the start | Not enabled in this baseline |

This project baseline uses plain LDAP on `389/tcp` because the requested shape
has one load-balancer DNS record and no TLS. That keeps the network and
certificate model simple, but it also means bind passwords and replication
credentials are sent over the network in plaintext.

Only use this shape inside trusted networks with strict source CIDRs and private
backend VMs. For broader exposure, use LDAPS on `636/tcp` or require StartTLS on
`389/tcp`.

## Hostname, IP, And LDAP URL

LDAP clients may ask for "Hostname/IP", "URL", or separate host, port, and TLS
fields. These are related but not identical.

Use the load balancer DNS name for clients:

```text
ldap.example.com
```

or as a full LDAP URL:

```text
ldap://ldap.example.com:389
```

Prefer a DNS name instead of a raw IP address because:

- The DNS name can stay stable even if the load balancer IP changes.
- Applications can keep one stable connection target.
- Backend LDAP VM IPs remain private implementation details.

Do not configure normal clients to use the backend VM private IPs directly.
Clients should connect to the load balancer endpoint, and the load balancer
should forward TCP traffic to the private LDAP VMs.

## Load Balancer Shape

In this project, the intended path is:

```text
trusted LDAP client
        |
        | ldap://ldap.example.com:389
        v
OpenStack Octavia TCP load balancer
        |
        v
private OpenLDAP VMs
```

The load balancer gives clients one stable endpoint. It does not replace LDAP
replication. If there are multiple LDAP VMs, the directory data must still be
replicated and tested separately.

For security, restrict both:

- The load balancer listener, using allowed source CIDRs.
- OpenStack security groups, allowing only expected traffic.

## No TLS In This Baseline

This baseline does not configure TLS certificates. That means:

- Clients use `ldap://ldap.example.com:389`, not `ldaps://`.
- Replication uses backend private IPs on `389/tcp`.
- There is only one DNS record: the load balancer name.
- LDAP credentials are not encrypted on the network.

Keep the load balancer and backend security groups restricted to trusted
networks. If that is not acceptable, move to LDAPS or StartTLS.

## Admin Users Versus Bind Users

Do not use the LDAP admin DN for normal applications.

Use separate identities:

| Identity | Purpose | Access level |
|----------|---------|--------------|
| LDAP admin | Directory administration | Powerful, tightly controlled |
| Read-only bind user | Application searches | Minimal read access |
| Human user | End-user login | Own authentication and attributes |
| Replication user | Node-to-node replication | Only what replication requires |

Keeping these separate limits the damage from a leaked application password and
makes auditing easier.

## Where LDAP Data Is Stored

LDAP is the protocol clients speak. OpenLDAP is the server. The server still
needs somewhere to store directory entries.

In a normal OpenLDAP deployment, `slapd` stores data in a local backend
database. Modern production deployments commonly use the MDB backend, backed by
LMDB. This is usually not a separate PostgreSQL or MySQL database.

Practical picture:

```text
client application
        |
        | LDAP or LDAPS
        v
slapd, the OpenLDAP server
        |
        v
local MDB/LMDB database files
```

There are two important things to back up:

| Data | What it contains |
|------|------------------|
| Main directory database | Users, groups, service accounts, and other LDAP entries |
| `cn=config` database | OpenLDAP configuration such as schema, ACLs, listeners, and replication |

## Client Configuration Checklist

Most LDAP client integrations need:

```text
Hostname/IP: ldap.example.com
Port: 389
TLS/LDAPS: disabled
Bind DN: cn=ldap-readonly,ou=service-accounts,dc=example,dc=org
Bind Password: <secret>
User Search Base: ou=users,dc=example,dc=org
Group Search Base: ou=groups,dc=example,dc=org
Login Attribute: uid
User Object Class: inetOrgPerson
Group Object Class: groupOfNames
Group Member Attribute: member
```

This baseline reads group membership from group entries. A group entry such as
`cn=admins,ou=groups,...` has `member` values containing full user DNs. It does
not configure a reverse `memberOf` overlay by default, so do not give clients
`memberOf` as the primary membership source unless you add and test that overlay.

The exact values depend on the directory schema and access-control rules. Before
handing values to an application team, verify:

- TCP connectivity to `ldap.example.com:389`.
- The read-only bind account can bind.
- User searches return the expected attributes.
- Group searches return the expected membership values.
- The bind account cannot modify directory data.
