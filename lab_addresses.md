# Lab addresses and OpenBao

This page is the cl1 lab address list and the commands that read each secret from OpenBao. Secret values stay in OpenBao and in `~/.config/lumynex/`. This file records paths and addresses only.

The lab network is `192.168.4.0/22`. Guest addresses were discovered from the QEMU guest agent into `inventory/host_vars/`. `prhqv-cl1-pmm-n1` is `192.168.5.118` on this boot (VMID 124). That address changes when the guest is rebuilt.

## Hypervisors

These three machines host the guests. SSH to them uses `root`. The same names are in `agent_governance/context/lumynex/proxmox_inventory.md`.

| Name | Address |
| --- | --- |
| prhqp-pve1 | 192.168.4.215 |
| prhqp-pve2 | 192.168.4.113 |
| prhqp-pve3 | 192.168.4.111 |

## Guests

Each row is one guest, the address Ansible uses, and the Proxmox VMID. SSH to a guest uses `harperjm`.

| Name | Address | VMID | Role |
| --- | --- | --- | --- |
| prhqv-cl1-openbao-n1 | 192.168.4.81 | 102 | OpenBao |
| prhqv-cl1-openbao-n2 | 192.168.4.82 | 103 | OpenBao |
| prhqv-cl1-openbao-n3 | 192.168.4.83 | 104 | OpenBao |
| prhqv-cl1-postgresql-n1 | 192.168.4.84 | 105 | PostgreSQL |
| prhqv-cl1-postgresql-n2 | 192.168.4.85 | 106 | PostgreSQL |
| prhqv-cl1-postgresql-n3 | 192.168.4.86 | 107 | PostgreSQL |
| prhqv-cl1-postgresql-n4 | 192.168.4.87 | 108 | PostgreSQL |
| prhqv-cl1-postgresql-n5 | 192.168.4.88 | 109 | PostgreSQL |
| prhqv-cl1-app-n1 | 192.168.4.90 | 110 | Django |
| prhqv-cl1-app-n2 | 192.168.4.91 | 111 | Django |
| prhqv-cl1-app-n3 | 192.168.4.92 | 112 | Django |
| prhqv-cl1-pgdog-n1 | 192.168.4.93 | 113 | PgDog |
| prhqv-cl1-pgdog-n2 | 192.168.4.94 | 114 | PgDog |
| prhqv-cl1-loadbal-n3 | 192.168.4.98 | 115 | HAProxy in front of PgDog |
| prhqv-cl1-loadbal-n4 | 192.168.4.99 | 116 | HAProxy in front of PgDog |
| prhqv-cl1-loadbal-n1 | 192.168.4.100 | 117 | HAProxy in front of Django |
| prhqv-cl1-loadbal-n2 | 192.168.4.101 | 118 | HAProxy in front of Django |

## Client addresses

Keepalived holds these addresses on a load-balancer pair and moves them when HAProxy on that pair stops. Clients use the virtual IP. Node addresses above are for admin.

| Client address | Port | Held by | Forwards to |
| --- | --- | --- | --- |
| 192.168.4.170 | 6432 | prhqv-cl1-loadbal-n3, prhqv-cl1-loadbal-n4 | PgDog guests |
| 192.168.4.171 | 80 | prhqv-cl1-loadbal-n1, prhqv-cl1-loadbal-n2 | SaaS Django guests |
| 192.168.4.172 | 80 | prhqv-cl1-loadbal-n1, prhqv-cl1-loadbal-n2 | Airport load test on the Django guests, port 8080 |

`192.168.4.172` is the airport load page. `192.168.4.171` stays the SaaS address.

## How to read a secret

Run these commands from the `lumynex_iaas` directory. `./scripts/openbao-login` reads `~/.config/lumynex/openbao.env` and prints `BAO_ADDR` and `BAO_TOKEN` for the current shell. That file points `BAO_ADDR` at `http://192.168.4.81:8200`, which is `prhqv-cl1-openbao-n1`. `./scripts/openbao-get` prints one field. `--check` exits 0 when the field exists and prints nothing.

```bash
eval "$(./scripts/openbao-login)"
./scripts/openbao-get secret/lumynex/postgresql/cl1/cluster postgres_password
./scripts/openbao-get --check secret/lumynex/postgresql/cl1/cluster postgres_password
```

The root token and unseal keys are in `~/.config/lumynex/openbao.env` and `~/.config/lumynex/openbao-init.json`. Those files are mode `600` and are outside git.

## Guest sysmaint passwords

Each guest has its own `sysmaint` secret. The field to read is `sysmaint_password`. The same secret also stores `username` and `host`.

| Tier | OpenBao path |
| --- | --- |
| PostgreSQL | `secret/lumynex/postgresql/<hostname>` |
| Django | `secret/lumynex/app/<hostname>` |
| PgDog | `secret/lumynex/pgdog/<hostname>` |
| Load balancer | `secret/lumynex/loadbal/<hostname>` |
| PMM | `secret/lumynex/pmm/<hostname>` |

```bash
./scripts/openbao-get secret/lumynex/postgresql/prhqv-cl1-postgresql-n1 sysmaint_password
./scripts/openbao-get secret/lumynex/app/prhqv-cl1-app-n1 sysmaint_password
./scripts/openbao-get secret/lumynex/pgdog/prhqv-cl1-pgdog-n1 sysmaint_password
./scripts/openbao-get secret/lumynex/loadbal/prhqv-cl1-loadbal-n1 sysmaint_password
```

## Cluster secrets

These secrets are shared by a tier. Read one field at a time with `./scripts/openbao-get <path> <field>`.

| Path | Fields |
| --- | --- |
| `secret/lumynex/postgresql/cl1/cluster` | `postgres_password`, `replicator_password`, `scope` |
| `secret/lumynex/app/cl1/cluster` | `django_secret_key`, `database_host`, `database_port`, `database_name`, `database_user`, `database_password`, `scope` |
| `secret/lumynex/pgdog/cl1/cluster` | `admin_password`, `listen_port`, `cluster_id`, `vip`, `scope` |
| `secret/lumynex/loadbal/cl1/pgdog` | `keepalived_password`, `listen_port`, `virtual_router_id`, `scope` |
| `secret/lumynex/loadbal/cl1/app` | `keepalived_password`, `listen_port`, `virtual_router_id`, `vip`, `scope` |
| `secret/lumynex/pmm/cl1` | `admin_password`, `monitor_password` |

The PgDog client address is the `vip` field on `secret/lumynex/pgdog/cl1/cluster`. The Django client address is the `vip` field on `secret/lumynex/loadbal/cl1/app`.

```bash
./scripts/openbao-get secret/lumynex/postgresql/cl1/cluster postgres_password
./scripts/openbao-get secret/lumynex/postgresql/cl1/cluster replicator_password
./scripts/openbao-get secret/lumynex/app/cl1/cluster django_secret_key
./scripts/openbao-get secret/lumynex/app/cl1/cluster database_password
./scripts/openbao-get secret/lumynex/pgdog/cl1/cluster admin_password
./scripts/openbao-get secret/lumynex/pgdog/cl1/cluster vip
./scripts/openbao-get secret/lumynex/loadbal/cl1/pgdog keepalived_password
./scripts/openbao-get secret/lumynex/loadbal/cl1/app vip
```

## Local env files

Each configure play also writes one mode `600` file under `~/.config/lumynex/` for use on this machine. OpenBao remains the store. The files are `openbao.env`, `postgresql.env`, `app.env`, `pgdog.env`, `loadbal-pgdog.env`, and `loadbal-app.env`.


## Getting Secrets from OpenBao

These commands log in and read one field. Secret values stay in OpenBao.

```bash
eval "$(./scripts/openbao-login)"
./scripts/openbao-get secret/lumynex/postgresql/cl1/cluster postgres_password


ssh sysmaint@192.168.4.88
```

192.168.4.81 openbao-n1
192.168.4.82 openbao-n2
192.168.4.83 openbao-n3


cd ~/project-work/new_repos/lumynex_iaas
eval "$(./scripts/openbao-login)"
python3 - <<'PY'
import json, os, urllib.request
keys = json.load(open(os.path.expanduser("~/.config/lumynex/openbao-init.json")))["unseal_keys_b64"][:3]
for addr in ("http://192.168.4.81:8200", "http://192.168.4.82:8200", "http://192.168.4.83:8200"):
    for key in keys:
        req = urllib.request.Request(
            addr + "/v1/sys/unseal",
            data=json.dumps({"key": key}).encode(),
            headers={"Content-Type": "application/json"},
        )
        body = json.load(urllib.request.urlopen(req))
    print(addr, "sealed", body["sealed"], "progress", f"{body['progress']}/{body['t']}")
PY


./openbao-login
export BAO_ADDR=http://192.168.4.81:8200
export BAO_TOKEN=s.7dDUWmlNvLnISnEY9AgSohNO


New API Key Proxmox VE 9.2.21
root@pam!lumynex_iaas
2b64762d-0e07-49ba-bd32-770f22e5cda0


192.168.4.215   prhqp-pve1.lumynex.net
192.168.4.113   prhqp-pve2.lumynex.net
192.168.4.111   prhqp-pve3.lumynex.net

ssh-copy-id -i ~/.ssh/id_ed25519.pub 192.168.4.215
ssh-copy-id -i ~/.ssh/id_ed25519.pub 192.168.4.113
ssh-copy-id -i ~/.ssh/id_ed25519.pub 192.168.4.111



### NFS Shares:
This scratch list is the share John noted while rebuilding. The live share is recorded above.
- prhqp-pve1.lumynex.net
    - peter/iso_share
    - over peter/iso_share
    

### ZFS Volumes:
This scratch list is John's memory of the disks. The live pools are in the Proxmox inventory.
- prhqp-pve1.lumynex.net
    - nana
        - 1.9 TB
        - (1) M.2 NVME 1 TB ZFS Single Disk
    - peter
        - 6.99 TB
        - (8) M.2 NVME 1 TB ZFS RaidZ2
    - tink
        - 1.99 TB
        9 (1) M.2 NVME 1 TB ZFS Single Disk
- prhqp-pve2.lumynex.net
    - michael
        - 7.99 TB
        - (1) External USB ZFS Single Disk
    - wendy
        - 7.99 TB
        - (1) External USB ZFS Single Disk
- prhqp-pve3.lumynex.net
    - croc
        - 13.98 TB
        - (1) External USB ZFS Single Disk
    - hook
        - 798 GB
        - (1) Internal ZFS Single Disk
    - john
        - 476.74
        - (1) Internal ZFS Single Disk
    - smee
        - 476.74
        - (1) Internal ZFS Single Disk
    - tiger
        - 7.99 TB
        - (1) External USB ZFS Single Disk