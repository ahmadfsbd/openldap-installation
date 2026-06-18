# Client Integration

LDAP clients should connect to OpenLDAP through the load balancer DNS name, not
directly to backend VM addresses.

For LDAP terminology, ports, bind users, search bases, and DNS versus IP
guidance, see [LDAP_INTRO.md](LDAP_INTRO.md).

Normal application clients should use the load balancer for bind/search traffic.
Administrative write tooling should target the current writable provider node as
described in [PRODUCTION.md](PRODUCTION.md), not the round-robin listener.

## Connection Values

Example values:

```text
Hostname/IP: ldap.example.com
Port: 389
TLS/LDAPS: disabled
Bind DN: cn=ldap-readonly,ou=service-accounts,dc=example,dc=org
Bind Password: <secret>
User Search Base: ou=users,dc=example,dc=org
Group Search Base: ou=groups,dc=example,dc=org
```

Common OpenLDAP schema values:

```text
Users Object Class: inetOrgPerson
Login Attribute: uid
Display Name Attribute: cn
First Name Attribute: givenName
Last Name Attribute: sn
Email Attribute: mail
User Search Attribute: uid

Groups Object Class: groupOfNames
Group Name Attribute: cn
Group Member Mapping Attribute: member
Group Member Value Type: user DN
Group Search Attribute: cn
```

This baseline does not configure a `memberOf` overlay, so users do not
automatically have a reverse `memberOf` attribute. Applications should read
membership from group entries where `groupOfNames.member` contains full user DNs,
unless you intentionally add and test a memberOf overlay later.

These values depend on the directory schema. Confirm them with LDAP searches
before configuring real clients.

## Connectivity Checks

Check TCP connectivity:

```bash
nc -vz ldap.example.com 389
```

Check LDAP bind/search:

```bash
ldapsearch -x -H ldap://ldap.example.com:389 \
  -D "cn=ldap-readonly,ou=service-accounts,dc=example,dc=org" \
  -W \
  -b "ou=users,dc=example,dc=org" \
  "(uid=<username>)"
```

Because this baseline has no TLS, only allow trusted client networks to reach
the load balancer. Bind passwords are sent over the network in plaintext.
