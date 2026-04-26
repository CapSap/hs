The intent of this file is to store the long term todos that are not actively being worked on. Notes is for active work

- [x] consider backup strategy and decide on filesystem type → decided on ext4 + restic (see notes.md)

**Commands used (not fully understood yet):**

```bash
sudo mount /dev/sdb1 /mnt/hdd/
sudo umount /mnt/hdd
sudo mount -a
```

## april-2026: once again for the first time

- [ ] ssh to the server and run `lsblk`, `blkid`, `df -h`, `findmnt` — just look at what disks are actually installed and what's already mounted. commits to nothing. ground truth before any planning.
- [ ] decide disk layout for the new hdds: filesystem (probably ext4), single pool vs separate-purpose disks, mount points in `/etc/fstab` using UUIDs (not `/dev/sdb1`)
- [ ] finish the immich named-volumes → bind-mounts migration. the compose file at `immich/docker-compose.yml` still uses named volumes (`immich-library`, `immich-database`, `model-cache`). `deploy.sh` already creates `~/immich/library` and `~/immich/postgres` but the compose was never updated to point at them. needs a careful copy of existing data before swapping.
- [ ] plan backups in both directions: desktop → server (server is the backup target for desktop files), and server → desktop (desktop holds a backup copy of the immich library). pick one tool for both — rsync over ssh is the most "learn linux" option, restic/borg give snapshots and dedup. decide later, not blocking the disk work.

## later, not blocking the storage work

- [ ] pick *one* monitoring gui and actually get it healthy. portainer and beszel are both deployed but neither is fully working. beszel needs a real `KEY` value in `beszel/docker-compose.yml:37` (currently a placeholder string). both probably need their ports opened in ufw — `host-setup.sh` only opens ssh + swarm ports.
- [ ] add a `./deploy.sh <servicename>` mode so adding a new service only touches that one stack. ~10 lines. would shrink the "scary to add a service" feeling a lot.
- [ ] note for future-me: `deploy.sh:141-152` silently *skips* updating any secret currently in use by a service. editing an `.env` value will not propagate to a running service. fix or document.

## 3D printer controller

Not started yet.

**Questions:**

- Which software? (OctoPrint, Klipper, etc.)
- How to connect the printer to the server?
- Run as another Docker service or bare metal?
