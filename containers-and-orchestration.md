# containers & orchestration — the primer under layer 4

the purpose of this file: the conceptual ground the layer-4 decision stands on. `swarm-vs-compose-decision.md` records *what* was chosen and why; this file records *how the thing actually works* — the kernel primitives under docker, the abstraction ladder from docker up to kubernetes, and the honest landscape of "simple orchestrators" for a single box. reread this when the mental model goes fuzzy, or when a shiny new orchestrator shows up and you need to place it.

companion docs: `stack-map.md` (layer 4), `swarm-vs-compose-decision.md` (the decision record).

## tl;dr

a container is not a thing the kernel has — it's three old linux features worn at once: **chroot** (a private filesystem view), **namespaces** (a private view of everything else), **cgroups** (a cap on how much you can consume). docker packages those into "run one container"; compose packages docker into "run many containers on one host"; swarm/k8s package compose into "run many containers across many hosts." on a single server the multi-host layer has no job, so the honest question is never "which orchestrator" but **"which unmet want do i have — a ui, deeper linux learning, or deploy ergonomics"** — and each answer is a different, smaller tool than kubernetes.

---

## part 1 — the three pillars (how a container is built)

there is no `container` object in the linux kernel. a container is a normal process that has been *lied to* by three independent mechanisms:

| pillar | limits… | the lie it tells the process | knob you'll see |
|---|---|---|---|
| **chroot** | filesystem view | "`/` is this directory; there is nothing above it" | bind mounts / `volumes:` |
| **namespaces** | view of everything else | "these are the only processes / interfaces / users / hostname that exist" | `networks:`, `ports:` |
| **cgroups** | resource *amount* | (no lie — a hard cap) "you may use this much cpu/memory/io" | `mem_limit`, `cpus` |

the clean split: **chroot + namespaces are about *isolation* (what you can see and reach); cgroups is about *limits* (how much you can consume).**

**chroot** ("change root", unix v7, 1979) is the ancestor — it makes a process see a chosen directory as `/` so it can't wander up into the host. the original "filesystem jail." modern runtimes don't literally call `chroot(2)` anymore; they use **`pivot_root`**, which does the same job but can't be escaped by a process still holding a file descriptor outside the jail. same pillar, hardened.

**namespaces** generalise that same "private view" idea to everything that *isn't* the filesystem. seven main kinds (eight if you count the newer time namespace):

- **pid** — its own process tree; container's main process is pid 1, can't see host processes
- **net** — its own interfaces, ip addresses, ports, routing table
- **mnt** — its own mount tree (this *is* the grown-up chroot; it's what makes pivot_root robust)
- **uts** — its own hostname
- **ipc** — its own shared memory / semaphores / message queues
- **user** — its own uid/gid mapping (root *inside* can map to an unprivileged user *outside*)
- **cgroup** — hides where it sits in the host's cgroup hierarchy

so: **chroot/mnt = the directory view; the other namespaces = every other non-directory resource.**

**cgroups** (control groups) are the only pillar that *enforces* rather than *hides*. they meter and cap cpu, memory, block io, pids. `docker run --memory=512m --cpus=1.5` is cgroups. when you see a `mem_limit:` or a `deploy.resources.limits` in a compose file, that's the field that reaches this pillar.

**the honourable mention (the real "fourth thing" people conflate):** the **union / overlay filesystem** (overlayfs today, aufs historically) — the copy-on-write layered filesystem that makes image *layers* + a writable container layer work. it's how images are cheap to store and fast to start. it isn't isolation or limiting, so it sits beside the three pillars rather than among them. other real-but-secondary isolators: **capabilities** (split root's all-or-nothing power into droppable pieces), **seccomp** (restrict which syscalls are allowed).

**the mental one-liner:** a container = one process + chroot (private files) + namespaces (private everything-else) + cgroups (a resource cap), with overlayfs underneath making the image layers cheap.

---

## part 2 — the abstraction ladder

each rung is a wrapper over the one below it. nothing here replaces docker — it *packages* docker for a bigger unit of work.

```
chroot + namespaces + cgroups   ← raw linux kernel features (part 1)
          ↓ abstracts
        docker                   ← run ONE container from an image
          ↓ abstracts
    docker compose               ← run MANY containers together, declaratively, ONE host
          ↓ abstracts
     docker swarm                ← run that same described app across a CLUSTER, + keep it alive
          ↓ abstracts
      kubernetes                 ← same job, industrial scale (the one that "won")
```

**docker (the engine)** turns the three pillars into one imperative command:
`docker run -d --name db -e POSTGRES_PASSWORD=… -v db_data:/var/lib/postgresql/data -p 5432:5432 postgres:16`.
one container, one long line of flags. fine for one thing, miserable for a real app (db + web + proxy) that needs several containers wired together in the right order.

**docker compose** makes that declarative: write the flags down as yaml `services:` and bring the whole set up with `docker compose up -d`. the primitives from part 1 reappear as *fields* — `volumes:` (chroot/mnt), `ports:`/`networks:` (net namespace), `mem_limit`/`cpus` (cgroups). what compose adds on top:

1. **declarative + version-controlled** — infra is a file in git, not shell history
2. **multi-container orchestration on one host** — several services + their `depends_on` ordering
3. **automatic networking** — a private network where containers reach each other *by service name* (web → `db`, no ip juggling)
4. **one-command lifecycle** — `up` / `down` / `logs` / `ps` manage the whole stack

**docker swarm** stretches "many containers on one host" to "many containers across many hosts." it turns a pool of docker engines into one virtual engine (managers decide scheduling + hold desired state; workers run containers). what it adds *over* compose:

- **desired-state reconciliation (self-healing)** — declare "3 replicas"; if a container or a whole node dies, swarm reschedules the missing copies onto healthy nodes. compose won't — if the host dies, it's just down.
- **horizontal scaling** across nodes; **routing mesh** load-balancing; **rolling updates + rollback**; **overlay networks** spanning hosts; first-class encrypted **secrets**.

the elegant part: **swarm reuses the compose file.** same yaml, different verb — `docker stack deploy -c compose.yml mystack` instead of `docker compose up`. the bridge is the **`deploy:`** block, which is the swarm-specific section (`replicas`, `placement`, `update_config`). plain compose ignores most of `deploy:`; swarm brings it alive. so compose and swarm are two consumers of one file format — one single-host, one clustered.

**kubernetes** does swarm's job at industrial scale and won the ecosystem. **k3s/k0s/microk8s** are lightweight single-binary distributions of it — light to *run*, but the k8s *mental model* stays heavy.

**the one-liner:** docker = run *a* container; compose = describe *a set* of containers on one host; swarm/k8s = run that set across a *cluster* and keep it alive when machines die.

---

## part 3 — what choosing plain compose means when you add a service

(the decision to be on compose lives in `swarm-vs-compose-decision.md`; this is the operational consequence.)

**the good news — adding a service is a leaf operation.** because compose has no shared cluster state, each service stays an island. adding "forgejo" later is: `mkdir forgejo/` → write `forgejo/docker-compose.yml` → (if needed) a secrets file → add its data path to the restic includes → bring it up. nothing above layer 5 moves. that containment *is* goal 4 ("ready for future services"), and it's already true.

**what you now own yourself** (the bits an orchestrator would have managed — on one node these become *conventions you keep by hand*):

| concern | an orchestrator would… | on your compose box, you… |
|---|---|---|
| **port collisions** | hide it behind ingress | keep a port map — two services can't both bind `8090` (beszel's there; portainer 9000/9443) |
| **inter-service networking** | flat cluster network | get a *private* network per compose project by default; to let a service reach immich you explicitly join a shared external network — otherwise it's isolated (usually what you want) |
| **restart / boot survival** | self-heal / reschedule | `restart: unless-stopped` + docker starting on boot; crash-restart only, no rescheduling |
| **updates** | rolling update | `docker compose pull && up -d` per service; a few seconds' downtime (already accepted) |

**the loose end:** `deploy.sh` is still swarm-native (`docker swarm init`, `docker stack deploy`, `docker secret create`). so today a new plain-compose service isn't served by the deploy path — you'd `docker compose up -d` it by hand or teach the script a compose branch. tracked in `todo.md`.

**dialect gotcha — don't template new services off the old files.** `portainer/` and `beszel/` are written in *swarm* dialect; several keys mean nothing under plain compose (`deploy.mode`, `deploy.placement`, `deploy.replicas`, `networks.driver: overlay`). under plain compose the idioms flip, and some things start working that swarm ignored:

- `restart: unless-stopped` (not `deploy.restart_policy:`)
- `depends_on:` **actually orders startup** (swarm ignored it)
- `container_name:` **is honoured** (swarm ignored it)
- default `bridge` network, not `overlay`

so template new services off **immich** after its migration — that's the first true plain-compose citizen — not off portainer/beszel.

---

## part 4 — the single-server orchestrator landscape

**the reframe that makes this tractable:** an orchestrator's core job is *placing containers across many machines and holding desired state*. on one box the placement half is meaningless. so "which orchestrator?" is the wrong question; the right one is **"which of these problems do i actually want solved?"** — and each answer is a different, smaller tool:

| the want | tool category | examples |
|---|---|---|
| "keep my containers running, declaratively" | you already have it | **compose** + restart policies |
| "give me a ui to see/manage them" | management gui | **dockge**, portainer, yacht |
| "supervise them like real linux services" | init-based | **podman + systemd (quadlet)** |
| "git-push and it deploys, with tls" | single-server paas | **coolify**, caprover, dokku |
| "i genuinely want to learn a scheduler" | lightweight scheduler | **nomad**, k3s |

**the options, walked:**

- **compose + a management gui (lightest).** not orchestration — a *face* on it. **dockge** is worth naming: it's compose-*native* (reads/writes your actual `docker-compose.yml` files instead of hiding them in a database the way portainer tends to), so it respects a repo that already *is* compose files in git. smallest possible step; changes nothing architecturally.

- **podman + systemd / quadlet** ← *the one that fits goal 1.* the "boring linux" orchestrator: **systemd is the scheduler.** write a `.container` unit and systemd starts/restarts/orders/logs it like any service (`systemctl status forgejo`, `journalctl -u forgejo`). two reasons it's interesting *here*: (1) **maximally transferable** — systemd is on every debian box you'll touch; it teaches real init/service management, not a vendor api; (2) **rootless by default** — containers run as your user, a genuine security upgrade over rootful docker, aligned with layer-8 thinking. cost: different runtime (podman not docker), newer idiom, smaller troubleshooting corpus. of everything here, the one that teaches the most that carries elsewhere.

- **single-server paas: coolify / caprover / dokku.** a different axis — these solve *deployment ergonomics*, not clustering. **coolify** = self-hosted vercel/heroku (web ui, git-push, auto-tls, manages compose apps); nicest ux, heaviest. **caprover** = similar but *swarm under the hood* (reintroduces the layer you're removing). **dokku** = the minimalist, git-push-to-deploy + buildpacks, small footprint. these make sense **only if the pain is "deploying is manual"** (i.e. the `deploy.sh` friction), not orchestration — but they'd own your whole layer 5 and add a lot of moving parts to a deliberately-boring box.

- **lightweight schedulers: nomad, k3s.** real orchestrators that *run* fine on one node. **nomad** — single go binary, hcl config, far humaner mental model than k8s; the honest answer to "i want scheduler experience someday." **k3s** — light to run, heavy to *think in*; already ruled out at layer 4.

**mapping back to the framework:** all of these live at **layer 4**, marked *decided*, whose revisit trigger is *"a real multi-node need appears."* none trips it. so:

- for the stated goals, **compose stays right** — nothing here beats it on the immich/backups/fundamentals critical path.
- the two that could earn a look *without* violating the philosophy are the ones serving a want compose doesn't:
  - **dockge** — if the want is a ui (and it'd resolve the portainer-vs-beszel todo: dockge for management, beszel for monitoring)
  - **podman + quadlet** — if the want is *learn something transferable* (goal 1), the most educational option here, with rootless as a real security win

**the one-liner:** on a single server you don't need an *orchestrator* — decide whether the unmet want is **a ui (dockge)**, **deeper linux + rootless (podman/quadlet)**, or **deploy ergonomics (coolify/dokku)**. each is a different tool, and none of them is "a smaller kubernetes."

---

## the decision protocol, applied

new orchestrator/container tool shows up → (1) it's **layer 4**; (2) layer 4 is **decided** — does the written trigger (*a real multi-node need*) fire? on one server it can't; (3) if it's genuinely interesting, add a one-line note here and move on. that's not dismissiveness — the reframe above already weighed the whole category.
