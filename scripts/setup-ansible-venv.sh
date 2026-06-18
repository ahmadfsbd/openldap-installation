#!/usr/bin/env bash

# Create/update the Ansible virtualenv for this repo.
#
# Use source so the virtualenv stays active in your current shell:
#
#   source scripts/setup-ansible-venv.sh
#
# If this file is executed directly, it still creates/updates the virtualenv, but
# activation cannot persist after the script exits.

_openldap_setup_ansible_venv() {
  local sourced="$1"
  local script_dir
  local repo_root
  local venv_dir
  local requirements_file

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || return 1
  repo_root="$(cd "${script_dir}/.." && pwd)" || return 1
  venv_dir="${OPENLDAP_ANSIBLE_VENV:-${repo_root}/.venv-ansible}"
  requirements_file="${repo_root}/ansible/requirements.txt"

  if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 was not found. Install python3 and python3-venv first." >&2
    return 1
  fi

  if [ ! -f "${requirements_file}" ]; then
    echo "Missing requirements file: ${requirements_file}" >&2
    return 1
  fi

  if [ ! -d "${venv_dir}" ]; then
    echo "Creating Ansible virtualenv: ${venv_dir}"
    python3 -m venv "${venv_dir}" || {
      echo "Failed to create virtualenv. On Ubuntu, install python3-venv." >&2
      return 1
    }
  else
    echo "Using existing Ansible virtualenv: ${venv_dir}"
  fi

  if [ "${OPENLDAP_UPGRADE_PIP:-0}" = "1" ]; then
    "${venv_dir}/bin/python" -m pip \
      --disable-pip-version-check \
      install \
      --no-cache-dir \
      --upgrade pip || return 1
  fi

  "${venv_dir}/bin/python" -m pip \
    --disable-pip-version-check \
    install \
    --no-cache-dir \
    -r "${requirements_file}" || return 1

  export ANSIBLE_CONFIG="${repo_root}/ansible.cfg"

  if [ "${sourced}" = "true" ]; then
    # shellcheck disable=SC1091
    . "${venv_dir}/bin/activate" || return 1
    hash -r 2>/dev/null || true
    echo "Ansible virtualenv is active: ${VIRTUAL_ENV}"
    ansible-playbook --version | sed -n '1,3p'
  else
    echo
    echo "Setup complete. To activate it in your current shell, run:"
    echo "  source scripts/setup-ansible-venv.sh"
  fi
}

if [ "${BASH_SOURCE[0]}" != "$0" ]; then
  _openldap_setup_ansible_venv true
else
  _openldap_setup_ansible_venv false
fi

_openldap_setup_status=$?
unset -f _openldap_setup_ansible_venv
return "${_openldap_setup_status}" 2>/dev/null || exit "${_openldap_setup_status}"
