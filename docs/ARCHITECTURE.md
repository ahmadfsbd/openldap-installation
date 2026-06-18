# Architecture

OpenLDAP runs on dedicated OpenStack VMs and is exposed through an OpenStack
Octavia TCP load balancer.

## Components

- OpenStack compute instances running OpenLDAP.
- One explicit backend VM security group with SSH and LDAP rules.
- Octavia TCP load balancer.
- Optional floating IP on the load balancer.
- DNS record such as `ldap.example.com`.

## Network Exposure

Recommended exposure:

```text
trusted source CIDRs
        |
        | 389/tcp
        v
Octavia load balancer
        |
        | private subnet
        v
OpenLDAP VMs
```

Do not expose backend LDAP VMs directly. If a floating IP is required, attach it
to the load balancer and restrict `allowed_cidrs` plus security groups.

## Security Controls

Terraform creates one explicit security group for LDAP backend VM ports. That
group controls SSH to the VMs and direct backend LDAP access on `389/tcp`.

The load balancer front door is controlled separately by the Octavia listener's
`allowed_cidrs`. The intended production boundary is:

```text
client CIDRs
  -> Octavia listener allowed_cidrs
  -> load balancer
  -> backend VM security group
  -> slapd
```

For real use, keep `ldap_allowed_cidrs` limited to trusted client networks and
keep `backend_allowed_cidrs` limited to the backend/load-balancer network, or use
source security groups where the cloud supports them.

## Ports

| Port | Purpose | Recommendation |
|------|---------|----------------|
| `389/tcp` | LDAP | Enabled for trusted client traffic through the load balancer |
| `389/tcp` between LDAP VMs | Replication traffic | Allow only between backend LDAP security group members |
| `636/tcp` | LDAPS | Not enabled in this no-TLS baseline |
| `22/tcp` | SSH | Restrict to management CIDRs or bastion |

This baseline intentionally does not configure TLS. LDAP bind passwords and
replication credentials cross the network in plaintext, so restrict `389/tcp` to
trusted client CIDRs and private backend networks only. Administration should
prefer local `ldapi:///` on the server.

## High Availability

The trusted-network baseline topology is single-provider replication:

```text
Octavia LDAP listener
        |
        +-- openldap-1, writable provider
        +-- openldap-2, read replica / consumer
        `-- openldap-N, read replica / consumer
```

The load balancer provides a stable endpoint for normal bind/search traffic.
OpenLDAP `syncrepl` keeps consumer data synchronized from the provider.
Terraform `instance_count` controls the total backend count. The generated
Ansible inventory keeps the first host as the provider and configures every
additional host as a read replica / consumer.

Administrative writes should go to the provider node. A round-robin TCP load
balancer must not be treated as automatic active-active write HA. If automatic
write failover is required, add a tested mirror-mode or proxy design that routes
writes to only one active provider at a time.

If the provider fails, read/authentication traffic can continue on consumers,
but writes are paused until the provider is restored or a consumer is promoted.

## Backend Database

OpenLDAP stores data in a local slapd backend database. This baseline uses the
MDB backend, backed by LMDB. Back up both the runtime configuration database,
`cn=config`, and the main directory data database.

## DNS

Create a DNS record after Terraform creates the load balancer:

```text
ldap.example.com -> <ldap_load_balancer_ip>
```

This is the only DNS record expected by the baseline. Backend LDAP VMs do not
need DNS records. Ansible connects to them by private IP, and OpenLDAP
replication uses private IP LDAP URIs such as:

```text
ldap://10.0.0.12:389
```
