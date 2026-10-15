#!/usr/bin/env bash
# Load OpenBao credentials for the other scripts in this directory.
# Secret values live in ~/.config/lumynex/openbao.env or the environment.
# This file has none.

openbao_env_file() {
  printf '%s\n' "${OPENBAO_ENV_FILE:-${HOME}/.config/lumynex/openbao.env}"
}

openbao_load() {
  local env_file
  if [[ -x /opt/homebrew/bin/bao ]]; then
    export PATH="/opt/homebrew/bin:${PATH}"
  fi
  env_file="$(openbao_env_file)"
  if [[ -f "${env_file}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${env_file}"
    set +a
  fi
  if [[ -z "${BAO_ADDR:-}" ]]; then
    echo "BAO_ADDR is unset. Set it in the environment or in ${env_file}." >&2
    return 1
  fi
  if [[ -n "${BAO_TOKEN:-}" ]]; then
    return 0
  fi
  if [[ -z "${BAO_ROLE_ID:-}" || -z "${BAO_SECRET_ID:-}" ]]; then
    echo "No BAO_TOKEN. Put BAO_TOKEN, or BAO_ROLE_ID and BAO_SECRET_ID, in ${env_file}." >&2
    return 1
  fi
  BAO_TOKEN="$(
    bao write -field=token auth/approle/login \
      role_id="${BAO_ROLE_ID}" \
      secret_id="${BAO_SECRET_ID}"
  )"
  export BAO_TOKEN
}
