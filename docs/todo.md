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
- [ ] finish the immich migration — **follow `immich/migration-runbook.md`, start at step 0's remaining checks.** done so far (july 2026): compose file converted to plain compose + bind mounts + file secrets; library twin-check PROVEN (rsync dry-run volume→hdd: 0 files to transfer, 26,875 files / ~80G identical on both disks, both ending 2025-09-08); /home extended +30G via lvextend. remaining: dry-run twin-checks for the database + model-cache volumes → `docker stack rm immich` if still defined → mv `/mnt/hdd/immich` → `/mnt/hdd/services/immich` → create `secrets/` files + `.env` on the server → git pull → preflight (`docker compose config`, PG_VERSION check) → `up -d`, watch ~10 months of db migrations → verify photos load + a fresh upload works + daily db dump enabled
- [ ] **the real deadline: immich has been down since ~sep 2025 — ~10 months of photos exist ONLY on the phone.** once immich is up, let the phone app drain its backlog onto the 14tb drive
- [ ] set up backups both directions — tool already DECIDED: restic + backrest, 4 repos across the two 14tb drives (see `backup-software-decision.md` for layout). blocked on the immich migration. sequence: init repos by hand from the cli first (that's the goal-1 learning), then backrest for scheduling, then ONE RESTORE DRILL. server→desktop is the load-bearing flow for the photos — needs an explicit answer for "desktop must be on for it to run"
- [ ] reclaim the ssd only after the desktop restic snapshot exists: `docker volume rm` the three immich volumes (~76G back on /home) — gated per runbook step 8, never before

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
