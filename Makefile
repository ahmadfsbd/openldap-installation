SHELL := /bin/bash

SERVER_URL ?= ldap://ldap.hgi-dev.sanger.ac.uk:389
WRITE_SERVER_URL ?= $(SERVER_URL)
BASE_DN ?= dc=example,dc=org
BIND_DN ?= cn=ldap-readonly,ou=service-accounts,$(BASE_DN)
BIND_PASSWORD_FILE ?=
WRITE_BIND_DN ?= cn=admin,$(BASE_DN)
USERS_BASE ?= ou=users,$(BASE_DN)
GROUPS_BASE ?= ou=groups,$(BASE_DN)
SERVICE_ACCOUNTS_BASE ?= ou=service-accounts,$(BASE_DN)

USER_OBJECT_CLASS ?= inetOrgPerson
GROUP_OBJECT_CLASS ?= groupOfNames
USER_SEARCH_ATTR ?= uid
GROUP_SEARCH_ATTR ?= cn

UID_NUMBER ?=
GID_NUMBER ?=
USER_UID_NUMBER ?= $(UID_NUMBER)
USER_GID_NUMBER ?= $(GID_NUMBER)
GROUP_GID_NUMBER ?= $(GID_NUMBER)
HOME_DIRECTORY ?=
USER_HOME_DIRECTORY ?= $(if $(HOME_DIRECTORY),$(HOME_DIRECTORY),/home/$(USER_UID))
USER_ATTRS ?= dn uid cn givenName sn mail uidNumber gidNumber homeDirectory entryDN
GROUP_ATTRS ?= dn cn member memberUid gidNumber entryDN

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
MEMBER_UID ?=

SERVICE_CN ?= $(NAME)
SERVICE_DN ?= cn=$(SERVICE_CN),$(SERVICE_ACCOUNTS_BASE)
SERVICE_DESCRIPTION ?= Service account

LDAPSEARCH ?= ldapsearch
LDAPADD ?= ldapadd
LDAPMODIFY ?= ldapmodify
LDAPDELETE ?= ldapdelete
LDAPPASSWD ?= ldappasswd

-include Makefile.local

.PHONY: help show-config require-name require-password-hash require-update-user-fields require-update-group-fields user-search group-search users groups add-user update-user add-group update-group add-user-to-group remove-user-from-group delete-user delete-group delete-service-account add-service-account reset-password reset-service-account-password

help:
	@printf '%s\n' 'OpenLDAP search helpers'
	@printf '%s\n' ''
	@printf '%s\n' 'Configure with make variables:'
	@printf '%s\n' '  SERVER_URL=ldap://ldap.example.com:389'
	@printf '%s\n' '  WRITE_SERVER_URL=ldap://openldap-1-private-ip:389'
	@printf '%s\n' '  BASE_DN=dc=example,dc=org'
	@printf '%s\n' '  BIND_DN=cn=ldap-readonly,ou=service-accounts,$$(BASE_DN)'
	@printf '%s\n' '  BIND_PASSWORD_FILE=/path/to/readonly.password'
	@printf '%s\n' '  or create an ignored Makefile.local with local defaults'
	@printf '%s\n' ''
	@printf '%s\n' 'Targets:'
	@printf '%s\n' '  make user-search NAME=alice'
	@printf '%s\n' '  make group-search NAME=rancher-admins'
	@printf '%s\n' '  make users'
	@printf '%s\n' '  make groups'
	@printf '%s\n' '  make add-user NAME=alice UID_NUMBER=2001 GID_NUMBER=2001 HOME_DIRECTORY=/home/alice CN="Alice Smith" SN=Smith MAIL=alice@example.org PASSWORD_HASH="{SSHA}..."'
	@printf '%s\n' '  make update-user NAME=alice UID_NUMBER=2501 GID_NUMBER=2501 CN="Alice Smith" MAIL=alice@example.org  # update numeric IDs and display fields'
	@printf '%s\n' '  make add-user NAME=alice CN="Alice Smith" SN=Smith MAIL=alice@example.org PASSWORD_HASH_FILE=/tmp/alice.hash'
	@printf '%s\n' '  make add-group NAME=rancher-admins GID_NUMBER=2001 MEMBER_NAME=alice'
	@printf '%s\n' '  make update-group NAME=rancher-admins GID_NUMBER=3001  # update group gidNumber only'
	@printf '%s\n' '  make add-user-to-group GROUP_NAME=rancher-admins MEMBER_NAME=bob'
	@printf '%s\n' '  make remove-user-from-group GROUP_NAME=rancher-admins MEMBER_NAME=bob'
	@printf '%s\n' '  make delete-user NAME=alice'
	@printf '%s\n' '  make delete-group NAME=rancher-admins'
	@printf '%s\n' '  make delete-service-account NAME=rancher-ldap-reader'
	@printf '%s\n' '  make add-service-account NAME=rancher-ldap-reader PASSWORD_HASH_FILE=/tmp/rancher-reader.hash'
	@printf '%s\n' '  make reset-password NAME=alice  # prompts for the new password'
	@printf '%s\n' '  make reset-password NAME=alice PASSWORD_HASH_FILE=/tmp/alice.hash'
	@printf '%s\n' '  make reset-service-account-password NAME=rancher-ldap-reader'
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
	@printf 'BIND_PASSWORD_FILE=%s\n' '$(BIND_PASSWORD_FILE)'
	@printf 'WRITE_BIND_DN=%s\n' '$(WRITE_BIND_DN)'
	@printf 'USERS_BASE=%s\n' '$(USERS_BASE)'
	@printf 'GROUPS_BASE=%s\n' '$(GROUPS_BASE)'
	@printf 'SERVICE_ACCOUNTS_BASE=%s\n' '$(SERVICE_ACCOUNTS_BASE)'
	@printf 'USER_SEARCH_ATTR=%s\n' '$(USER_SEARCH_ATTR)'
	@printf 'GROUP_SEARCH_ATTR=%s\n' '$(GROUP_SEARCH_ATTR)'

require-name:
	@if [ -z "$(NAME)" ]; then \
		goal='$(firstword $(MAKECMDGOALS))'; \
		printf 'Set NAME, for example: make %s NAME=alice\n' "$${goal:-user-search}" >&2; \
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

require-update-user-fields:
	@if [ -z "$(UID_NUMBER)" ] && [ -z "$(GID_NUMBER)" ] && [ -z "$(HOME_DIRECTORY)" ] && [ -z "$(CN)" ] && [ -z "$(GIVEN_NAME)" ] && [ -z "$(SN)" ] && [ -z "$(MAIL)" ]; then \
		printf '%s\n' 'Set at least one field to update, for example:' >&2; \
		printf '%s\n' '  make update-user NAME=bob UID_NUMBER=2501 GID_NUMBER=2501' >&2; \
		printf '%s\n' '  make update-user NAME=bob HOME_DIRECTORY=/home/bob' >&2; \
		printf '%s\n' '  make update-user NAME=bob CN="Bob Smith" MAIL=bob@example.org' >&2; \
		exit 2; \
	fi

require-update-group-fields:
	@if [ -z "$(GID_NUMBER)" ] && [ -z "$(NEW_NAME)" ]; then \
		printf '%s\n' 'Set GID_NUMBER or NEW_NAME to update, for example:' >&2; \
		printf '%s\n' '  make update-group NAME=dev GID_NUMBER=3001' >&2; \
		printf '%s\n' '  make update-group NAME=dev NEW_NAME=ops' >&2; \
		exit 2; \
	fi

user-search: require-name
	@auth_args=(-D '$(BIND_DN)'); \
	if [ -n '$(BIND_PASSWORD_FILE)' ]; then \
		auth_args+=(-y '$(BIND_PASSWORD_FILE)'); \
	else \
		auth_args+=(-W); \
	fi; \
	$(LDAPSEARCH) -x \
		-H '$(SERVER_URL)' \
		"$${auth_args[@]}" \
		-b '$(USERS_BASE)' \
		'(&(objectClass=$(USER_OBJECT_CLASS))($(USER_SEARCH_ATTR)=$(NAME)))' \
		$(USER_ATTRS)

group-search: require-name
	@auth_args=(-D '$(BIND_DN)'); \
	if [ -n '$(BIND_PASSWORD_FILE)' ]; then \
		auth_args+=(-y '$(BIND_PASSWORD_FILE)'); \
	else \
		auth_args+=(-W); \
	fi; \
	$(LDAPSEARCH) -x \
		-H '$(SERVER_URL)' \
		"$${auth_args[@]}" \
		-b '$(GROUPS_BASE)' \
		'(&(objectClass=$(GROUP_OBJECT_CLASS))($(GROUP_SEARCH_ATTR)=$(NAME)))' \
		$(GROUP_ATTRS)

users:
	@auth_args=(-D '$(BIND_DN)'); \
	if [ -n '$(BIND_PASSWORD_FILE)' ]; then \
		auth_args+=(-y '$(BIND_PASSWORD_FILE)'); \
	else \
		auth_args+=(-W); \
	fi; \
	$(LDAPSEARCH) -x \
		-H '$(SERVER_URL)' \
		"$${auth_args[@]}" \
		-b '$(USERS_BASE)' \
		'(objectClass=$(USER_OBJECT_CLASS))' \
		$(USER_ATTRS)

groups:
	@auth_args=(-D '$(BIND_DN)'); \
	if [ -n '$(BIND_PASSWORD_FILE)' ]; then \
		auth_args+=(-y '$(BIND_PASSWORD_FILE)'); \
	else \
		auth_args+=(-W); \
	fi; \
	$(LDAPSEARCH) -x \
		-H '$(SERVER_URL)' \
		"$${auth_args[@]}" \
		-b '$(GROUPS_BASE)' \
		'(objectClass=$(GROUP_OBJECT_CLASS))' \
		$(GROUP_ATTRS)

add-user: require-name require-password-hash
	@tmp="$$(mktemp)"; \
	trap 'rm -f "$$tmp"' EXIT; \
	password_hash='$(PASSWORD_HASH)'; \
	uid_number='$(USER_UID_NUMBER)'; \
	gid_number='$(USER_GID_NUMBER)'; \
	if [ -z "$$gid_number" ] && [ -n "$$uid_number" ]; then \
		gid_number="$$uid_number"; \
	fi; \
	if [ -z "$$password_hash" ]; then \
		password_hash="$$(sed -n '1p' '$(PASSWORD_HASH_FILE)')"; \
	fi; \
	{ \
		printf '%s\n' 'dn: $(USER_DN)'; \
		printf '%s\n' 'objectClass: top'; \
		printf '%s\n' 'objectClass: person'; \
		printf '%s\n' 'objectClass: organizationalPerson'; \
		printf '%s\n' 'objectClass: inetOrgPerson'; \
		if [ -n "$$uid_number" ] || [ -n "$$gid_number" ]; then \
			printf '%s\n' 'objectClass: posixAccount'; \
		fi; \
		printf '%s\n' 'uid: $(USER_UID)'; \
		printf '%s\n' 'cn: $(USER_CN)'; \
		printf '%s\n' 'givenName: $(USER_GIVEN_NAME)'; \
		printf '%s\n' 'sn: $(USER_SN)'; \
		printf '%s\n' 'mail: $(USER_MAIL)'; \
		if [ -n "$$uid_number" ]; then \
			printf 'uidNumber: %s\n' "$$uid_number"; \
		fi; \
		if [ -n "$$gid_number" ]; then \
			printf 'gidNumber: %s\n' "$$gid_number"; \
		fi; \
		if [ -n "$$uid_number" ] || [ -n "$$gid_number" ]; then \
			printf '%s\n' 'homeDirectory: $(USER_HOME_DIRECTORY)'; \
		fi; \
		printf '%s\n' "userPassword: $$password_hash"; \
	} > "$$tmp"; \
	$(LDAPADD) -x -H '$(WRITE_SERVER_URL)' -D '$(WRITE_BIND_DN)' -W -f "$$tmp"

add-group: require-name
	@member_dn='$(MEMBER_DN)'; \
	member_uid='$(MEMBER_UID)'; \
	group_gid='$(GROUP_GID_NUMBER)'; \
	if [ -z "$$group_gid" ] && [ -n '$(GID_NUMBER)' ]; then \
		group_gid='$(GID_NUMBER)'; \
	fi; \
	if [ -z "$$member_dn" ]; then \
		if [ -z "$(MEMBER_NAME)" ]; then \
			printf '%s\n' 'Set MEMBER_NAME or MEMBER_DN, for example: make add-group NAME=rancher-admins MEMBER_NAME=alice' >&2; \
			exit 2; \
		fi; \
		member_dn='uid=$(MEMBER_NAME),$(USERS_BASE)'; \
		if [ -z "$$member_uid" ]; then \
			member_uid='$(MEMBER_NAME)'; \
		fi; \
	fi; \
	tmp="$$(mktemp)"; \
	trap 'rm -f "$$tmp"' EXIT; \
	{ \
		printf '%s\n' 'dn: $(GROUP_DN)'; \
		printf '%s\n' 'objectClass: top'; \
		printf '%s\n' 'objectClass: groupOfNames'; \
		if [ -n "$$group_gid" ]; then \
			printf '%s\n' 'objectClass: posixGroup'; \
		fi; \
		printf '%s\n' 'cn: $(GROUP_NAME)'; \
		printf '%s\n' "member: $$member_dn"; \
		if [ -n "$$group_gid" ]; then \
			printf 'gidNumber: %s\n' "$$group_gid"; \
		fi; \
		if [ -n "$$member_uid" ] && [ -n "$$group_gid" ]; then \
			printf 'memberUid: %s\n' "$$member_uid"; \
		fi; \
	} > "$$tmp"; \
	$(LDAPADD) -x -H '$(WRITE_SERVER_URL)' -D '$(WRITE_BIND_DN)' -W -f "$$tmp"

update-user: require-name require-update-user-fields
	@tmp="$$(mktemp)"; \
	trap 'rm -f "$$tmp"' EXIT; \
	{ \
		printf '%s\n' 'dn: uid=$(NAME),$(USERS_BASE)'; \
		printf '%s\n' 'changetype: modify'; \
		if [ -n '$(UID_NUMBER)' ] || [ -n '$(GID_NUMBER)' ]; then \
			printf '%s\n' 'add: objectClass'; \
			printf '%s\n' 'objectClass: posixAccount'; \
			printf '%s\n' '-'; \
		fi; \
		if [ -n '$(UID_NUMBER)' ]; then \
			printf '%s\n' 'replace: uidNumber'; \
			printf '%s\n' 'uidNumber: $(UID_NUMBER)'; \
			printf '%s\n' '-'; \
		fi; \
		if [ -n '$(GID_NUMBER)' ]; then \
			printf '%s\n' 'replace: gidNumber'; \
			printf '%s\n' 'gidNumber: $(GID_NUMBER)'; \
			printf '%s\n' '-'; \
		fi; \
		if [ -n '$(UID_NUMBER)' ] || [ -n '$(GID_NUMBER)' ]; then \
			printf '%s\n' 'add: homeDirectory'; \
			printf '%s\n' 'homeDirectory: $(USER_HOME_DIRECTORY)'; \
			printf '%s\n' '-'; \
		elif [ -n '$(HOME_DIRECTORY)' ]; then \
			printf '%s\n' 'replace: homeDirectory'; \
			printf '%s\n' 'homeDirectory: $(HOME_DIRECTORY)'; \
			printf '%s\n' '-'; \
		fi; \
		if [ -n '$(CN)' ]; then \
			printf '%s\n' 'replace: cn'; \
			printf '%s\n' 'cn: $(CN)'; \
			printf '%s\n' '-'; \
		fi; \
		if [ -n '$(GIVEN_NAME)' ]; then \
			printf '%s\n' 'replace: givenName'; \
			printf '%s\n' 'givenName: $(GIVEN_NAME)'; \
			printf '%s\n' '-'; \
		fi; \
		if [ -n '$(SN)' ]; then \
			printf '%s\n' 'replace: sn'; \
			printf '%s\n' 'sn: $(SN)'; \
			printf '%s\n' '-'; \
		fi; \
		if [ -n '$(MAIL)' ]; then \
			printf '%s\n' 'replace: mail'; \
			printf '%s\n' 'mail: $(MAIL)'; \
			printf '%s\n' '-'; \
		fi; \
	} > "$$tmp"; \
	$(LDAPMODIFY) -x -H '$(WRITE_SERVER_URL)' -D '$(WRITE_BIND_DN)' -W -f "$$tmp"

update-group: require-name require-update-group-fields
	@tmp="$$(mktemp)"; \
	trap 'rm -f "$$tmp"' EXIT; \
	{ \
		printf '%s\n' 'dn: cn=$(NAME),$(GROUPS_BASE)'; \
		printf '%s\n' 'changetype: modify'; \
		if [ -n '$(GID_NUMBER)' ]; then \
			printf '%s\n' 'add: objectClass'; \
			printf '%s\n' 'objectClass: posixGroup'; \
			printf '%s\n' '-'; \
			printf '%s\n' 'replace: gidNumber'; \
			printf '%s\n' 'gidNumber: $(GID_NUMBER)'; \
			printf '%s\n' '-'; \
		fi; \
		if [ -n '$(NEW_NAME)' ]; then \
			printf '%s\n' 'replace: cn'; \
			printf '%s\n' 'cn: $(NEW_NAME)'; \
			printf '%s\n' '-'; \
		fi; \
	} > "$$tmp"; \
	$(LDAPMODIFY) -x -H '$(WRITE_SERVER_URL)' -D '$(WRITE_BIND_DN)' -W -f "$$tmp"

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

reset-password: RESET_DN = $(USER_DN)
reset-service-account-password: RESET_DN = $(SERVICE_DN)

reset-password reset-service-account-password: require-name
	@password_hash='$(PASSWORD_HASH)'; \
	if [ -z "$$password_hash" ] && [ -n '$(PASSWORD_HASH_FILE)' ]; then \
		password_hash="$$(sed -n '1p' '$(PASSWORD_HASH_FILE)')"; \
	fi; \
	if [ -z "$$password_hash" ]; then \
		printf '%s\n' 'Resetting password for $(RESET_DN)' >&2; \
		printf '%s\n' 'Enter the new password twice, then the $(WRITE_BIND_DN) password.' >&2; \
		$(LDAPPASSWD) -x -H '$(WRITE_SERVER_URL)' -D '$(WRITE_BIND_DN)' -W -S '$(RESET_DN)'; \
		exit $$?; \
	fi; \
	tmp="$$(mktemp)"; \
	trap 'rm -f "$$tmp"' EXIT; \
	{ \
		printf '%s\n' 'dn: $(RESET_DN)'; \
		printf '%s\n' 'changetype: modify'; \
		printf '%s\n' 'replace: userPassword'; \
		printf '%s\n' "userPassword: $$password_hash"; \
	} > "$$tmp"; \
	$(LDAPMODIFY) -x -H '$(WRITE_SERVER_URL)' -D '$(WRITE_BIND_DN)' -W -f "$$tmp"
