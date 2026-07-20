# SALVAGE worksheet — empty me, then delete me

**Temporary.** This is raw material rescued verbatim from `handover.md` and `handover2.md` before they get deleted. Nothing here is polished prose — it's *your original words*, quoted, so you can rewrite each piece into its home doc in your own voice and stay the author.

**How to use:** work through the checkboxes. For each one, write the content into the suggested home (in your words), then tick it. When every box is ticked, tell me "salvage done" and I'll (a) delete `handover.md` + `handover2.md` and (b) rewrite the 6 references listed at the bottom so nothing dangles. Then delete this file.

Ordered most-important first. The last two are optional/low-value.

---

## MUST-KEEP

### [ ] 1. Full `deploy.sh` bug table (6 rows)
- **from:** handover.md §1 "issues found in deploy.sh"
- **home:** `todo.md` — expand the existing deploy.sh item (it currently has only rows 1–3)
- **ref that points here:** `stack-map.md:80`, `todo.md:27`

```
| issue | where | detail |
|---|---|---|
| rotation doesn't converge | `deploy.sh:141-152` | secrets in use are silently skipped — editing a local `.env` value does nothing for a running service. this is WHY the manual ssh/stop/rm/redeploy rotation script had to exist. (already noted in `todo.md`) |
| trailing newline in secrets | `deploy.sh:151` | `echo "$value"` appends `\n`. postgres strips it; a node app reading the file gets `"...token\n"` → silent auth failures. fix: `printf '%s'` |
| rebuilds may not redeploy | `deploy.sh:171` | building `dir:latest` + `docker stack deploy` with an unchanged tag often doesn't roll the service — new code builds but doesn't ship. fix: tag with git sha |
| dead error branches | e.g. `deploy.sh:154,190` | `set -e` exits before any `if [[ $? -eq 0 ]] ... else` branch can run; `$?` after an `if` is the if's status anyway |
| local/remote dir coupling | `deploy.sh:93,101` | service list comes from `find` on the REMOTE checkout, but the subshell `cd`s into the LOCAL dir of the same name. a remote-only dir kills the whole deploy under `set -e` |
| dead code | `deploy.sh:204` | `mkdir -p ~/immich/{library,postgres}` predates the switch to named volumes |
```

### [ ] 2. "push to master = root on the server" gotcha (exists nowhere else)
- **from:** handover.md §gotchas
- **home:** your call — a security note in `README.md`, or `stack-map.md` layer 8, or `todo.md`
- **ref that points here:** none (it would just vanish)

```
- **push access to master = root on the server.** deploy is "git pull whatever's on master, run it with docker socket access." acceptable for a personal repo; be conscious of it. portainer/beszel socket mounts are full-trust components for the same reason
```

### [ ] 3. UFW gotcha — the specifics (bare fact is elsewhere; the ports + mechanism only here)
- **from:** handover.md §gotchas
- **home:** `stack-map.md` layer 8 (expand the existing one-line "fix the ufw illusion" note)
- **ref that points here:** `todo.md:26`, `stack-map.md:107`

```
- **UFW is not protecting published ports.** docker/swarm iptables rules bypass ufw — 2283, 9443, 9000, 8090 etc. are reachable regardless of the careful `ufw allow` list in `host-setup.sh`. fine on a home LAN, but if exposure ever matters the answer is the `DOCKER-USER` chain (or a proxy-only port surface), not ufw rules
```

### [ ] 4. Deployment-strategy alternatives survey (6 options + recommendation)
- **from:** handover.md §2. Option 6 and the "1 + 3 + light 4" recommendation exist nowhere else; options 3/4/5 are placed individually in stack-map but never as a survey.
- **home:** `swarm-vs-compose-decision.md` — as an appendix (that doc's opening line already advertises "the full alternatives survey" and points here)
- **ref that points here:** `swarm-vs-compose-decision.md:3`

```
1. **plain compose + systemd timers** — the boring default; most faithful mimicry of what small businesses actually run on a single vps. compose supports file-based `secrets:` WITHOUT swarm (bind-mounted, not tmpfs; `*_FILE` pattern carries over unchanged)
2. **swarm (current)** — already paid the learning cost, but weakest on the mimicry argument: single-node swarm is niche in real production. what transfers is the discipline (file secrets, declarative stacks, scripted deploy), not the swarm api itself
3. **compose + SOPS/age** — encrypt `.env` files, commit them; repo becomes single source of truth, rotation = git commit, dr = clone + one age key. fixes the "local .env is invisible state" problem
4. **ansible (or bash made idempotent)** — `host-setup.sh`/`deploy.sh` are hand-rolled non-idempotent ansible; idempotent config mgmt is a bigger real-world skill than any orchestrator
5. **k3s** — best employability, `CronJob` maps perfectly to the csv workload, but severe complexity tax. **ruled out**
6. **no containers (systemd-native)** — for the actual business workload arguably correct (systemd timer + `LoadCredential=` + openssh `internal-sftp` chroot), but least reusable for the homeserver

recommendation for the business-mimicry goal (now background): 1 + 3 + light 4.
```

### [ ] 5. The goal-1 learning ledger (whole section — lvm/fstab bullets + meta-lesson are unique)
- **from:** handover2.md "things learned that are worth keeping (the goal-1 ledger)"
- **home:** your goal-1 learning record — `notes.md` if you keep it as a journal/ledger, otherwise `todo.md` beside the existing goal-1 note
- **ref that points here:** `todo.md:13`

```
- `lsblk` / `blkid` (lives in /usr/sbin — needs sudo) / `df -h` / `findmnt` as the ground-truth quartet
- lvm: `vgs`/`lvs` to see free extents; `lvextend -r` resizes lv + filesystem online, under a running system
- fstab by UUID vs device path; `/dev/mapper/*` names are stable for lvm
- rsync: trailing slashes, `-a` preserves ownership (postgres cares), `-n --stats` as a free integrity/diff check between two trees, no `--delete` = can only add
- docker: data-root location determines which disk named volumes fill; `docker stack rm` does not remove volumes; volume names get stack-prefixed (`immich_immich-library`)
- the meta-lesson: months of unease dissolved by ~10 read-only commands. the system on disk is the real one; docs and memories drift. ground truth first, always
```

### [ ] 6. Hardware / LVM ground-truth facts (exact sizes, VG name, the lvextend command)
- **from:** handover2.md "verified facts about the server"
- **home:** `README.md` "Server details" (note: the data-root value is already corrected there)
- **ref that points here:** none

```
- **disks:** 238.5G ssd (os, LVM) + 12.7T hdd (`/dev/sdb1`, ext4, mounted at `/mnt/hdd` by UUID in fstab already)
- **lvm:** volume group had ~119G unallocated. `/home` was 100% full (83G/85G) — extended live with `sudo lvextend -r -L +30G shelaria-s-vg/home` → now 116G. first write operation of the project, zero downtime
- **docker data-root is `/home/docker-data/docker`** (not /var/lib/docker). that's why filling volumes killed /home: immich's named volumes (76G) live on the small ssd
```

---

## OPTIONAL (low value — keep only if you want)

### [ ] 7. Secret-rotation fix (only relevant if any service stays on swarm)
- **from:** handover.md §1 "the rotation fix (if staying on swarm anywhere)"
- **home:** `todo.md` deploy.sh item, or drop entirely if everything moves to compose

```
versioned secret names: `immich_db_password_v2` (or suffix with a content hash), reference the new name in compose, `docker stack deploy` → rolling update onto the new secret. no stop, no rm, no downtime. old versions gc'd whenever. this alone eliminates the manual rotation script.
```

### [ ] 8. Verified security fact (nice to have on record)
- **from:** handover.md §1 "what's genuinely good"
- **home:** wherever the "push = root" security note lands (item 2)

```
no `.env` files or logs ever committed to git (verified full history)
```

---

## References I will rewrite at deletion time (do NOT need your attention)

Once you've placed the content above and said "salvage done", these get repointed and the handover files deleted — in one atomic pass:

| file:line | current text points at | repoint to (once content is placed) |
|---|---|---|
| `stack-map.md:5` | `handover.md` in companion-docs list | remove the entry |
| `stack-map.md:80` | "known bugs catalogued in `handover.md` §1" | `todo.md` (deploy.sh section) |
| `todo.md:13` | "goal-1 ledger in `handover2.md`" | wherever item 5 lands |
| `todo.md:26` | "see handover.md §gotchas" | `stack-map.md` layer 8 |
| `todo.md:27` | "catalogued in `handover.md` §1" | self (the expanded table) |
| `swarm-vs-compose-decision.md:3` | "`handover.md` §2 (the full alternatives survey)" | self (the appendix) |

**Note:** everything *not* in this worksheet was checked and is safely duplicated elsewhere — `immich/migration-runbook.md` already holds handover2's server-state, photo-safety model, remaining-steps, and credentials facts; `swarm-vs-compose-decision.md` + `stack-map.md` hold the decision rationale.
