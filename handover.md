# handover — deployment strategy review (july 2026)

summary of a conversation reviewing the deployment setup, weighing alternatives, and landing on a direction. written to be picked up cold by future-me or a future session.

## tl;dr

- the swarm setup is sound and correctly built, but swarm isn't earning its keep against the immediate goals (linux fundamentals, immich, backups)
- **direction chosen: hybrid.** a swarm manager is still a normal docker engine — plain compose runs alongside swarm stacks. migrate per-service when there's a concrete reason to touch one, no big-bang rewrite
- **first concrete move: migrate immich from swarm to plain compose during the already-planned named-volumes → bind-mounts migration** (have to stop it and move data anyway)
- backup decision (restic + backrest, ext4, 4 repos — see `backup-software-decision.md`) was NOT reopened. it stands. the work path to backups is sequenced below
- k8s/k3s explicitly ruled out. staying in the compose/swarm arena

---

## 1. review of the current setup

### what's genuinely good

- compose files use swarm secrets correctly: `external: true`, `*_FILE` env vars, `/run/secrets/` mounts, per-service scoping
- secret values piped over ssh stdin, not command line — they never hit `deploy.log` or shell history
- no `.env` files or logs ever committed to git (verified full history)
- the `*_FILE` discipline transfers directly to any production setup

### issues found in deploy.sh

| issue | where | detail |
|---|---|---|
| rotation doesn't converge | `deploy.sh:141-152` | secrets in use are silently skipped — editing a local `.env` value does nothing for a running service. this is WHY the manual ssh/stop/rm/redeploy rotation script had to exist. (already noted in `todo.md`) |
| trailing newline in secrets | `deploy.sh:151` | `echo "$value"` appends `\n`. postgres strips it; a node app reading the file gets `"...token\n"` → silent auth failures. fix: `printf '%s'` |
| rebuilds may not redeploy | `deploy.sh:171` | building `dir:latest` + `docker stack deploy` with an unchanged tag often doesn't roll the service — new code builds but doesn't ship. fix: tag with git sha |
| dead error branches | e.g. `deploy.sh:154,190` | `set -e` exits before any `if [[ $? -eq 0 ]] ... else` branch can run; `$?` after an `if` is the if's status anyway |
| local/remote dir coupling | `deploy.sh:93,101` | service list comes from `find` on the REMOTE checkout, but the subshell `cd`s into the LOCAL dir of the same name. a remote-only dir kills the whole deploy under `set -e` |
| dead code | `deploy.sh:204` | `mkdir -p ~/immich/{library,postgres}` predates the switch to named volumes |

### the rotation fix (if staying on swarm anywhere)

versioned secret names: `immich_db_password_v2` (or suffix with a content hash), reference the new name in compose, `docker stack deploy` → rolling update onto the new secret. no stop, no rm, no downtime. old versions gc'd whenever. this alone eliminates the manual rotation script.

### gotchas outside the script

- **UFW is not protecting published ports.** docker/swarm iptables rules bypass ufw — 2283, 9443, 9000, 8090 etc. are reachable regardless of the careful `ufw allow` list in `host-setup.sh`. fine on a home LAN, but if exposure ever matters the answer is the `DOCKER-USER` chain (or a proxy-only port surface), not ufw rules
- **push access to master = root on the server.** deploy is "git pull whatever's on master, run it with docker socket access." acceptable for a personal repo; be conscious of it. portainer/beszel socket mounts are full-trust components for the same reason

---

## 2. deployment strategy alternatives considered

context: the swarm choice was originally made to (a) get safe per-service secret injection and (b) mimic a production deployment for a business workload — a lightweight server pulling a csv, transforming it, serving it over sftp.

key reframe: that workload is **a cron job plus a file server**. the hard production problems for it are "did the 3am pull fail and would i know", credential/host-key hygiene, and backups — not orchestration.

options surveyed:

1. **plain compose + systemd timers** — the boring default; most faithful mimicry of what small businesses actually run on a single vps. compose supports file-based `secrets:` WITHOUT swarm (bind-mounted, not tmpfs; `*_FILE` pattern carries over unchanged)
2. **swarm (current)** — already paid the learning cost, but weakest on the mimicry argument: single-node swarm is niche in real production. what transfers is the discipline (file secrets, declarative stacks, scripted deploy), not the swarm api itself
3. **compose + SOPS/age** — encrypt `.env` files, commit them; repo becomes single source of truth, rotation = git commit, dr = clone + one age key. fixes the "local .env is invisible state" problem
4. **ansible (or bash made idempotent)** — `host-setup.sh`/`deploy.sh` are hand-rolled non-idempotent ansible; idempotent config mgmt is a bigger real-world skill than any orchestrator
5. **k3s** — best employability, `CronJob` maps perfectly to the csv workload, but severe complexity tax. **ruled out**
6. **no containers (systemd-native)** — for the actual business workload arguably correct (systemd timer + `LoadCredential=` + openssh `internal-sftp` chroot), but least reusable for the homeserver

recommendation for the business-mimicry goal (now background): 1 + 3 + light 4.

### honest read on single-node swarm secrets

what you get: tmpfs mount, not visible in `docker inspect`, not in the image, encrypted in raft. what limits it: on a single node the raft encryption key sits on the same disk as the secrets. real but modest vs a root-owned 600-perm file. the bigger win was always the `*_FILE` app-side pattern, which works under plain compose too.

### "compose isn't recommended for production" — unpacked

that advice translates to "not for **multi-node, high-availability** production," which a single home server can't be anyway:

- no multi-node/HA → irrelevant, the node is the SPOF either way
- no rolling updates → true; swarm's one honest advantage. compose recreate = seconds of downtime. irrelevant for LAN immich
- no encrypted secret store → thin gap on a single node (see above); compose `secrets:` keeps the same app-facing interface
- no reconciliation loop → `restart: unless-stopped` behaves nearly identically on one node

---

## 3. immediate goals and what they imply

goals, re-anchored mid-conversation:

1. learn foundational linux sysadmin
2. set up immich
3. back up immich to a 2nd place on the server AND to the desktop pc

implication: the orchestrator debate mostly evaporates. goal 1 lives a layer below any orchestrator (fstab, uuids, permissions, ssh, systemd timers, restic). goals 2–3 are "run one well-documented app and copy its data around reliably."

why immich specifically should move to plain compose (during the storage migration, near-free since immich must be stopped anyway):

- immich's official docs/upgrades/community troubleshooting all assume compose; every swarm divergence (ignored `container_name`/`depends_on`, healthcheck quirks) is friction with no learning payoff
- restore becomes the textbook procedure: `compose down` → restore files → restore db dump → `compose up -d`
- immich's only real secret is a postgres password on a LAN-only container network; a 600-perm `.env` is proportionate

### the sequenced path to backups (builds on todo.md + backup-software-decision.md)

1. ground truth on disks: `lsblk`, `blkid`, `df -h`, `findmnt` (already first in todo.md)
2. format ext4, mount via UUID in `/etc/fstab`. NOTE: if the server gets two new hdds, put live immich data on one and the server-local restic repo on the other — upgrades the "2nd copy on server" from accidental-delete protection to real drive-failure protection (the decision doc flags the same-disk limitation)
3. migrate immich to bind mounts at `/mnt/hdd/services/immich/` and swap `docker stack deploy` → `docker compose up -d` in the same operation. careful data copy first (postgres: dump/restore or stop-and-copy)
4. confirm immich's built-in daily db dump is on (dumps into `UPLOAD_LOCATION/backups/`). **never back up the live postgres data dir — a raw copy of a running db is inconsistent garbage.** back up the dumps; exclude live `postgres/` from restic. schedule restic AFTER the nightly dump
5. set up restic repos by hand first (init/backup/snapshots/restore from the cli — that's the goal-1 learning), THEN hand scheduling to backrest per the existing decision
6. mind the load-bearing flow: server → desktop-hdd is what actually protects the photos, it's push-based, and it only runs when the desktop is on and reachable. decide explicitly how to handle that (schedule for reliably-on hours, backrest retries, or wake-on-lan)
7. **do one restore drill.** restore a photo + db dump to a scratch dir and boot a throwaway immich against it. an untested backup is a hypothesis

---

## 4. swarm/compose coexistence (the unlock)

- a swarm manager node is a completely normal docker engine. `docker compose up -d` works on it, side by side with stacks. not a hack
- plain containers can join an overlay network created with `--attachable` — `management_net` already is (`deploy.sh:80`)
- gotchas: shared published-port pool (no collisions between stacks and compose projects); swarm's routing mesh binds published ports on all interfaces
- the real cost is cognitive: two deployment models, two answers to "how do i restart this." fine as a migration path, less fine forever

### future internet exposure — what it actually requires

none of it is an orchestrator feature; every item works identically on compose and swarm:

- reverse proxy + TLS: caddy (simplest) or traefik (label-based, more to learn). one entry point; services stop publishing ports directly
- ideally don't expose the home IP at all: tailscale/wireguard for personal access (sane default for a photo library), cloudflare tunnel or cheap vps relay for genuinely public things
- network segmentation: exposed services on their own docker network, unable to reach immich's db
- fix the ufw illusion via `DOCKER-USER` chain once exposure is real
- auth in front of admin UIs (authelia/authentik territory, later)

---

## 5. where things landed

- **hybrid, migrate opportunistically.** no forced big-bang; each service moves when there's a concrete reason to touch it
- **immich → plain compose** as part of the bind-mount migration (swap `external: true` secrets for `file:` sources; app-side `*_FILE` pattern unchanged)
- portainer/beszel/test-web-server stay on swarm until wound down or the business-mimicry project needs it again
- caddy or traefik in front when exposure becomes real; vpn-first for personal services
- k8s/k3s: no
- backup tooling decision (restic + backrest, ext4, 4 repos): unchanged, see `backup-software-decision.md`

### natural next artifacts

- compose-converted `immich/docker-compose.yml` (bind mounts at `/mnt/hdd/services/immich/`, file-based secrets)
- a written migration runbook for the storage move (step 3 above)
- deploy.sh fixes if it's kept for the remaining swarm services: `printf '%s'` for secrets, versioned secret names, git-sha image tags, drop dead code
