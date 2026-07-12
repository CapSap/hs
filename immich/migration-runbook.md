# immich migration runbook: swarm + named volumes → plain compose + bind mounts

state as of july 2026 (verified by hand on the server):

- nothing is running (`docker ps` empty). immich has been down since ~feb. data is frozen — no risk of writes during this migration.
- docker data-root is `/home/docker-data/docker`; the original data is in named volumes there (76G)
- a copy already exists at `/mnt/hdd/immich/{library 75G, model-cache 766M, database 339M}`, made ~feb 10
- `/mnt/hdd` is the 14tb drive, ext4, mounted by UUID in fstab (already correct)
- credential values live in `immich/.env` on the LOCAL machine (gitignored). postgres was initialized with these — the secret files created in step 4 MUST contain the same values.

rollback safety: the named volumes are not touched until the very last step. at any point before step 8, rollback = stop compose, redeploy the old swarm stack from git history.

**photo-safety model — read this first:**

- there are currently TWO full copies on TWO different disks: the named volumes (ssd) and `/mnt/hdd/immich` (hdd). this migration only ever writes to the hdd copy; the ssd copy stays pristine.
- every command before step 8 is a read, a copy, or a same-disk rename. nothing deletes. the ONLY photo-destroying command in this runbook is `docker volume rm` in step 8.
- `docker stack rm` does NOT remove volumes — stacks own services/networks, not volumes.
- every rsync here runs WITHOUT `--delete` (it only adds/updates files, never removes any) and gets a `--dry-run` first.
- step 8 is gated on the first restic snapshot existing on the desktop — not just on "immich seems to work".

---

## step 0 — freshness check (read-only)

**RESULT (verified 2026-07-12): library twin confirmed.** rsync dry-run volume→hdd: 0 files to transfer, 26,875 files / ~80G identical on both sides, newest content 2025-09-08 on both. immich stopped writing sep 2025 (when /home filled); the feb 2026 copy is complete. → skip step 2 for library; still run the quick dry-runs for database and model-cache below before trusting them.

is the feb copy as new as the volumes?

```bash
docker volume ls                                   # note exact volume names (likely immich_immich-library etc.)
sudo find /home/docker-data/docker/volumes -type f -printf '%TF %p\n' 2>/dev/null | sort | tail -3
sudo find /mnt/hdd/immich -type f -printf '%TF %p\n' | sort | tail -3
```

- newest files in both ≈ same date → copy is current, skip step 2
- volumes have newer files → do step 2

same twin-check for the two small ones (seconds each):

```bash
sudo rsync -aHAXn --stats /home/docker-data/docker/volumes/immich_immich-database/_data/ /mnt/hdd/immich/database/
sudo rsync -aHAXn --stats /home/docker-data/docker/volumes/immich_model-cache/_data/ /mnt/hdd/immich/model-cache/
```

(want "regular files transferred: 0" on both. the database copy is consistent because postgres has been stopped since long before the copy was made — this is a cold copy, not the dreaded live-db copy.)

also check swarm leftovers:

```bash
docker stack ls && docker service ls
```

## step 1 — remove the old stack definition (if any)

```bash
docker stack rm immich   # only if `docker stack ls` shows it
```

leave swarm itself, other stacks, and swarm secrets alone — they're cleaned up in step 8.

## step 2 — re-sync the diff (only if volumes are newer)

rsync only copies what changed, so this is cheap. use the volume names from step 0.

direction check before anything: source = the volume (`/home/docker-data/...`), destination = the hdd (`/mnt/hdd/...`). newer data flows onto the older copy.

dry-run FIRST — `-n` prints what would be transferred without writing a byte. read the list; it should be only recent files:

```bash
sudo rsync -aHAXn --info=progress2 /home/docker-data/docker/volumes/<library-volume>/_data/ /mnt/hdd/immich/library/
```

if the dry-run output looks right, re-run each without the `n`:

```bash
sudo rsync -aHAX --info=progress2 /home/docker-data/docker/volumes/<library-volume>/_data/ /mnt/hdd/immich/library/
sudo rsync -aHAX --info=progress2 /home/docker-data/docker/volumes/<database-volume>/_data/ /mnt/hdd/immich/database/
sudo rsync -aHAX --info=progress2 /home/docker-data/docker/volumes/<model-cache-volume>/_data/ /mnt/hdd/immich/model-cache/
```

(trailing slashes matter: `src/` `dst/` = merge contents. `-a` preserves ownership/perms — postgres is picky about this. no `--delete` anywhere: these rsyncs can only add/update files on the destination, never remove.)

## step 3 — move to the planned layout

same filesystem, so this is instant:

```bash
sudo mkdir -p /mnt/hdd/services
sudo mv /mnt/hdd/immich /mnt/hdd/services/immich
```

sanity: `ls /mnt/hdd/services/immich` → `database  library  model-cache`

## step 4 — secret files on the server

in the server's checkout of this repo, `immich/` dir (values from local `immich/.env` — DB_PASSWORD, DB_USERNAME, DB_DATABASE_NAME):

```bash
mkdir -p secrets && chmod 700 secrets
printf '%s' 'THE_DB_PASSWORD'  > secrets/immich_db_password
printf '%s' 'postgres'         > secrets/immich_db_username
printf '%s' 'immich'           > secrets/immich_db_database_name
chmod 600 secrets/*
```

notes:
- `printf '%s'` not `echo` — no trailing newline (the deploy.sh bug, not repeated)
- the leading space trick doesn't apply here since these are files, but don't paste the password into a bare `echo` either; `secrets/` is gitignored
- also create/update the server's `immich/.env` to match the local one (it's gitignored, so git pull won't bring it): UPLOAD_LOCATION, DB_DATA_LOCATION, MODEL_CACHE_LOCATION, TZ, IMMICH_VERSION

## step 5 — get the new compose file onto the server

git pull the branch containing the converted `immich/docker-compose.yml` into the server's checkout (or scp the file over).

## step 6 — preflight checks

```bash
cd ~/path/to/repo/immich
docker compose config          # renders the file; catches bad paths/env before anything runs

# guard against booting onto an empty/wrong path (wouldn't delete anything,
# but would start a fresh empty immich and a fresh postgres cluster):
test -f /mnt/hdd/services/immich/database/PG_VERSION && echo "db data present" || echo "STOP: no postgres data at that path"
sudo du -sh /mnt/hdd/services/immich/library   # expect ~75G, not zero

ls -ln /mnt/hdd/services/immich/database | head -3   # note numeric uid — should match what the volume had (rsync -a preserved it)
```

version-jump check: immich moved ~5 months of releases while down. skim the breaking-changes notes at https://github.com/immich-app/immich/releases before `up`. the postgres image (vectorchord) is already the current generation, which removes the worst historical migration. consider pinning `IMMICH_VERSION` in `.env` to the current release instead of `release` so future upgrades are deliberate.

## step 7 — up, watch, verify

```bash
docker compose up -d
docker compose logs -f immich-server   # expect db migration output on first boot; let it finish
```

verify like a user, not like an admin:
- open http://server:2283 — log in, timeline shows the old photos
- upload one new photo from the phone app — appears in timeline
- check server settings → the built-in DAILY DATABASE DUMP is enabled (dumps land in `library/backups/`) — this is what restic will back up; the live `database/` dir never gets backed up directly

## step 8 — reclaim (ONLY after the first restic snapshot of the library exists on the desktop)

hard precondition, not a vibe: until a restic snapshot of the photos lives on the desktop's drive, the ssd volumes are your only second-disk copy. deleting them early drops the photos to a single copy on a single disk. verify with `restic snapshots` on the desktop repo first.

```bash
docker volume rm <the three immich volumes>   # the 76G on /home comes back
docker system prune                            # dangling images etc. — read the prompt before confirming
docker secret rm immich_tz immich_db_password immich_db_username immich_db_database_name   # old swarm secrets
```

do NOT run `docker volume prune` or `docker system prune --volumes` — explicit `volume rm` of the three named volumes only.

## done means

- photos load, uploads work, `docker compose down && up -d` loses nothing
- ssd `/home` back to ~7G used
- next phase begins: restic repos (`/mnt/hdd/restic/{server-local,desktop-remote}`), by hand first, then backrest
