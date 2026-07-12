# stack map — layers, decisions, and what cascades where

the purpose of this file: when a decision comes up (or a shiny new tool appears), find which layer it lives at, check whether that layer is already decided, and only reopen it if a revisit trigger actually fires. this is the antidote to "everything feels connected to everything."

companion docs: `handover.md` (july 2026 strategy review), `backup-software-decision.md`, `todo.md`.

## the goals (fixed reference point)

1. **learn transferable linux fundamentals** — things that carry across distros, jobs, and domains: disks/fstab/UUIDs, permissions, ssh, systemd, networking, backups
2. **run immich** on the server
3. **backups in both directions** — immich → 2nd place on server + desktop pc; desktop pc → server
4. **be ready for future services** — self-hosted git, journal syncing, 3d printer controller, whatever comes next

every decision below should be justifiable against at least one of these.

---

## the layers

| # | layer | current state | status |
|---|---|---|---|
| 0 | hardware | server (ssd os + 14tb hdd), desktop (ssd + 14tb hdd) | **decided** (purchased) |
| 1 | operating system | debian on the server | **decided** |
| 2 | filesystem & mounts | ext4, fstab by UUID (not yet executed) | **decided** |
| 3 | host configuration | hand-rolled `host-setup.sh` | open, **not blocking** |
| 4 | container runtime / orchestration | docker; hybrid swarm→compose, migrating opportunistically | **decided** |
| 5 | deployment & secrets | `deploy.sh` + swarm secrets; compose `secrets:` for migrated services | semi-open, not blocking |
| 6 | services | immich, portainer, beszel, test-web-server | per-service |
| 7 | backup | restic + backrest, 4 repos | **decided** |
| 8 | network exposure | LAN-only today | **deferred** until exposure is real |

the headline: **everything on the critical path to immich + backups is already decided.** the open items (host config tooling, which monitoring gui, exposure stack) are either non-blocking or explicitly deferred.

---

## layer 0 — hardware

2 × 14tb drives, one per machine. server: small ssd (os only) + 14tb (live immich data AND server-local restic repo — same-disk, so that repo is accidental-delete protection only; drive-failure protection for photos comes from the desktop copy).

**cascades into:** layer 2 (what to format), layer 7 (repo layout).
**revisit trigger:** a drive dies, or a 3rd drive appears (then: split live data from local backup repo on the server).

## layer 1 — operating system

debian. boring, stable, the thing most real servers run.

**what lives here:** distro choice, release upgrades, kernel.
**nixos goes here.** it is a whole-paradigm replacement of layers 1, 3, and 5 at once. verdict: **conflicts with goal 1.** nixos skills famously don't transfer (its whole point is being unlike standard linux); debian admin IS the transferable baseline. also its declarative payoff overlaps what docker compose files already give at layer 5.
**cascades into:** everything. which is exactly why it stays boring.
**revisit trigger:** honestly, none for this project. if declarative-everything becomes its own learning goal someday, that's a new project, not a change to this one.

## layer 2 — filesystem & mounts

**decided: ext4, mounted by UUID in `/etc/fstab`.** decided together with the backup tool — see `backup-software-decision.md`, which considered btrfs (option B) and **zfs (option C)** on their merits and rejected them.

**zfs goes here.** the benefits in that video (snapshots, checksumming, send/receive) were on the table when ext4 was chosen. the reasoning that still holds: restic already provides snapshots + dedup + transfer from outside the filesystem; zfs needs a dkms module that can break on debian kernel upgrades; more ram, more concepts (pools/vdevs/datasets); cow gotchas with postgres and docker. keep the filesystem boring, let the tool be clever.
**the one thing zfs would add that restic doesn't:** live checksumming catches silent bit rot on the *live* copy. restic faithfully backs up corrupted data.
**cascades into:** layer 7 (repo layout paths), immich bind-mount paths.
**revisit triggers:** silent corruption actually observed; a mirrored-drive setup on the server (zfs shines with redundancy, is weakest on a single disk); this becoming a dedicated learning goal.

## layer 3 — host configuration

how the OS itself gets set up: users, ssh hardening, ufw, docker install, mounts, packages. currently `host-setup.sh` — hand-rolled, non-idempotent bash.

**ansible goes here.** it is NOT an alternative to portainer (layer 6 gui) or nixos (layer 1). verdict from the july review: idempotent config management is a bigger real-world skill than any orchestrator — **well aligned with goal 1** — but it is a rebuild-time concern. nothing about immich or backups waits on it.
**cascades into:** disaster recovery story (how fast can the server be rebuilt from nothing).
**decide when:** after the storage + immich + backup work is done, as its own learning block. options then: ansible-ify `host-setup.sh`, or just make the bash idempotent first (cheaper, teaches the same concept).

## layer 4 — container runtime / orchestration

**decided (july 2026): hybrid.** docker everywhere; new/touched services run plain compose; existing swarm stacks stay until there's a concrete reason to touch them. k8s/k3s ruled out. immich moves to compose during the bind-mount migration.

the principle that unlocked this: services stay in containers (isolation instinct is correct), but isolation comes from networks + minimal mounts, not from the orchestrator. swarm was solving a secrets problem compose already solves.

**cascades into:** layer 5 (how secrets are wired), layer 6 (compose file dialect).
**revisit trigger:** a real multi-node need appears (it won't, on one server).

## layer 5 — deployment & secrets

how compose files and secrets get onto the server and become running containers. currently `deploy.sh` (git pull on server + `docker stack deploy` + swarm secrets over ssh stdin). known bugs catalogued in `handover.md` §1.

for migrated services: compose file-based `secrets:` + `*_FILE` env vars — same app-facing pattern, 600-perm files instead of tmpfs. proportionate for LAN-only postgres passwords.

**SOPS/age goes here** (encrypt secrets, commit them, repo becomes the single source of truth). nice-to-have, not blocking.
**cascades into:** rotation story, disaster recovery.
**decide when:** if/when the "local .env is invisible state" problem actually bites, or as a learning block after backups work.

## layer 6 — services

each service is a mostly-leaf node. **adding a service touches layers 5–7 only** (a compose file, a secret file, a backup include) — this is what "ready for future services" (goal 4) means, and it's already true.

- **immich** — the current focus. moving to bind mounts + plain compose in one operation.
- **portainer goes here.** it's a management gui service, not infrastructure. open todo: pick ONE of portainer/beszel and make it healthy, wind down the other. small decision, contained to this layer.
- **future: forgejo/gitea, journal sync, octoprint/klipper** — each is "write a compose file, add to backup includes." no stack decisions required.

## layer 7 — backup

**decided: restic + backrest, ext4 underneath, 4 repos** (see `backup-software-decision.md` — including when to revisit). not reopened by the july review; not reopened by this file.

the load-bearing detail: server → desktop is push-based and only runs when the desktop is on. the schedule needs an explicit answer (reliably-on hours / backrest retries / wake-on-lan).

**cascades from:** layer 2 (paths), layer 6 (what to include; never the live postgres dir — back up immich's nightly dumps).
**revisit triggers:** already written down in the decision doc.

## layer 8 — network exposure

**deferred, deliberately.** today: LAN-only. when exposure becomes real, the checklist (all orchestrator-independent): vpn-first (tailscale/wireguard) for personal services like immich; reverse proxy + TLS (caddy simplest) for anything genuinely public; per-service docker networks so an exposed service can't reach immich's db; fix the ufw illusion via the `DOCKER-USER` chain; auth in front of admin uis.

**cascades from:** almost nothing above — that's why deferring is safe.
**decide when:** the first time something actually needs to be reachable from outside.

---

## the decision protocol (anti-overwhelm)

when a new tool/idea/video shows up:

1. **which layer is it?** (nixos→1, zfs→2, ansible→3, portainer→6, tailscale→8...)
2. **is that layer decided?** if yes → does a written revisit trigger fire? if no trigger fires, add a one-line note to this file if it's genuinely interesting, and move on. that's not dismissiveness — the decision docs already weighed it.
3. **is it on the critical path?** the critical path is: disks → fstab → immich migration → restic → restore drill. if it's not on that path, it goes to `todo.md`'s "later" section, not into today's work.

decisions mostly cascade **downward in layer number → outward in blast radius**. layer 1–2 choices touch everything (keep them boring); layer 6 choices touch almost nothing (be adventurous there — that's what the homelab is for).
