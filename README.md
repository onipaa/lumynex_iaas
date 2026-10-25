# lumynex_iaas

Felix owns this repo. It replaces the Ansible that used to live in `old_repos/lumynex` and was removed in the "before reinstall" commit. This tree is frozen. Change it only when John asks to change IaaS in the current message.

That tree had one `create_vm.yml` and four playbooks that shelled out to `uv run ansible-playbook` to call it. Destroy took a single name and failed when the guest was already gone. Guest identity was copy-pasted into `hosts.ini` and into those wrappers.

Guests are now data in `inventory/group_vars/guests.yml`. The role `roles/proxmox_guest` creates or destroys one guest. Playbooks only choose the state. Current addresses and the OpenBao read commands are in `lab_addresses.md`.

## Teardown

This destroys every guest in `inventory/group_vars/guests.yml`, including the four load balancer guests. It does not destroy `prhqp-pve1`, `prhqp-pve2`, `prhqp-pve3`, or `node_32core_ubuntu`.

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
3. Django app guests read `openbao.env` and `postgresql.env`, and write `app.env`.
4. PgDog guests read `openbao.env` and write `pgdog.env`.
5. The PgDog load balancer reads those addresses and writes `loadbal-pgdog.env`.
6. The Django load balancer reads the app addresses and writes `loadbal-app.env`.

Stages 3 and 4 create the guests and their accounts. They do not install Django or PgDog. Stages 5 and 6 install HAProxy and keepalived.

```bash
ansible-playbook playbooks/spin_tier.yml -e tier=openbao
ansible-playbook playbooks/configure_openbao.yml
```

## One tier

Build and remove one feature without touching the others. The loop creates the guests and destroys them. It does not install the product.

OpenBao, Postgres, the app guests, the PgDog guests, the PMM server, and both load balancer pairs have `node` and `template` filled in. Other tiers fail the placement check until those fields are added. Guests are created n1 first, one at a time, so `pvesh get /cluster/nextid` is not shared. Teardown walks that tier from the top of `guests.yml`.

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

## Percona PMM

One guest, `prhqv-cl1-pmm-n1`, runs the PMM server. The PostgreSQL nodes run the PMM client and `pg_stat_monitor`. Query examples keep the literal text from the first execution because `pgsm_normalized_query` is off. Prepared-statement bind values are not stored by `pg_stat_monitor`; statements slower than one second write those values to the PostgreSQL log through `log_parameter_max_length` and `auto_explain`. Passwords live in `secret/lumynex/pmm/cl1`. A second run does not rotate them. Publishing the libraries restarts each PostgreSQL node that is pending, replicas first.

```bash
ansible-playbook playbooks/spin_tier.yml -e tier=pmm
ansible-playbook playbooks/configure_pmm.yml
```

## Django guests

`spin_tier` creates the three guests at the old size: 1 socket, 6 cores, 12288 MB. `prhqv-cl1-app-n1` is on `prhqp-pve1`, `prhqv-cl1-app-n2` is on `prhqp-pve2`, and `prhqv-cl1-app-n3` is on `prhqp-pve3`. `configure_app.yml` requires `openbao.env` and a configured Postgres leader. It stores each `sysmaint` password and the app cluster secret in OpenBao, then writes `app.env`. A second run does not rotate those secrets. The database role `lumynex_app` is not created here.

```bash
ansible-playbook playbooks/spin_tier.yml -e tier=app
ansible-playbook playbooks/configure_app.yml
```

```bash
ansible-playbook playbooks/teardown_tier.yml -e tier=app -e teardown_confirm=true
```

## PgDog guests

`spin_tier` creates three guests: 1 socket, 4 cores, 8192 MB, one on each Proxmox node. `configure_pgdog.yml` installs PgDog on those guests and points it at every PostgreSQL node with `role = "auto"`. Reads stay off the primary. Clients use `192.168.4.170:6432`, which the PgDog load-balancer pair holds. A second run does not rotate the admin password.

```bash
ansible-playbook playbooks/spin_tier.yml -e tier=pgdog
ansible-playbook playbooks/configure_pgdog.yml
```

```bash
ansible-playbook playbooks/teardown_tier.yml -e tier=pgdog -e teardown_confirm=true
```

## Load balancers

HAProxy and keepalived run as two pairs. One pair sits in front of PgDog. The other sits in front of the Django guests. Each pair is split across two of the three Proxmox hosts, and keepalived moves that pair's client address when HAProxy stops. CPU and memory stay at the vanilla template size, because no earlier load balancer size is recorded. Disk is a full clone on `local-lvm`. The network is `192.168.4.0/22`. These plays install the packages. They do not install Django or PgDog, and they do not enable a host firewall.

The PgDog pair is `prhqv-cl1-loadbal-n3` and `prhqv-cl1-loadbal-n4`. It owns `192.168.4.170` and forwards TCP `6432` to the PgDog guests. Configure the PgDog guests first so that address is already in OpenBao. A second run does not rotate the keepalived password. The node that wins the address keeps it until its HAProxy check fails.

```bash
ansible-playbook playbooks/spin_tier.yml -e tier=loadbal_pgdog
ansible-playbook playbooks/configure_loadbal.yml -e tier=loadbal_pgdog
```

```bash
ansible-playbook playbooks/teardown_tier.yml -e tier=loadbal_pgdog -e teardown_confirm=true
```

The Django pair is `prhqv-cl1-loadbal-n1` and `prhqv-cl1-loadbal-n2`. It owns `192.168.4.171` and forwards HTTP `80` to nginx on the app guests. The first configure stores that address; a second run keeps it. A new address has to be inside `192.168.4.0/22` and different from `192.168.4.170`. Logs go to `/var/log/haproxy.log` on each guest. The two nodes of a pair are configured one at a time.

```bash
ansible-playbook playbooks/spin_tier.yml -e tier=loadbal_app
ansible-playbook playbooks/configure_loadbal.yml -e tier=loadbal_app -e loadbal_vip=<address>
```

```bash
ansible-playbook playbooks/teardown_tier.yml -e tier=loadbal_app -e teardown_confirm=true
```

## Spin one guest

`present` clones from a template when the name is missing and leaves an existing guest alone.

```bash
ansible-playbook playbooks/spin_guest.yml \
  -e proxmox_node=prhqp-pve1 \
  -e vm_name=prhqv-cl1-app-n1 \
  -e template_name=vanilla-26a
```

Two playbooks at once can still race on `pvesh get /cluster/nextid`.

## What is not here

The Django application, the PgDog proxy, and PMM are not playbooks yet. OpenBao listens with TLS off, which is how the old cluster was formed. The root token and unseal keys are written only under `~/.config/lumynex/`. Secrets from `ansible/vault/secrets.yml` were not copied.
