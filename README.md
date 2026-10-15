# lumynex_iaas

Felix owns this repo. It replaces the Ansible that used to live in `old_repos/lumynex` and was removed in the "before reinstall" commit.

That tree had one `create_vm.yml` and four playbooks that shelled out to `uv run ansible-playbook` to call it. Destroy took a single name and failed when the guest was already gone. Guest identity was copy-pasted into `hosts.ini` and into those wrappers.

Guests are now data in `inventory/group_vars/guests.yml`. The role `roles/proxmox_guest` creates or destroys one guest. Playbooks only choose the state.

## Teardown

This destroys the fourteen guests from the pre-reinstall inventory. It does not destroy `prhqp-proxmox-1`, `prhqp-proxmox-2`, or `node_32core_ubuntu`.

Copy the inventory, then confirm on the command line. Without `teardown_confirm=true` the play refuses to run.

```bash
cp inventory/hosts.ini.example inventory/hosts.ini
ansible-playbook playbooks/teardown_guests.yml -e teardown_confirm=true
```

A guest that is already absent is skipped. A template is never destroyed. Disks are purged.

## Build order

Each tier is created, then configured, before the next tier starts. Configure writes one file under `~/.config/lumynex/` and leaves the secrets there. Those files are not in git.

1. OpenBao writes `openbao.env`.
2. Postgres, Patroni, and etcd read `openbao.env` and write `postgresql.env`.
3. Django app guests.
4. PgDog in front of Postgres.
5. Web load balancers in front of the Django guests.

Stages 3–5 are not playbooks yet.

```bash
ansible-playbook playbooks/spin_tier.yml -e tier=openbao
ansible-playbook playbooks/configure_openbao.yml
```

## One tier

Build and remove one feature without touching the others. The loop creates the guests and destroys them. It does not install the product.

OpenBao and Postgres have `node` and `template` filled in. Other tiers fail the placement check until those fields are added. Guests are created n1 first, one at a time, so `pvesh get /cluster/nextid` is not shared. Teardown walks that tier from the top of `guests.yml`.

```bash
ansible-playbook playbooks/spin_tier.yml -e tier=openbao
ansible-playbook playbooks/teardown_tier.yml -e tier=openbao -e teardown_confirm=true
```

To apply one guest first:

```bash
ansible-playbook playbooks/spin_tier.yml \
  -e tier=openbao \
  -e member=prhqv-cl1-openbao-n1
```

## Postgres, Patroni, and etcd

`spin_tier` creates the five guests. `configure_postgres.yml` requires `openbao.env`, stores the Postgres passwords in OpenBao, and writes `postgresql.env`. That file has `PGHOST`, `PGUSER`, `PGPASSWORD`, the replicator password, and each `sysmaint` password. PostgreSQL listens on all interfaces. `pg_hba` allows `192.168.4.0/22` plus loopback. etcd and the Patroni REST port are still plaintext HTTP, which is how that cluster was formed. A second run leaves a node alone once `/etc/patroni/patroni.yml` exists and does not rotate passwords.

```bash
ansible-playbook playbooks/spin_tier.yml -e tier=postgres
ansible-playbook playbooks/configure_postgres.yml
```

```bash
ansible-playbook playbooks/teardown_tier.yml -e tier=postgres -e teardown_confirm=true
```

## Spin one guest

`present` clones from a template when the name is missing and leaves an existing guest alone.

```bash
ansible-playbook playbooks/spin_guest.yml \
  -e proxmox_node=prhqp-proxmox-1 \
  -e vm_name=prhqv-cl1-app-n1 \
  -e template_name=vanilla-26a
```

Two playbooks at once can still race on `pvesh get /cluster/nextid`.

## What is not here

PgDog, the Django app, the web load balancers, and PMM are not playbooks yet. OpenBao listens with TLS off, which is how the old cluster was formed. The root token and unseal keys are written only under `~/.config/lumynex/`. Secrets from `ansible/vault/secrets.yml` were not copied.
