# SALVAGE worksheet — empty me, then delete me

**Temporary.** This is raw material rescued verbatim from `handover.md` and `handover2.md` before they get deleted. Nothing here is polished prose — it's _your original words_, quoted, so you can rewrite each piece into its home doc in your own voice and stay the author.

**How to use:** work through the checkboxes. For each one, write the content into the suggested home (in your words), then tick it. When every box is ticked, tell me "salvage done" and I'll (a) delete `handover.md` + `handover2.md` and (b) rewrite the 6 references listed at the bottom so nothing dangles. Then delete this file.

Ordered most-important first. The last two are optional/low-value.

---

## MUST-KEEP

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

| file:line                        | current text points at                            | repoint to (once content is placed) |
| -------------------------------- | ------------------------------------------------- | ----------------------------------- |
| `stack-map.md:5`                 | `handover.md` in companion-docs list              | remove the entry                    |
| `stack-map.md:80`                | "known bugs catalogued in `handover.md` §1"       | `todo.md` (deploy.sh section)       |
| `todo.md:13`                     | "goal-1 ledger in `handover2.md`"                 | wherever item 5 lands               |
| `todo.md:26`                     | "see handover.md §gotchas"                        | `stack-map.md` layer 8              |
| `todo.md:27`                     | "catalogued in `handover.md` §1"                  | self (the expanded table)           |
| `swarm-vs-compose-decision.md:3` | "`handover.md` §2 (the full alternatives survey)" | self (the appendix)                 |

**Note:** everything _not_ in this worksheet was checked and is safely duplicated elsewhere — `immich/migration-runbook.md` already holds handover2's server-state, photo-safety model, remaining-steps, and credentials facts; `swarm-vs-compose-decision.md` + `stack-map.md` hold the decision rationale.
