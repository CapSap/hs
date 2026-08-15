# Homeserver

A Debian home server for photos and backups and other things, plus the notes from learning to run
it. Services are Docker containers; Immich runs on plain Docker Compose.

## Goals

- Back up phone photos (via Immich)
- Back up both the server and the desktop
- Install a 3D printer controller
- Learn Linux server administration along the way — the _why_, not just commands
  that happen to work

## The two machines

This is a two-machine project, and confusing them wastes time. They are separate
hardware with separate disk layouts.

|             | `shelaria-s` (server)          | `sheelah-d` (desktop)                        |
| ----------- | ------------------------------ | -------------------------------------------- |
| hardware    | Lenovo ThinkCentre M910s       | desktop PC                                   |
| OS          | Debian 12 (bookworm)           | Debian 13 (trixie)                           |
| disks       | 238G SSD (LVM) + 12.7T HDD     | 1.9T NVMe + 12.7T HDD                        |
| big disk at | `/mnt/hdd` (in fstab, by UUID) | not yet in fstab — see todo                  |
| role        | runs the services              | drives deploys; holds the second backup disk |

There is no cloud server. `deploy.env` calls the server `DROPLET_HOST` — that's
leftover naming from the DigitalOcean template this repo was scaffolded from.

## Where things live

- **Service definitions** — `server/<service>/docker-compose.yml`
- **Immich's data** — `/mnt/hdd/services/immich/{library,database,model-cache}`
  on the server, bind-mounted into the containers
- **Secrets** — files in `server/<service>/secrets/`, gitignored, mode 600,
  mounted at `/run/secrets/<name>`
- **Non-secret config** — `server/<service>/.env`, also gitignored (paths,
  timezone, version pins)
- **The server's checkout** — `/home/shelaria/box`

## Services

- **Immich** — photo management and backup. **Running**, on plain Compose
- **test-web-server** — Node.js app (norm-tribute)

## How deployment works

Immich has moved to **plain Docker Compose**, run on the server:

```bash
./server/sync-secrets.sh                    # from the desktop: rsync secret files over
ssh debian-box
cd ~/box && git pull
cd server/immich && docker compose up -d
```

**`deploy.sh` is legacy and should not be run.** It is Swarm-based: it would
re-initialise Swarm on a box that has since left it, then `docker stack deploy`
compose files no longer written for Swarm. It also has known bugs (it appends a
trailing newline to every secret, and silently skips rotating a secret that's in
use). It remains only because Portainer/Beszel were last deployed with it. See
`docs/decisions/swarm-vs-compose-decision.md`.

`host-setup.sh` is still correct for first-time provisioning of a fresh box
(Docker install, firewall), minus the Swarm step.

## Start here

If you're returning after a gap, read in this order:

1. **[docs/system-state.md](docs/system-state.md)** — ground truth for the
   server: disks, UUIDs, LVM, mounts, Docker's data-root, the git checkout.
   Every fact is one someone ran a command to confirm
2. **[docs/desktop-state.md](docs/desktop-state.md)** — the same, for the desktop
3. **[docs/todo.md](docs/todo.md)** — what's actually next
4. **[docs/stack-map.md](docs/stack-map.md)** — the decision layer: why things
   are as they are, and when to reopen a choice

The rule those docs follow: **run a command that changes the box → update
`system-state.md`; make a choice → update `stack-map.md`.** Facts get a ✔ only
when they've been re-derived on the live machine, never when they're remembered.

## Further reading

- [Migration runbook](docs/immich-migration-runbook.md) — the Swarm + named
  volumes → Compose + bind mounts migration, step by step, with results
- [Containers & orchestration primer](docs/containers-and-orchestration.md) —
  how containers actually work (kernel pillars → Docker → Compose → Swarm → k8s)
- [Backup software decision](docs/decisions/backup-software-decision.md) — note
  the divergence warning at the top; reality went a different way
- [Working notes](docs/scratch-notes.md) — the running log
- [Homeserver reference repo](https://github.com/zilexa/Homeserver)

## History

I intially thought i had to use docker swarm for production and safe secrets. ive
since learned that docker-compose is fine.
but i did spend a lot of time second guessing myself and feeling overwhelmded

Later addition: the project stalls for months at a time, and each restart used to
begin by re-deriving facts that were already known once. That's what the
`*-state.md` files are for. They're not documentation for anyone else — they're
notes to whoever picks this up next, which is always me, having forgotten.
