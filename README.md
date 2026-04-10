# leaving some notes for myself so i remember what i did

## my goals:

- have a home server up and running, and backup photos from my phone
- install that 3d printer contoroller on the server

### Step 1: install OS

currently debating between debian or something else. decided on debian.
notes from installation:
I chose LVM and seperate paritions for /home, /var/ and /tmp
Post install steps were setting up ssh, moving over the host-setup script and running it (this installs docker and some basic firewall stuff)

### Step 2: deploy

on my desktop machine with ssh configured, run the deploy script
this will run commands on server machine (deploy the github repo) and get .env vars from my local machine and then add them to docker via docker secret

### notes

useful link
https://github.com/zilexa/Homeserver

# Some more detailed notes that help document my reasoning at the time

## setting up host machine

1.  install debian on host machine via usb iso. using LVM
    hostname = shelaria-s
    domain name?
    username = shelaria
    user password = ?40
    how to set up the partitions?
    using the gui- seperate /var /home /tmp
    installed ssh and xfce

2.  set up ssh so that i can remote into the machine
    i created a ssh key pair on client side, and copied over the pub key to server
    and reserved an ip address via the router settings, and mac address
    i can now ssh into server via the command ssh debian-box
    and i set something in the .bashrc on the server to change the shell prompt text colour

and i should disable ssh with password now. DONE

3. I've decided to use LVM and try and have most of the data on home. By default docker wants to use /var. It's possible to add a config that will point the docker daemon to use my own dir. Might need to create a symlink (more reading here: https://docs.docker.com/engine/daemon/)
   create /etc/docker/daemon.json
   and add
   {
   "data-root": "/mnt/docker-data"
   }

4. mv over the setup script and run it. this will: install docker and do some firewall setup

5. deploy via script
   the deploy script is finnally working!

6. now what?
   5a. try and get immich actually working
   next bottleneck is that /var has only 7. something gb and its where the docker volumes are stored. need lots of storage there.
   im deciding to use bind mounts

## Troubles with immich- bind mounts or docker volumes?

Before running anything I had to choose between docker volumnes and bind mounts. In the end I chose docker volumnes, and ran into an issue where i had only allocated 7gb to the /var partition and it filled up and things stopped working. I learned that bind mounts and volumes are really not that different and that i think id prefer these volumes to be manged by docker.

# trying to get a backup service up and running

so ive got photos on immich- next step is backing them up

i think ive decided to have some other backup service,

10/feb/26
copying over the files is done,
next step is deleting existing docker volume data
rewriting the docker-compose file so that i use the bind mounts instead of docker volumes
and is that the only place i need to config bind mounts?
and i also need to sort out permissions for /mnt files

and upon relfection i dont actually understand the commands i ran to get the thing running
sudo mount /dev/sdb1 /mnt/hdd/
sudo umount /mnt/hdd
sudo mount -a

and i dont understand the permission stuff. ive got lots of tabs open to research /mnt and some chats about user group and permissions

# april-2026: once again for the first time

- [ ] ssh to the server and run `lsblk`, `blkid`, `df -h`, `findmnt` — just look at what disks are actually installed and what's already mounted. commits to nothing. ground truth before any planning.
- [ ] decide disk layout for the new hdds: filesystem (probably ext4), single pool vs separate-purpose disks, mount points in `/etc/fstab` using UUIDs (not `/dev/sdb1`)
- [ ] finish the immich named-volumes → bind-mounts migration. the compose file at `immich/docker-compose.yml` still uses named volumes (`immich-library`, `immich-database`, `model-cache`). `deploy.sh` already creates `~/immich/library` and `~/immich/postgres` but the compose was never updated to point at them. needs a careful copy of existing data before swapping.
- [ ] plan backups in both directions: desktop → server (server is the backup target for desktop files), and server → desktop (desktop holds a backup copy of the immich library). pick one tool for both — rsync over ssh is the most "learn linux" option, restic/borg give snapshots and dedup. decide later, not blocking the disk work.

## later, not blocking the storage work

- [ ] pick *one* monitoring gui and actually get it healthy. portainer and beszel are both deployed but neither is fully working. beszel needs a real `KEY` value in `beszel/docker-compose.yml:37` (currently a placeholder string). both probably need their ports opened in ufw — `host-setup.sh` only opens ssh + swarm ports.
- [ ] add a `./deploy.sh <servicename>` mode so adding a new service only touches that one stack. ~10 lines. would shrink the "scary to add a service" feeling a lot.
- [ ] note for future-me: `deploy.sh:141-152` silently *skips* updating any secret currently in use by a service. editing an `.env` value will not propagate to a running service. fix or document.
