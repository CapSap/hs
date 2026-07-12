The intent of this file is to store the long term todos that are not actively being worked on. Notes is for active work

- [x] consider backup strategy and decide on filesystem type → decided on ext4 + restic (see notes.md)

**Commands used (not fully understood yet):**

```bash
sudo mount /dev/sdb1 /mnt/hdd/
sudo umount /mnt/hdd
sudo mount -a
```

## april-2026: once again for the first time

- [x] ssh to the server and run `lsblk`, `blkid`, `df -h`, `findmnt` — done july 2026. findings: 14tb (sdb1) already ext4 + mounted at /mnt/hdd with 76G on it; **/home is 100% full (83G/85G)**; ~119G looks unallocated in the LVM volume group; still to verify: fstab entry by UUID for sdb1
- [x] decide disk layout for the new hdds — discovered already done (july 2026): sdb1 is ext4, mounted at /mnt/hdd via UUID in fstab. correct as-is. root cause of full /home found: docker data-root is `/home/docker-data/docker` (83G) — immich volumes live on the small ssd, not the 14tb drive. fix = the planned bind-mount migration, now urgent
- [ ] finish the immich named-volumes → bind-mounts migration. UPDATE july 2026: the data copy already exists — `/mnt/hdd/immich/{library 75G, model-cache 766M, database 339M}`, made ~feb 10. NOTHING is currently running (`docker ps` empty — immich has been down for months, no photo backups happening). docker data-root is `/home/docker-data/docker`; volumes (76G) still hold the original. remaining work: (1) confirm /mnt/hdd copy is as new as the volumes (find -printf newest-file check), (2) re-rsync the diff if not, (3) write plain-compose file with bind mounts + file secrets, (4) up, verify photos, (5) only then reclaim the 83G on /home
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
