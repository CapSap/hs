# SALVAGE worksheet — empty me, then delete me

**Temporary.** This is raw material rescued verbatim from `handover.md` and `handover2.md` before they get deleted. Nothing here is polished prose — it's _your original words_, quoted, so you can rewrite each piece into its home doc in your own voice and stay the author.

**How to use:** work through the checkboxes. For each one, write the content into the suggested home (in your words), then tick it. When every box is ticked, tell me "salvage done" and I'll (a) delete `handover.md` + `handover2.md` and (b) rewrite the 6 references listed at the bottom so nothing dangles. Then delete this file.

Ordered most-important first. The last two are optional/low-value.

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
