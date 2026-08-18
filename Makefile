SHELL := /bin/bash

SERVER_URL ?= ldap://ldap.example.com:389
WRITE_SERVER_URL ?= $(SERVER_URL)
BASE_DN ?= dc=example,dc=org
BIND_DN ?= cn=ldap-readonly,ou=service-accounts,$(BASE_DN)
WRITE_BIND_DN ?= cn=admin,$(BASE_DN)
USERS_BASE ?= ou=users,$(BASE_DN)
GROUPS_BASE ?= ou=groups,$(BASE_DN)
SERVICE_ACCOUNTS_BASE ?= ou=service-accounts,$(BASE_DN)

USER_OBJECT_CLASS ?= inetOrgPerson
GROUP_OBJECT_CLASS ?= groupOfNames
USER_SEARCH_ATTR ?= uid
GROUP_SEARCH_ATTR ?= cn

USER_ATTRS ?= dn uid cn givenName sn mail entryDN
GROUP_ATTRS ?= dn cn member entryDN

USER_UID ?= $(NAME)
USER_DN ?= uid=$(USER_UID),$(USERS_BASE)
USER_CN ?= $(if $(CN),$(CN),$(NAME))
USER_GIVEN_NAME ?= $(if $(GIVEN_NAME),$(GIVEN_NAME),$(NAME))
USER_SN ?= $(if $(SN),$(SN),$(NAME))
USER_MAIL ?= $(if $(MAIL),$(MAIL),$(NAME)@example.org)

GROUP_NAME ?= $(NAME)
GROUP_DN ?= cn=$(GROUP_NAME),$(GROUPS_BASE)
MEMBER_NAME ?=
MEMBER_DN ?=

SERVICE_CN ?= $(NAME)
SERVICE_DN ?= cn=$(SERVICE_CN),$(SERVICE_ACCOUNTS_BASE)
SERVICE_DESCRIPTION ?= Service account

LDAPSEARCH ?= ldapsearch
LDAPADD ?= ldapadd
LDAPMODIFY ?= ldapmodify
LDAPDELETE ?= ldapdelete

-include Makefile.local

.PHONY: help show-config require-name require-password-hash user-search group-search users groups add-user add-group add-user-to-group remove-user-from-group delete-user delete-group delete-service-account add-service-account

help:
	@printf '%s\n' 'OpenLDAP search helpers'
	@printf '%s\n' ''
	@printf '%s\n' 'Configure with make variables:'
	@printf '%s\n' '  SERVER_URL=ldap://ldap.example.com:389'
	@printf '%s\n' '  WRITE_SERVER_URL=ldap://openldap-1-private-ip:389'
	@printf '%s\n' '  BASE_DN=dc=example,dc=org'
	@printf '%s\n' '  BIND_DN=cn=ldap-readonly,ou=service-accounts,$$(BASE_DN)'
	@printf '%s\n' '  or create an ignored Makefile.local with local defaults'
	@printf '%s\n' ''
	@printf '%s\n' 'Targets:'
	@printf '%s\n' '  make user-search NAME=alice'
	@printf '%s\n' '  make group-search NAME=rancher-admins'
	@printf '%s\n' '  make users'
	@printf '%s\n' '  make groups'
	@printf '%s\n' '  make add-user NAME=alice CN="Alice Smith" SN=Smith MAIL=alice@example.org PASSWORD_HASH="{SSHA}..."'
	@printf '%s\n' '  make add-user NAME=alice CN="Alice Smith" SN=Smith MAIL=alice@example.org PASSWORD_HASH_FILE=/tmp/alice.hash'
	@printf '%s\n' '  make add-group NAME=rancher-admins MEMBER_NAME=alice'
	@printf '%s\n' '  make add-user-to-group GROUP_NAME=rancher-admins MEMBER_NAME=bob'
	@printf '%s\n' '  make remove-user-from-group GROUP_NAME=rancher-admins MEMBER_NAME=bob'
	@printf '%s\n' '  make delete-user NAME=alice'
	@printf '%s\n' '  make delete-group NAME=rancher-admins'
	@printf '%s\n' '  make delete-service-account NAME=rancher-ldap-reader'
	@printf '%s\n' '  make add-service-account NAME=rancher-ldap-reader PASSWORD_HASH_FILE=/tmp/rancher-reader.hash'
	@printf '%s\n' '  make show-config'
	@printf '%s\n' ''
	@printf '%s\n' 'Example with real connection values:'
	@printf '%s\n' '  make user-search NAME=alice SERVER_URL=ldap://ldap.example.com:389 BASE_DN=dc=example,dc=org'
	@printf '%s\n' ''
	@printf '%s\n' 'Typical add-user workflow:'
	@printf '%s\n' '  slappasswd > /tmp/alice.hash'
	@printf '%s\n' '  make add-user NAME=alice CN="Alice Smith" GIVEN_NAME=Alice SN=Smith MAIL=alice@example.org PASSWORD_HASH_FILE=/tmp/alice.hash'
	@printf '%s\n' ''
	@printf '%s\n' 'Search targets use SERVER_URL. Write targets use WRITE_SERVER_URL and WRITE_BIND_DN.'
	@printf '%s\n' 'For production, point WRITE_SERVER_URL at the provider, not the round-robin load balancer.'
	@printf '%s\n' 'If WRITE_SERVER_URL is a private OpenStack IP, run make from the Ansible host, bastion, or private network.'
	@printf '%s\n' 'Generate PASSWORD_HASH with slappasswd before adding users or service accounts.'
	@printf '%s\n' 'On Ubuntu/Debian, slappasswd comes from the slapd package; it is not a package named slappasswd.'
	@printf '%s\n' 'Use PASSWORD_HASH_FILE to avoid putting hashes in shell history.'

show-config:
	@printf 'SERVER_URL=%s\n' '$(SERVER_URL)'
	@printf 'WRITE_SERVER_URL=%s\n' '$(WRITE_SERVER_URL)'
	@printf 'BASE_DN=%s\n' '$(BASE_DN)'
	@printf 'BIND_DN=%s\n' '$(BIND_DN)'
	@printf 'WRITE_BIND_DN=%s\n' '$(WRITE_BIND_DN)'
	@printf 'USERS_BASE=%s\n' '$(USERS_BASE)'
	@printf 'GROUPS_BASE=%s\n' '$(GROUPS_BASE)'
	@printf 'SERVICE_ACCOUNTS_BASE=%s\n' '$(SERVICE_ACCOUNTS_BASE)'
	@printf 'USER_SEARCH_ATTR=%s\n' '$(USER_SEARCH_ATTR)'
	@printf 'GROUP_SEARCH_ATTR=%s\n' '$(GROUP_SEARCH_ATTR)'

require-name:
	@if [ -z "$(NAME)" ]; then \
		printf '%s\n' 'Set NAME, for example: make user-search NAME=alice' >&2; \
		exit 2; \
	fi

require-password-hash:
	@if [ -z "$(PASSWORD_HASH)" ] && [ -z "$(PASSWORD_HASH_FILE)" ]; then \
		name='$(NAME)'; \
		printf '%s\n' 'Missing password hash.' >&2; \
		printf '%s\n' '' >&2; \
		printf '%s\n' 'First generate a password hash:' >&2; \
		printf '  slappasswd > /tmp/%s.hash\n' "$$name" >&2; \
		printf '%s\n' '' >&2; \
		printf '%s\n' 'Then pass it to the Makefile with PASSWORD_HASH_FILE:' >&2; \
		printf '  make add-user NAME=%s CN="Full Name" GIVEN_NAME=First SN=Last MAIL=%s@example.org PASSWORD_HASH_FILE=/tmp/%s.hash\n' "$$name" "$$name" "$$name" >&2; \
		printf '%s\n' '' >&2; \
		printf '%s\n' 'For a service account, use:' >&2; \
		printf '  make add-service-account NAME=%s PASSWORD_HASH_FILE=/tmp/%s.hash\n' "$$name" "$$name" >&2; \
		printf '%s\n' '' >&2; \
		printf '%s\n' 'On Ubuntu/Debian, slappasswd is provided by the slapd package.' >&2; \
		printf '%s\n' 'If you install it locally, the package name is slapd, not slappasswd.' >&2; \
		exit 2; \
	fi

user-search: require-name
	$(LDAPSEARCH) -x \
		-H '$(SERVER_URL)' \
		-D '$(BIND_DN)' \
		-W \
		-b '$(USERS_BASE)' \
		'(&(objectClass=$(USER_OBJECT_CLASS))($(USER_SEARCH_ATTR)=$(NAME)))' \
		$(USER_ATTRS)

group-search: require-name
	$(LDAPSEARCH) -x \
		-H '$(SERVER_URL)' \
		-D '$(BIND_DN)' \
		-W \
		-b '$(GROUPS_BASE)' \
		'(&(objectClass=$(GROUP_OBJECT_CLASS))($(GROUP_SEARCH_ATTR)=$(NAME)))' \
		$(GROUP_ATTRS)

users:
	$(LDAPSEARCH) -x \
		-H '$(SERVER_URL)' \
		-D '$(BIND_DN)' \
		-W \
		-b '$(USERS_BASE)' \
		'(objectClass=$(USER_OBJECT_CLASS))' \
		$(USER_ATTRS)

groups:
	$(LDAPSEARCH) -x \
		-H '$(SERVER_URL)' \
		-D '$(BIND_DN)' \
		-W \
		-b '$(GROUPS_BASE)' \
		'(objectClass=$(GROUP_OBJECT_CLASS))' \
		$(GROUP_ATTRS)

add-user: require-name require-password-hash
	@tmp="$$(mktemp)"; \
	trap 'rm -f "$$tmp"' EXIT; \
	password_hash='$(PASSWORD_HASH)'; \
	if [ -z "$$password_hash" ]; then \
		password_hash="$$(sed -n '1p' '$(PASSWORD_HASH_FILE)')"; \
	fi; \
	{ \
		printf '%s\n' 'dn: $(USER_DN)'; \
		printf '%s\n' 'objectClass: top'; \
		printf '%s\n' 'objectClass: person'; \
		printf '%s\n' 'objectClass: organizationalPerson'; \
		printf '%s\n' 'objectClass: inetOrgPerson'; \
		printf '%s\n' 'uid: $(USER_UID)'; \
		printf '%s\n' 'cn: $(USER_CN)'; \
		printf '%s\n' 'givenName: $(USER_GIVEN_NAME)'; \
		printf '%s\n' 'sn: $(USER_SN)'; \
		printf '%s\n' 'mail: $(USER_MAIL)'; \
		printf '%s\n' "userPassword: $$password_hash"; \
	} > "$$tmp"; \
	$(LDAPADD) -x -H '$(WRITE_SERVER_URL)' -D '$(WRITE_BIND_DN)' -W -f "$$tmp"

add-group: require-name
	@member_dn='$(MEMBER_DN)'; \
	if [ -z "$$member_dn" ]; then \
		if [ -z "$(MEMBER_NAME)" ]; then \
			printf '%s\n' 'Set MEMBER_NAME or MEMBER_DN, for example: make add-group NAME=rancher-admins MEMBER_NAME=alice' >&2; \
			exit 2; \
		fi; \
		member_dn='uid=$(MEMBER_NAME),$(USERS_BASE)'; \
	fi; \
	tmp="$$(mktemp)"; \
	trap 'rm -f "$$tmp"' EXIT; \
	{ \
		printf '%s\n' 'dn: $(GROUP_DN)'; \
		printf '%s\n' 'objectClass: top'; \
		printf '%s\n' 'objectClass: groupOfNames'; \
		printf '%s\n' 'cn: $(GROUP_NAME)'; \
		printf '%s\n' "member: $$member_dn"; \
	} > "$$tmp"; \
	$(LDAPADD) -x -H '$(WRITE_SERVER_URL)' -D '$(WRITE_BIND_DN)' -W -f "$$tmp"

add-user-to-group:
	@if [ -z "$(GROUP_NAME)" ]; then \
		printf '%s\n' 'Set GROUP_NAME, for example: make add-user-to-group GROUP_NAME=rancher-admins MEMBER_NAME=alice' >&2; \
		exit 2; \
	fi; \
	member_dn='$(MEMBER_DN)'; \
	if [ -z "$$member_dn" ]; then \
		if [ -z "$(MEMBER_NAME)" ]; then \
			printf '%s\n' 'Set MEMBER_NAME or MEMBER_DN, for example: make add-user-to-group GROUP_NAME=rancher-admins MEMBER_NAME=alice' >&2; \
			exit 2; \
		fi; \
		member_dn='uid=$(MEMBER_NAME),$(USERS_BASE)'; \
	fi; \
	tmp="$$(mktemp)"; \
	trap 'rm -f "$$tmp"' EXIT; \
	{ \
		printf '%s\n' 'dn: $(GROUP_DN)'; \
		printf '%s\n' 'changetype: modify'; \
		printf '%s\n' 'add: member'; \
		printf '%s\n' "member: $$member_dn"; \
	} > "$$tmp"; \
	$(LDAPMODIFY) -x -H '$(WRITE_SERVER_URL)' -D '$(WRITE_BIND_DN)' -W -f "$$tmp"

remove-user-from-group:
	@if [ -z "$(GROUP_NAME)" ]; then \
		printf '%s\n' 'Set GROUP_NAME, for example: make remove-user-from-group GROUP_NAME=rancher-admins MEMBER_NAME=alice' >&2; \
		exit 2; \
	fi; \
	member_dn='$(MEMBER_DN)'; \
	if [ -z "$$member_dn" ]; then \
		if [ -z "$(MEMBER_NAME)" ]; then \
			printf '%s\n' 'Set MEMBER_NAME or MEMBER_DN, for example: make remove-user-from-group GROUP_NAME=rancher-admins MEMBER_NAME=alice' >&2; \
			exit 2; \
		fi; \
		member_dn='uid=$(MEMBER_NAME),$(USERS_BASE)'; \
	fi; \
	tmp="$$(mktemp)"; \
	trap 'rm -f "$$tmp"' EXIT; \
	{ \
		printf '%s\n' 'dn: $(GROUP_DN)'; \
		printf '%s\n' 'changetype: modify'; \
		printf '%s\n' 'delete: member'; \
		printf '%s\n' "member: $$member_dn"; \
	} > "$$tmp"; \
	$(LDAPMODIFY) -x -H '$(WRITE_SERVER_URL)' -D '$(WRITE_BIND_DN)' -W -f "$$tmp"

delete-user: require-name
	$(LDAPDELETE) -x -H '$(WRITE_SERVER_URL)' -D '$(WRITE_BIND_DN)' -W 'uid=$(NAME),$(USERS_BASE)'

delete-group: require-name
	$(LDAPDELETE) -x -H '$(WRITE_SERVER_URL)' -D '$(WRITE_BIND_DN)' -W 'cn=$(NAME),$(GROUPS_BASE)'

delete-service-account: require-name
	$(LDAPDELETE) -x -H '$(WRITE_SERVER_URL)' -D '$(WRITE_BIND_DN)' -W 'cn=$(NAME),$(SERVICE_ACCOUNTS_BASE)'

add-service-account: require-name require-password-hash
	@tmp="$$(mktemp)"; \
	trap 'rm -f "$$tmp"' EXIT; \
	password_hash='$(PASSWORD_HASH)'; \
	if [ -z "$$password_hash" ]; then \
		password_hash="$$(sed -n '1p' '$(PASSWORD_HASH_FILE)')"; \
	fi; \
	{ \
		printf '%s\n' 'dn: $(SERVICE_DN)'; \
		printf '%s\n' 'objectClass: simpleSecurityObject'; \
		printf '%s\n' 'objectClass: organizationalRole'; \
		printf '%s\n' 'cn: $(SERVICE_CN)'; \
		printf '%s\n' 'description: $(SERVICE_DESCRIPTION)'; \
		printf '%s\n' "userPassword: $$password_hash"; \
	} > "$$tmp"; \
	$(LDAPADD) -x -H '$(WRITE_SERVER_URL)' -D '$(WRITE_BIND_DN)' -W -f "$$tmp"
