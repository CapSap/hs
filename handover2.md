# handover 2 — ground truth established, immich migration in flight (july 2026)

successor to `handover.md` (the july strategy review). that doc captured the *decisions*; this one captures the *verified state of the actual server* and exactly where the work sits. written to be picked up cold.

## tl;dr

- direction unchanged: hybrid, immich → plain compose + bind mounts, restic + backrest after. see `stack-map.md` for the layer map and the anti-overwhelm decision protocol
- we ssh'd in and established ground truth. several assumptions were stale — in a good way. **the migration is ~90% done already**; february-you completed the data copy and never flipped the switch
- **immich has been down since ~sep 2025** (photos stopped arriving 2025-09-08 — almost certainly when `/home` hit 100%). that means ~10 months of phone photos exist ONLY on the phone. **getting immich accepting uploads again is the real deadline in this project**
- the converted compose file and a step-by-step runbook now exist: `immich/docker-compose.yml`, `immich/migration-runbook.md`. next session starts at "remaining steps" below

## verified facts about the server (not assumptions — all checked by hand, july 11–12)

- **disks:** 238.5G ssd (os, LVM) + 12.7T hdd (`/dev/sdb1`, ext4, mounted at `/mnt/hdd` **by UUID in fstab already** — that todo item was already done)
- **lvm:** volume group had ~119G unallocated. `/home` was 100% full (83G/85G) — extended live with `sudo lvextend -r -L +30G shelaria-s-vg/home` → now 116G. first write operation of the project, zero downtime
- **docker data-root is `/home/docker-data/docker`** (not /var/lib/docker). that's why filling volumes killed /home: immich's named volumes (76G) live on the small ssd
- **nothing is running.** `docker ps` is empty — no immich, no portainer, no beszel. the server has been idle for months
- **two identical copies of the photos exist on two different disks — proven, not assumed:**
  - named volumes on ssd: `immich_immich-library` etc.
  - `/mnt/hdd/immich/{library 75G, database 339M, model-cache 766M}` — a copy made ~feb 10 2026
  - rsync dry-run volume→hdd: **0 files to transfer**, 26,875 files / ~80G identical, newest content 2025-09-08 on both sides
- the database copy is a **cold copy** (postgres had been stopped for months when it was made) — consistent, safe to boot from
- credentials: `immich/.env` on the LOCAL machine (gitignored) holds the db password/user/dbname that postgres was initialized with. the new secret files MUST use these same values

## artifacts created this session

| file | what it is |
|---|---|
| `stack-map.md` | the stack in 9 layers, each marked decided/open/deferred with revisit triggers, + the 3-question protocol for shiny new things (which layer? decided? on critical path?) |
| `immich/docker-compose.yml` | converted: plain compose, bind mounts via `.env` paths (upstream-immich-shaped), file-based secrets keeping the `*_FILE` discipline, `DB_STORAGE_TYPE: HDD` |
| `immich/migration-runbook.md` | the full migration procedure with photo-safety model, dry-run-first rsyncs, preflight guards, rollback story |
| `immich/.env` | paths updated to `/mnt/hdd/services/immich/...` (gitignored — server needs its own copy) |
| `.gitignore` | now also ignores `secrets/` |

## the photo-safety model (from the runbook, worth repeating)

- migration only writes to the hdd copy; the ssd volumes stay pristine as rollback
- every command before the final reclaim step is a read, copy, or same-disk rename. the ONLY photo-destroying command in the runbook is `docker volume rm`, and it is **gated on the first restic snapshot of the library existing on the desktop** — until then the ssd volumes are the second-disk copy
- rsyncs: no `--delete` anywhere, `--dry-run` first, always volume→hdd direction

## remaining steps (start here next session — details in `immich/migration-runbook.md`)

1. ~~freshness check~~ ✔ done for library (twin confirmed). still to run: the two quick dry-run twin-checks for `immich_immich-database` and `immich_model-cache` (commands in runbook step 0)
2. `docker stack ls && docker service ls` → `docker stack rm immich` if the old stack definition survives
3. `sudo mkdir -p /mnt/hdd/services && sudo mv /mnt/hdd/immich /mnt/hdd/services/immich` (instant, same fs)
4. on the server, in the repo's `immich/` dir: create `secrets/` files (`printf '%s'`, chmod 600, values from local `.env`) and the server-side `.env`
5. `git pull` the branch on the server to get the new compose file (committed as of this handover)
6. preflight: `docker compose config`, PG_VERSION check, library non-empty check; skim immich release notes for breaking changes since ~sep 2025 (db will migrate ~10 months of versions on first boot — watch the logs, let it finish)
7. `docker compose up -d` → verify like a user: old photos in timeline, one fresh upload works, daily database dump enabled in settings
8. let the phone drain its backlog onto the 12T drive
9. THEN the backup phase: restic repos at `/mnt/hdd/restic/{server-local,desktop-remote}` by hand, then backrest, then the restore drill. reclaim the ssd volumes only after the desktop restic snapshot exists

## things learned that are worth keeping (the goal-1 ledger)

- `lsblk` / `blkid` (lives in /usr/sbin — needs sudo) / `df -h` / `findmnt` as the ground-truth quartet
- lvm: `vgs`/`lvs` to see free extents; `lvextend -r` resizes lv + filesystem online, under a running system
- fstab by UUID vs device path; `/dev/mapper/*` names are stable for lvm
- rsync: trailing slashes, `-a` preserves ownership (postgres cares), `-n --stats` as a free integrity/diff check between two trees, no `--delete` = can only add
- docker: data-root location determines which disk named volumes fill; `docker stack rm` does not remove volumes; volume names get stack-prefixed (`immich_immich-library`)
- the meta-lesson: months of unease dissolved by ~10 read-only commands. the system on disk is the real one; docs and memories drift. ground truth first, always
