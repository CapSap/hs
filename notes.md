# Working Notes

## Current status (as of Feb 2026, project stalled)

- Debian installed with LVM (separate /home, /var, /tmp partitions)
- Docker Swarm running with deploy script working
- Immich, Portainer, Beszel, and test-web-server deployed
- New HDD purchased and installed, SMART test passed
- Data copied from Docker volumes to /mnt/hdd

## Storage: Docker volumes vs bind mounts on HDD

The /var partition is only ~7GB and filled up with Docker volumes. Need to move
Immich data (photos + postgres) to the new HDD.

**Options considered:**
- Bind mounts pointing to /mnt/hdd (started but not finished)
- Docker volumes with a changed data-root (daemon.json)

**Decision:** Going with bind mounts. Already copied data over to /mnt/hdd.

**What still needs to happen:**
- Make the HDD mount persistent (add to /etc/fstab)
- Understand and set correct permissions on /mnt/hdd for Docker containers
- Update immich/docker-compose.yml to use bind mounts instead of volumes
- Delete old Docker volume data once bind mounts are confirmed working

**Commands used (not fully understood yet):**
```bash
sudo mount /dev/sdb1 /mnt/hdd/
sudo umount /mnt/hdd
sudo mount -a
```

## Backup strategy

Photos are on Immich but there's no backup of the Immich data itself yet.
Was looking into a separate backup service but didn't decide on one.

**Questions:**
- What backup tool/service to use?
- Where to back up to? (second drive, cloud, offsite?)
- What needs backing up? (photos, postgres DB, config?)

## 3D printer controller

Not started yet.

**Questions:**
- Which software? (OctoPrint, Klipper, etc.)
- How to connect the printer to the server?
- Run as another Docker service or bare metal?
