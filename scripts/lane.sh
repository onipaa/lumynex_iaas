#!/usr/bin/env bash
# lane.sh — build or tear down the cl1 IaaS lane.
#
# Usage:
#   scripts/lane.sh up
#   scripts/lane.sh down
#
# Exit codes: 0 = success, 2 = usage/error
#
# Requires: ansible-playbook, inventory/hosts.ini, and ~/.config/lumynex/openbao.env
# after the OpenBao tier has been initialized.
#
# Order up: OpenBao, PostgreSQL, the airport database, PMM, PgDog, Django guests,
# both load balancers, then the airport load page.
# PgDog is installed on the three PgDog guests and registers every PostgreSQL node.
# The database exists before PgDog starts, so its pools can log in.
# Order down: teardown_guests.yml walks guests.yml from the top.
# etcd and Patroni run on every PostgreSQL node. The airports client address is
# 192.168.4.172. 192.168.4.171 stays the SaaS address.

set -euo pipefail

readonly PROG="$(basename "$0")"
readonly ROOT="$(cd "$(dirname "$0")/.." && pwd)"

die() {
    echo "error: $*" >&2
    exit 2
}

usage() {
    echo "usage: ${PROG} up|down" >&2
}

command -v ansible-playbook >/dev/null 2>&1 || die "ansible-playbook not found"
[[ -f "${ROOT}/inventory/hosts.ini" ]] || die "missing ${ROOT}/inventory/hosts.ini"

cd "${ROOT}"

run_tier() {
    local tier="$1"
    ansible-playbook playbooks/spin_tier.yml -e "tier=${tier}"
    ansible-playbook "playbooks/configure_${tier}.yml"
}

case "${1:-}" in
    up)
        run_tier openbao
        run_tier postgres
        ansible-playbook playbooks/configure_airport.yml --tags airport_db
        run_tier pmm
        run_tier pgdog
        run_tier app
        ansible-playbook playbooks/spin_tier.yml -e tier=loadbal_pgdog
        ansible-playbook playbooks/configure_loadbal.yml -e tier=loadbal_pgdog
        ansible-playbook playbooks/spin_tier.yml -e tier=loadbal_app
        ansible-playbook playbooks/configure_loadbal.yml -e tier=loadbal_app -e loadbal_vip=192.168.4.171
        ansible-playbook playbooks/configure_airport.yml --tags airport_app
        ;;
    down)
        ansible-playbook playbooks/teardown_guests.yml -e teardown_confirm=true
        ;;
    *)
        usage
        die "pass up or down"
        ;;
esac
