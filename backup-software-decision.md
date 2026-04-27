# backup software decision (april 2026)

## tl;dr

going with **restic + backrest** for backups.

key reasons:
- top risks for this homelab are **user error** and **hardware failure**, not compromise — both tools cover those equally
- backrest gives a self-hosted web gui that fits the broader goal of "one healthy gui to fix the i-don't-know-what's-running anxiety"
- restic only needs to be installed on the source side; destination is just sshd. simpler version management, no lockstep upgrades
- if priorities shift later (compromise becomes a real concern), restic can match borg's append-only via rest-server — that path is open

borg was a serious consideration. its append-only ssh-key feature is genuinely cleaner than restic's. but the threat that feature defends against (compromised source machine destroying its own backups) is not on the top-risks list, and the gui story for borg is weaker (vorta is desktop-only, borgmatic is config-driven cli — no self-hosted web ui).

---

## the architectural framing (one sentence)

**restic treats the destination as a dumb file store. borg treats the destination as a peer that runs its own process.** every other difference falls out of that.

| because... | restic | borg |
|---|---|---|
| ...destination is dumb | only needs sshd | needs borg installed |
| ...source does all the work | no version coupling | versions must match on both sides |
| ...can't enforce rules at destination | append-only needs rest-server | append-only is built in |
| ...no server-side process to coordinate | repos handle multiple writers | repos lock to one writer at a time |

**analogy that helped it click:**
- **restic = dropbox model.** smart client on your machine, dumb storage on the server side. dropbox's servers don't know what your files mean.
- **borg = git+ssh model.** when you `git push`, ssh runs `git-receive-pack` on the remote — a real git process that validates the push and can refuse it. both ends are smart.

**day-to-day they're identical:** the scheduler runs on each source machine and pushes its own data outbound. differences only show up at install time, upgrade time, and security setup.

---

## how the bytes actually move (push model + wire-level)

both tools are **push-based**. the source machine — the one that has the data — initiates the connection and sends bytes outward. neither has a clean "pull from a remote source" mode.

- the schedule lives on each source machine (backrest plan, cron, systemd timer)
- you can manually trigger from the other side via ssh, but the backup process itself always runs on the machine that owns the data
- desktop pushes desktop's data outward; server pushes server's data outward. symmetric.

**what differs at wire level:**

- **restic over sftp** — server side is *dumb storage*. sshd writes files. no restic process on the server. desktop's restic does all chunking, hashing, encryption, and pushes chunk files up via sftp.
- **borg over ssh** — server side runs `borg serve` (invoked by ssh). two borg processes communicate over the ssh pipe, both doing real work. server-side borg manages the repo writes and can enforce policies — this is what makes append-only possible.

since neither tool listens on a port (ssh handles the connection in both cases), neither is exposed to the internet by default. standard ssh hardening is what keeps backups LAN-only — containerizing the backup process doesn't add meaningful protection here.

---

## the threat model that drove the decision

biggest risks for this homelab, in priority order:

1. **user error** — fat-fingered `rm`, accidental delete, misconfigured something
2. **hardware failure** — drive dies, bit rot, machine dies
3. (much lower) **compromise / ransomware** — desktop gets owned, attacker tries to wipe backups

mitigations already in the plan:
- **versioned snapshots** (both tools) cover user error
- **two physical copies on two different disks** (the 4-repo plan) cover hardware failure
- **append-only** would cover compromise — but compromise isn't a top risk

### what append-only actually defends against

if desktop is compromised, attacker uses desktop's ssh key to reach the server and runs `borg delete` (or `restic forget --prune`). without append-only that wipes the server-side backup of desktop. with append-only, the server-side process refuses delete operations — attacker can only add to the repo.

borg gets append-only from one line in `authorized_keys`:
```
command="borg serve --append-only --restrict-to-path /path/to/repo" ssh-ed25519 AAAA...
```

restic gets the equivalent by running rest-server (a separate go daemon) with `--append-only`. that's real infrastructure: install, systemd unit, port, htpasswd, possibly nginx for tls.

### why is the cost so different? (architecture asserting itself)

borg's append-only is "free" because borg's wire-level design always has a server-side process to enforce policy. restic's design deliberately has no server-side process, so to add policy you have to add a process. **this is the design choice asserting itself, not an oversight.**

verdict: **append-only would be doing real work in a more security-conscious threat model, but it's not load-bearing for "user error + hardware failure as top risks."** if priorities shift later, rest-server is the documented path.

### what append-only does *not* protect against

worth being honest about the limits:
- attacker who compromises the destination directly (root on destination can do anything)
- physical theft / fire / flood (offsite copies are the answer there)
- you running `rm -rf` as root locally (append-only is a remote restriction)
- silent corruption / disk death (that's what redundancy is for)

---

## borg-specific notes (if we ever switch)

the 4-repo topology stays identical — but the split becomes **mandatory** instead of optional, because borg has a hard per-repo lock (single writer at a time). restic supports concurrent writers and could combine repos in principle; borg can't.

- **append-only maps cleanly onto the cross-machine repos.** each machine's ssh key on the other gets `--append-only` access scoped to just the repo it writes to. local repos don't need it.
- **version coupling applies to both cross-machine flows.** desktop's borg and server's borg must be version-matched. `apt upgrade` on both boxes in lockstep.
- **borg 2.0 (april 2026):** still in beta after years, with breaking repo format changes. debian stable ships 1.x. starting on borg today buys a "migrate someday" task. restic has no equivalent looming transition.

---

## detailed feature comparison

| | restic | borg |
|---|---|---|
| install location | source only (destination just needs sshd) | both ends, version-matched |
| backends | sftp, s3, b2, azure, gcs, rclone, rest-server | local + ssh, rclone as escape hatch for cloud |
| concurrency | multi-writer per repo natively | single-writer per repo (hard lock) |
| append-only | via rest-server (extra daemon) | one ssh-key flag |
| performance | parallelizes aggressively | borg 2 improved chunker parallelism |
| maturity | stable, widely used | older, in debian stable |
| mounting snapshots | `restic mount` (fuse) | `borg mount` (fuse) |
| language | go static binary | python (apt-installable on debian) |
| self-hosted web gui | backrest | none comparable (vorta is desktop, borgmatic is cli) |
| repo format stability | conservative, no looming transition | borg 2.0 in beta, format migration coming |

**not the deciding factor either way:** dedup ratio, encryption strength, restore speed. both are good enough that the difference is in the ergonomics, not the bytes on disk.

---

## filesystem choice: ext4 vs btrfs vs zfs

**decision: ext4.** keep the filesystem and backup tool separate.

reasons:
- ext4 is well-understood, any Linux live USB can read it, easy to recover
- can swap backup tools later without reformatting
- btrfs/zfs have copy-on-write gotchas with postgres and Docker's storage driver (need specific tuning to avoid fragmentation/performance issues)
- restic handles snapshots, deduplication, and network transfer from the outside — the filesystem stays simple
- restic uses independent "repositories" — easy to back up to multiple locations (local repo on same disk + remote repo on the other machine). each repo is self-contained and location-agnostic (local disk, ssh, sftp, s3, etc.)

### the setup driving the decision

**the machines:**
- **server** — Debian, SSD (small, OS only), HDD (data)
- **desktop** — working ssd drive, separate HDD for backups/archival

**the data:**
- **server:** Immich photos/videos + postgres DB + service configs + other services
- **desktop:** personal files (whatever you want protected)

**immich-specific requirements:**
- database dump first, then filesystem (ordering matters)
- immich auto-dumps the DB daily into the upload location
- need to back up `library/`, `upload/`, `profile/`, and the DB dumps

### options considered

**option A: ext4 + restic** ← chosen
- format both HDDs as ext4, simple fstab mount
- use restic to take snapshots and transfer between machines over the network
- two separate things to learn, but each is simple on its own
- filesystem is boring and reliable, backup tool handles the clever stuff
- browsing snapshots: `restic snapshots` lists all versions, `restic ls` shows files in a snapshot, `restic mount` lets you browse any snapshot as a regular folder via FUSE. easy to find and restore individual files

**option B: btrfs + btrfs send/receive**
- format both HDDs as btrfs
- snapshots and checksumming built into the filesystem
- `btrfs send/receive` to replicate snapshots between machines over the network
- one thing to learn but it's a bigger thing
- in the mainline kernel, no DKMS issues on Debian
- checksumming catches silent corruption — nice for long-term photo storage
- browsing snapshots: each snapshot is a regular directory you can `cd` into and `ls`. no special tools needed — it's just a folder. very intuitive but you need to manage naming/cleanup yourself

**option C: zfs + zfs send/receive**
- same idea as btrfs but more mature, more battle-tested
- not in the Linux kernel — needs DKMS module, can break on kernel upgrades
- wants more RAM
- more concepts (pools, vdevs, datasets)
- browsing snapshots: `zfs list -t snapshot` to list them, then access via a hidden `.zfs/snapshot/` directory inside the dataset mount point. also just regular folders you can browse

---

## the concrete plan: 4 repos across 2 disks

**hardware:**
- **desktop:** working ssd (primary), spare hdd (backup target only)
- **server:** small ssd (os only), hdd (live immich storage *and* backup target)

**four restic repos, four flows:**

| flow | source | destination | protects against |
|---|---|---|---|
| desktop → server hdd | desktop ssd | server hdd | desktop drive failure |
| server → desktop hdd | server hdd | desktop hdd | server drive failure |
| desktop → desktop hdd (local) | desktop ssd | desktop hdd | accidental delete, fast restore |
| server → server hdd (local) | server hdd | server hdd | accidental delete |

**the subtlety to be clear-eyed about:** the server's "local" repo lives on the same physical disk as live immich data. that's accidental-delete protection only — **not drive-failure protection**. drive-failure protection for server data comes from the copy on the desktop hdd. which means **the desktop-side cross-backup is the load-bearing flow for server data** and needs a schedule that actually runs.

restic dedup keeps the math sane — the server hdd holds live immich + snapshot history + a copy of desktop data, but unique-chunks-only means history is cheap.

**planned repo layout (decide up front, hard to rename later):**

```
desktop hdd:  /mnt/backup/restic/desktop-local/
              /mnt/backup/restic/server-remote/

server hdd:   /mnt/hdd/services/immich/...        (live)
              /mnt/hdd/restic/server-local/
              /mnt/hdd/restic/desktop-remote/
```

four repos total, two per disk. each repo is fully independent — lean into that.

**what this setup doesn't cover:** both disks are in the same house. fire/flood/theft loses everything. not solving this now, but restic makes "add an offsite target later" a config change, not a redesign — b2, rclone to cloud, or a friend's server all work.

---

## when to revisit this decision

triggers that should make future-me reopen this:
- compromise becomes a real concern (e.g. exposing services to the internet, or after a security incident)
- backrest turns out to be flaky or abandoned
- need an offsite-only target with strong append-only guarantees — cloud object lock (S3 / B2) is the answer there, still in restic-land, no need to switch tools
- if borg 2.0 ships stable and we want append-only enough to switch, the move would be borg + borgmatic
