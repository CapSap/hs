The intent of this file is to store the long term todos that are not actively being worked on. Notes is for active work

- [x] consider backup strategy and decide on filesystem type → decided on ext4 + restic (see notes.md)

**Commands used (now understood — july 2026):**

```bash
sudo mount /dev/sdb1 /mnt/hdd/   # attach sdb1's filesystem at /mnt/hdd (one-off, gone after reboot)
sudo umount /mnt/hdd             # detach it
sudo mount -a                    # mount everything listed in /etc/fstab — the persistent version
```

(the fstab entry by UUID is what makes /mnt/hdd survive reboots — verified present. the storage ground-truth facts + the commands that reveal them live in `system-state.md`.)

## april-2026: once again for the first time

- [x] ssh to the server and run `lsblk`, `blkid`, `df -h`, `findmnt` — done july 2026. findings: 14tb (sdb1) already ext4 + mounted at /mnt/hdd with 76G on it; **/home is 100% full (83G/85G)**; ~119G looks unallocated in the LVM volume group; still to verify: fstab entry by UUID for sdb1
- [x] decide disk layout for the new hdds — discovered already done (july 2026): sdb1 is ext4, mounted at /mnt/hdd via UUID in fstab. correct as-is. root cause of full /home found: docker data-root is `/home/docker-data/docker` (83G) — immich volumes live on the small ssd, not the 14tb drive. fix = the planned bind-mount migration, now urgent
- [x] **finish the immich migration — ✔ DONE 2026-08-16. IMMICH IS RUNNING**, first boot since ~sept 2025. plain compose + bind mounts + file secrets on the 14tb drive, pinned to `v1.138.0`. steps 0–7a of `docs/immich-migration-runbook.md`. the storage migration is *proven*, not merely plausible — a booting app validates the data in a way no rsync check could. what it took, in the end: one `.env` file. everything else was already done and just not known to be done
- [ ] **finish the immich work — steps 7b/7c.** in order: (1) **tag the cached `v1.138.0` images** if not already done, else a future `docker system prune` destroys the only offline copy matching this database; (2) **step 7b — upgrade to v3**, required because the phone app won't talk to a v1 server. `sudo cp -a` the database dir to `database-pre-v3-<date>` FIRST — ~11 months of schema migrations is the one genuinely hard-to-reverse write in this project; expect a long first boot that can look stuck on `Reindexing clip_index`; (3) **step 7c** — a fresh upload from the phone (also the first proof the library is *writable* — read is already confirmed, write is not), then enable the daily db dump in server settings
- [ ] **the real deadline, now unblocked: ~11 months of photos still exist ONLY on the phone.** immich being up is not the goal — the photos being on it is. this stays open until the backlog has actually drained onto the 14tb drive
- [ ] set up backups both directions — tool already DECIDED: restic + backrest, 4 repos across the two 14tb drives (see `backup-software-decision.md` for layout). blocked on the immich migration. sequence: init repos by hand from the cli first (that's the goal-1 learning), then backrest for scheduling, then ONE RESTORE DRILL. server→desktop is the load-bearing flow for the photos — needs an explicit answer for "desktop must be on for it to run"
- [ ] reclaim the ssd only after the desktop restic snapshot exists: `docker volume rm` the three immich volumes (~76G back on /home) — gated per runbook step 8, never before. **do NOT use `docker volume prune` or `docker system prune --volumes`** — the immich volumes are "unused" right now, so prune would take all three. explicit `docker volume rm <name>` only

## tooling gaps found aug 2026 (small, none blocking)

- [ ] **`sync-secrets.sh` doesn't carry `.env`** — it rsyncs `server/*/secrets/` only. but `.env` is gitignored too, so `git pull` can't deliver it either, which left the server with no `.env` at all until it was scp'd by hand. teach the script to carry both and a fresh setup won't rediscover this. (safe to do: the `.env` holds no credentials, only paths + TZ + version)
- [ ] **write the compose-era deploy script** — `deploy.sh` is swarm-only and must NOT be run now (it would re-init swarm on a box that has left it). the replacement is roughly three lines: `./server/sync-secrets.sh` then `ssh debian-box "cd box && git pull && cd server/immich && docker compose up -d"`. worth noticing that the new model needs ~3 lines where the old needed ~200
- [x] **server checkout had no git upstream tracking** — fixed 2026-08-16 with `git branch --set-upstream-to=origin/master master`. it had been silently unable to report "your branch is behind" for a year, because `deploy.sh` bootstraps with `git init` + `git pull origin master` rather than `git clone`. if the checkout is ever recreated, re-apply this (or clone instead)
- [ ] `deploy.env` still calls the home server `DROPLET_HOST` — leftover from the digitalocean template this repo was scaffolded from (see commit `73859c7`). purely cosmetic, but it genuinely caused an "is there a droplet?" confusion in aug 2026. renaming touches `deploy.sh`, so only do it if that script survives

## desktop side (july 2026 — see `desktop-state.md` for the full ground truth)

- [ ] **add the fstab entry for the desktop hdd** — the one blocking item, and independent of everything server-side. `UUID=50613f6f-0dd8-4a82-97a3-85a03f95faf9 /mnt/top-d ext4 defaults,nofail 0 2`. today the drive is only ever mounted by udisks2 (file manager) at `/media/sheelah/top-d`, which no scheduled job can rely on — and the alternative path `/mnt/top-d` is a bare directory on a root fs with 8.6G free. both are silent failure modes
- [ ] enumerate what's actually in the `desktop-sheelah-d-2026-02-01` borg archive (195G, contents never checked): `borg info` + `borg list` on it
- [ ] reconcile borg-vs-restic — the april decision doc says restic + backrest; the desktop has a working verified 195G **borg** repo from january and neither restic nor backrest installed. staying on borg is defensible; the real cost is borg's both-ends version coupling across debian 12 (server) / 13 (desktop). decide before building the cross-machine flows, not after
- [ ] `/home` on the desktop is at 98% (1.7T/1.9T, ~42G left) — and there's no LVM on that box, so no `lvextend` escape hatch. the 12.7T hdd is the relief valve
- [ ] record a SMART baseline for the desktop hdd (`smartctl -a /dev/sda`) into `desktop-state.md`

## later, not blocking the storage work

- [ ] pick *one* monitoring gui and actually get it healthy. UPDATE july 2026: neither is even running anymore (`docker ps` is empty — the whole server was idle). when revisiting, deploy the winner as plain compose per the hybrid direction, not as a swarm stack. beszel needs a real `KEY` value in `beszel/docker-compose.yml:37` (currently a placeholder string). (note: ufw doesn't actually gate docker-published ports — see `stack-map.md` layer 8 — so "open ports in ufw" is moot on the LAN)
- [ ] deploy.sh: only matters while anything still runs on swarm — immich leaves it with the migration. if kept for portainer/beszel, the known bugs (this list is the catalogue): secret rotation silently skipped at `deploy.sh:141-152`, `echo` adds trailing newline to secrets, unchanged image tags may not redeploy. if everything ends up on plain compose instead, retire the script rather than fix it

## 3D printer controller

Not started yet.

**Questions:**

- Which software? (OctoPrint, Klipper, etc.)
- How to connect the printer to the server?
- Run as another Docker service or bare metal?
