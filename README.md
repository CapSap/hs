# Homeserver

A Debian home server running Docker Swarm, managed via a deploy script.

## Goals

- Back up phone photos (via Immich)
- Backup immich and desktop
- Install a 3D printer controller
- Learn Linux server administration along the way
- Learning ground for a production microservice — need a robust setup for deploying to a remote VM and safely managing secrets

## Services

- **Immich** — photo management and backup
- **Portainer** — container management UI
- **Beszel** — server monitoring dashboard
- **test-web-server** — Node.js app (norm-tribute)

## How it works

1. **Host setup** — Run `host-setup.sh` on the server to install Docker, configure the firewall, and initialize Swarm
2. **Deploy** — Run `deploy.sh` from a desktop machine. It SSHes into the server, pulls the repo, creates Docker secrets from local `.env` files, builds any Dockerfiles, and deploys each service as a Swarm stack

## Server details

- **OS:** Debian, LVM with separate /home, /var, /tmp partitions
- **Docker data root:** `/mnt/docker-data` (configured via `/etc/docker/daemon.json`)
- **Storage:** HDD mounted at `/mnt/hdd` for Immich data (migration in progress)

## Further reading

- [Working notes and decisions](notes.md)
- [Homeserver reference repo](https://github.com/zilexa/Homeserver)

