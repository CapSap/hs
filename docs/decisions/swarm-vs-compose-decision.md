# swarm → plain compose decision (july 2026)

the "why are we switching?" record. this question has resurfaced more than once — when it does, reread this instead of re-deriving it. the full alternatives survey (6 options + recommendation) is the appendix at the bottom of this file. companion doc: `stack-map.md` layer 4.

## tl;dr

swarm was chosen to solve a problem compose already solves (secrets), and for a goal that got demoted (production mimicry) — while actively adding friction to the goals that remain (immich + backups + learning). we're removing an orchestration layer that had no job, not changing paradigms.

## why swarm got picked originally

1. belief that safe per-service secret injection required it
2. mimicking a production deployment for the business-workload idea (csv/sftp project)

both were reasonable at the time.

## why both reasons dissolved

**secrets:** plain compose supports file-based `secrets:` — same `/run/secrets/` mounts, same `*_FILE` env vars, same discipline. swarm's extras are tmpfs storage + encryption in the raft store, but on a single node the encryption key sits on the same disk as the data it encrypts, so the real gain over a root-owned `chmod 600` file is thin. the valuable thing built here — secrets never in images, `docker inspect` output, git, or shell history — transfers unchanged.

**mimicry:** single-node swarm is niche in real production. companies run plain compose on a vps, or kubernetes — almost nothing in between. so it wasn't even mimicking well. and the re-anchored goals (linux fundamentals, immich, backups) put that workload in the background anyway. what transfers to any job is the discipline (file secrets, declarative stacks, scripted deploys), not the swarm api.

## what swarm actively costs (what tipped it from "harmless leftover" to "migrate")

- **immich's whole world assumes compose** — official docs, upgrade guides, every community troubleshooting thread. under swarm, `container_name` and `depends_on` are silently ignored, healthchecks behave differently. every future problem starts with "is this an immich issue or a swarm-divergence issue?" friction with zero learning payoff
- **backups/restores become the textbook procedure** — `compose down` → restore files → `compose up -d`. matters enormously because backups are the core goal and the restore drill is the final exam
- **swarm secrets are immutable** — which is why `deploy.sh:141-152` silently skips rotating any in-use secret, and why the manual stop/rm/redeploy rotation dance existed. with compose: edit the file, `up -d`, done
- **a second mental model for one machine** — two answers to "how do i restart this", "where are the logs", "how do i change a config"

## what swarm honestly does better — and why it doesn't matter here

- rolling updates: compose recreation = a few seconds of downtime. irrelevant for a LAN photo library
- multi-node scheduling / HA: impossible on one box; the node is the single point of failure regardless
- tmpfs secrets: thin on a single node (see above)

this isn't "swarm is bad" — the setup was correctly built. it's that on one home server, every swarm feature is either replicated by compose or serves a situation this server can't be in.

## what is NOT changing

still docker. still containers. still isolation via per-service networks and minimal mounts. still declarative files in git. still disposable containers (data in bind mounts, config in git, secrets in files — nothing of value inside a container). still the `*_FILE` secrets pattern.

and not a big-bang: a swarm manager is a normal docker engine, so compose runs alongside the existing stacks. each service moves only when there's a concrete reason to touch it. immich's reason was concrete — it had to be stopped and repointed at bind mounts anyway.

## the litmus test that settled it

for each feature swarm provides, ask: **which of the four goals does this serve?** (linux fundamentals / immich / backups / ready for future services)

every answer came back empty. the compose column had: immich's docs work again, restores become simple, one less model in your head.

## when to revisit

- a genuine multi-node need appears (a second always-on machine that must run coordinated workloads — not just a backup target)
- the business-mimicry project comes back AND its learning goal is specifically orchestration rather than the cron/sftp/backup fundamentals it actually needs

absent those, resurfacing doubt is noise, not signal — reread this file and move on.

other considerations

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
