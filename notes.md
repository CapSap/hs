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
so the smart test has completed, i created the /mnt/hdd dir and did some mounting (and i dont understand fully)
copying over the files is done from docker volume to mounted /mnt/hdd,

next step is deleting existing docker volume data
rewriting the docker-compose file so that i use the bind mounts instead of docker volumes
and is that the only place i need to config bind mounts?
and i also need to sort out permissions for /mnt files

and upon relfection i dont actually understand the commands i ran to get the thing running
sudo mount /dev/sdb1 /mnt/hdd/
sudo umount /mnt/hdd
sudo mount -a

and i dont understand the permission stuff. ive got lots of tabs open to research /mnt and some chats about user group and permissions

11/feb
trying to clear up the permissions and better understand.

# progress summary

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

## Backup strategy

Photos are on Immich but there's no backup of the Immich data itself yet.
Was looking into a separate backup service but didn't decide on one.

**Questions:**

- What backup tool/service to use?
- Where to back up to? (second drive, cloud, offsite?)
- What needs backing up? (photos, postgres DB, config?)

# reconsidering architecture / software choices

so far ive decied to use debian on bare metal, and running docker swarm. and each service will be within a docker container, and one docker service per service

## why docker swarm over docker compose?

chose swarm so secrets are injected at runtime via /run/secrets/ rather than sitting in env vars or on disk. the container process reads them as files.

**questions to help decide if this is worth the complexity:**

- am i planning to add more nodes? if yes, swarm makes more sense long-term
- is the deploy script complexity bothering me? the secret management loop is where most of the friction lives
- would i rather keep the security property and simplify other parts? (e.g. docker compose with an external secret backend could give similar isolation without full swarm)
- who am i protecting the secrets from? on a single-node homeserver on my local network, the threat model is different from a production server. the secrets are already in .env files on my desktop, and if someone has access to the box they can docker inspect the service anyway

## summary of the conversation that produced the april 2026 todo list

came back to this project after a long drift, feeling stretched and uneasy and not sure whether to refactor. talked it through and landed on:

- the drift wasn't laziness or the project being broken. it was hitting a real fork in the road (the disk filled up, new hdds got installed, and now there are real decisions to make about disk layout / bind mounts / backups). that's the project doing its job — i've reached the edge of what i currently know, same as every other thing in this repo was once at that edge.
- the unease about `deploy.sh` is mostly an *observability* problem ("i don't know what's running on the server"), not a deploy problem. the script itself is more conservative than it looks: each service dir is its own `docker stack`, stacks are isolated, and `docker stack deploy` is idempotent + does rolling updates. adding a new service dir literally cannot touch the running ones unless i edit their files in the same commit.
- the *real* blocker is storage, not deploys or monitoring. don't refactor anything right now. the deploy script works. nothing in this repo needs rewriting before the storage decisions are made.
- the storage problem is actually three sub-decisions: (1) disk layout + fstab, (2) finishing the immich named-volumes → bind-mounts migration that's already half-done, (3) bidirectional backups between desktop and server. (3) is not blocking (1) and (2).
- discovered while talking: the immich compose file was never updated when i decided to switch to bind mounts (`deploy.sh` even creates the dirs, but `immich/docker-compose.yml` still declares named volumes). so the migration is sitting in a half-state.
- discovered while talking: portainer and beszel are both deployed-ish but neither is fully working. beszel has a placeholder `KEY` string in its compose. neither has firewall ports opened in `host-setup.sh`. one healthy gui would fix most of the "i don't know what's running" anxiety.
- the smallest possible next step, that commits to nothing: ssh in and run `lsblk`, `blkid`, `df -h`, `findmnt`. ground truth about what's actually installed before planning anything.
- chose swarm originally because it was the *minimum* tool that gave real secrets management without going to k8s. that choice still stands. the goal of this whole project is learning linux + servers, so prefer the simplest path that teaches the fundamentals (ext4 + uuid fstab + bind mounts + rsync) over fancier abstractions (zfs pools, volume drivers, syncthing) unless there's a reason.

# filesystem choice: ext4

going with **ext4** — boring, well-understood, and any Linux live USB can read it. snapshots and dedup will be handled by restic instead, so the filesystem stays simple and we can swap backup tools later without reformatting. full reasoning + comparison with btrfs and zfs: see [backup-software-decision.md](./backup-software-decision.md#filesystem-choice-ext4-vs-btrfs-vs-zfs).

## backup tool: restic + backrest

after a lot of back-and-forth, going with **restic + backrest**. risk model is dominated by user error and hardware failure (not compromise), and both are covered by versioned snapshots across two physical disks. backrest gives a self-hosted web gui that fits the broader "one healthy gui to fix the i-don't-know-what's-running anxiety" goal. borg was a serious consideration — its append-only feature is cleaner than restic's — but it defends against a threat that's not in our top tier.

full reasoning, threat model, architectural framing, and the 4-repo plan: see [backup-software-decision.md](./backup-software-decision.md).
