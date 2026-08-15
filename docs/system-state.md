# system state — ground-truth facts about this server

**scope: the server (`shelaria-s`) only.** the desktop (`sheelah-d`) is separate
hardware with a separate disk layout — plain partitions, no LVM, its own backup
hdd. nothing below applies to it. its counterpart file is `desktop-state.md`.

**what this file is:** the literal, current state of the machine, re-derived by
investigating the live server (not copied from anywhere). exact sizes, device
names, UUIDs, the VG name, the username, mount points, the docker data-root.

**how it differs from `stack-map.md`:** stack-map is the *decision* layer — why
things are the way they are, and when to reopen a choice as technology shifts.
this file is the *state* layer — what is actually true right now. rule of thumb:
run a command that changes the box → update this file; make a choice → update
stack-map.

**how to maintain it:** each section below has the command that reveals the
truth. run it, read the output, write the facts underneath. keep it secret-free
(usernames, disk layout, paths = fine; passwords, keys = never — this is in git).

> **status (2026-07-22 verification session):**
>
> ✔ **verified on the live box:** block devices · filesystems & UUIDs · LVM ·
> mounts · capacity & usage. every fact in those sections came from running the
> command printed above it and reading the output. **the whole storage layer is
> now checked rather than remembered.**
>
> ✔ **also verified:** identity · docker ground-truth. **every section in this
> file is now checked against the live box. no ⚠️ claims remain.**
>
> the ⚠️ facts were written from memory in the old handover docs, not re-derived
> on this machine. run each section's command to confirm (and fix) them, then
> drop the ⚠️.

---

## block devices

what physical disks and partitions exist, how big, what model.

```
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL
```

`-o` picks the columns: name, size, type (disk/part/lvm), filesystem, mountpoint,
drive model.

**findings:** ✔ verified on the live box 2026-07-22

**two physical disks, that's all there is:**

| device | size | model | role |
|---|---|---|---|
| `sda` | 238.5G | SAMSUNG MZ7LN256HAJQ-000L7 | ssd — the OS disk |
| `sdb` | 12.7T | WUH721414ALE6L0 (hgst ultrastar) | the big hdd |

partitions:

| partition | size | fstype | mounted at |
|---|---|---|---|
| `sda1` | 512M | vfat | `/boot/efi` |
| `sda2` | 488M | ext2 | `/boot` |
| `sda3` | 237.5G | LVM2_member | → the volume group (see LVM) |
| `sdb1` | 12.7T | ext4 | `/mnt/hdd` |

things this settles:

- **"14tb" vs "12.7T" is not a discrepancy.** drives are sold in base-10 (14 ×
  10¹² bytes); `lsblk` prints base-2 and labels TiB as `T`. 14e12 ÷ 1024⁴ ≈
  12.73. same disk, two rulers.
- **only ONE hdd is in the server.** the old open question ("how many disks
  total?") is answered. this is consistent with the backup plan — its "2 disks"
  are the server's hdd and the *desktop's* hdd, in different machines. the
  server-local restic repo is accidental-delete protection only; drive-failure
  protection for the photos is the desktop-side copy.
- **device names move.** this drive was `sda1` in an earlier session and is
  `sdb1` today. `sd*` letters are assigned in kernel enumeration order at boot
  and can change on a reboot or cable swap. this is exactly why fstab must
  reference UUIDs, never `/dev/sdX`.

_(lsblk shows the **running** mount, not the declared intent — whether `/mnt/hdd`
survives a reboot is an fstab question, still open in the **mounts** section.)_

---

## filesystems & UUIDs

what each partition is formatted as, and the UUIDs that `/etc/fstab` references.

```
sudo blkid
```

**findings:** ✔ verified on the live box 2026-07-22

| device | fstype | filesystem UUID |
|---|---|---|
| `/dev/sdb1` | ext4 | `79ebb986-e3b0-4266-b452-e84f7df185d9` ← **`/mnt/hdd`, the one fstab must reference** |
| `/dev/sda1` | vfat | `BE13-714B` |
| `/dev/sda2` | ext2 | `be39df17-c809-440c-a562-bcff5864aff5` |
| `/dev/sda3` | LVM2_member | `HKMtG9-sJFe-xUr2-uezE-pnd0-rMXl-ghQTGH` (not a filesystem — see below) |
| `shelaria--s--vg-root` | ext4 | `a74b64d1-c635-4ef7-abeb-b5a83ecc5e60` |
| `shelaria--s--vg-var` | ext4 | `897e017b-227c-412f-8fdd-aa587fbab187` |
| `shelaria--s--vg-home` | ext4 | `67ccc105-1ffc-44f5-bb0d-38db052b6a18` |
| `shelaria--s--vg-tmp` | ext4 | `27a7dbb3-5a2a-4f36-80bb-0dd68056498c` |
| `shelaria--s--vg-swap_1` | swap | `b46a4db5-2e77-4f51-9807-4d147b3a710a` |

what the different id types actually are (blkid prints several and they are NOT
interchangeable):

- **`UUID=`** — lives in the *filesystem's* superblock, written by `mkfs`. this
  is what `fstab` means when it says `UUID=`. reformat the partition and it
  changes.
- **`PARTUUID=`** — lives in the *GPT partition table*, one level below the
  filesystem. only the real partitions (`sda1/2/3`, `sdb1`) have one. survives a
  reformat, because the partition still exists.
- **the LVM LVs have no PARTUUID** — they aren't partitions. they appear as
  `/dev/mapper/<vg>-<lv>` because device-mapper synthesises them out of the PV.
- **`sda3`'s "UUID" is not a filesystem UUID at all** — `TYPE="LVM2_member"`
  means that partition is *donated to LVM*, and the id is its PV identifier, a
  different namespace with a different format (the `HKMtG9-sJFe-…` shape).
- **`sda1`'s `BE13-714B` is short because FAT has no UUID.** it's a 32-bit
  volume serial number; blkid formats it as a UUID for consistency.

these are disk identifiers, not credentials — safe to keep in git. they're
printed on the disk for anyone holding it.

**still open:** blkid says these UUIDs *exist*. it does not say `/etc/fstab`
uses them — that's the **mounts** section below, and it's the check that
actually matters before immich boots onto `/mnt/hdd`.

---

## LVM

the logical volume stack: which disks are physical volumes (PVs) → which volume
group (VG) → which logical volumes (LVs), plus free space left in the VG.

```
sudo pvs      # physical volumes — which disks feed LVM
sudo vgs      # volume groups — name + total/free space
sudo lvs      # logical volumes — /home, root, swap, sizes
```

**findings:** partly verified 2026-07-22 (from `lsblk` — `pvs`/`vgs`/`lvs` not yet run)

- **VG name:** `shelaria-s-vg` ✔ confirmed
- **the one PV is `sda3`** (237.5G) — the hdd is NOT in LVM, it's a plain ext4
  partition

the logical volumes, ✔ all confirmed present with these sizes:

| LV | size | fs | mounted at |
|---|---|---|---|
| `root` | 22.3G | ext4 | `/` |
| `var` | 7.7G | ext4 | `/var` |
| `swap_1` | 976M | swap | `[SWAP]` |
| `tmp` | 1.4G | ext4 | `/tmp` |
| `home` | 116.4G | ext4 | `/home` |

- **the `lvextend` held.** `/home` was 100% full (83G / 85G) and was extended
  live with zero downtime — `sudo lvextend -r -L +30G shelaria-s-vg/home` — and
  today reads **116.4G**. (first write operation of the project.)
- **`/var` is 7.7G** — the partition that filled up and started this whole
  migration.
- **reading LV names in lsblk output:** it prints `shelaria--s--vg-home`. the
  doubled dashes are device-mapper escaping — a literal `-` inside a VG or LV
  name gets doubled so the `vg-lv` separator stays unambiguous. the real names
  are `shelaria-s-vg` and `home`, and that's what you type in commands.
- **free space in the VG: `88.76G` unallocated** ✔ measured with `vgs`
  2026-07-22. (`vgs` reports `VSize <237.50g`, `VFree <88.76g` — lvm's `<`
  prefix means "slightly less than", i.e. it's rounding down to be honest about
  extent boundaries.) the earlier estimate-by-subtraction of ≈88G was right.
- **`vgs` also confirms the shape:** `#PV 1`, `#LV 5` — one physical volume
  (`sda3`), five logical volumes, matching the table above. the 12.7T hdd is
  **not** part of LVM.
- that 88.76G is headroom for future `lvextend`s on the ssd. it is not a
  substitute for the hdd — it lives on the same physical disk as everything
  else in the VG.

---

## mounts

what is mounted where (running state) vs what is *declared* in fstab (intent).
the interesting facts live in the gap — anything mounted but not in fstab won't
survive a reboot.

```
findmnt --real          # the live mount tree (real filesystems only)
cat /etc/fstab          # the declared mounts
```

**findings:** ✔ verified on the live box 2026-07-22. **no gap — every mounted
filesystem is declared in fstab, and nothing in fstab is missing from the live
tree.** (`/media/cdrom0` is declared `noauto`, so it is correctly absent.)

| mount point | declared in fstab as | live source | fstype | options |
|---|---|---|---|---|
| `/` | `/dev/mapper/shelaria--s--vg-root` | same | ext4 | `errors=remount-ro` |
| `/boot` | `UUID=be39df17-…` | `/dev/sda2` | ext2 | `defaults` |
| `/boot/efi` | `UUID=BE13-714B` | `/dev/sda1` | vfat | `umask=0077` |
| `/home` | `/dev/mapper/shelaria--s--vg-home` | same | ext4 | `defaults` |
| `/tmp` | `/dev/mapper/shelaria--s--vg-tmp` | same | ext4 | `defaults` |
| `/var` | `/dev/mapper/shelaria--s--vg-var` | same | ext4 | `defaults` |
| swap | `/dev/mapper/shelaria--s--vg-swap_1` | — | swap | `sw` |
| `/media/cdrom0` | `/dev/sr0` | not mounted | udf,iso9660 | `user,noauto` |
| **`/mnt/hdd`** | **`UUID=79ebb986-e3b0-4266-b452-e84f7df185d9`** | `/dev/sdb1` | ext4 | `defaults` |

**the load-bearing fact: `/mnt/hdd` is mounted by UUID from fstab and therefore
survives reboots.** immich's bind mounts can safely depend on that path. this
was claimed from memory since february and is now actually checked.

the UUID indirection is visible in the two outputs side by side: fstab names the
disk by `UUID=79ebb986-…`, findmnt reports the live source as `/dev/sdb1`. the
kernel resolved the UUID to whatever letter the disk landed on this boot. that
same drive was `sda1` in an earlier session — which is precisely the failure the
UUID prevents.

**why the LVM rows use `/dev/mapper/…` instead of UUID, and why that's still
safe:** device-mapper names are derived from the VG and LV names, not from
kernel enumeration order. LVM finds its physical volumes by scanning for the PV
UUID and always assembles the same LV under the same `/dev/mapper/<vg>-<lv>`
path. so `/dev/mapper/shelaria--s--vg-home` is stable in a way `/dev/sdb1` is
not. the bare partitions (`/boot`, `/boot/efi`, `/mnt/hdd`) are the ones that
*need* UUIDs, and all three have them.

**reading an fstab line** — six fields: `<device> <mountpoint> <type> <options>
<dump> <pass>`

- `dump` — always `0` now; it's for a 1980s backup tool nobody runs
- `pass` — fsck order at boot. `1` = root, checked first; `2` = checked after;
  `0` = never checked. `/mnt/hdd` is `2`, so it's in the periodic fsck rotation
- `defaults` — expands to `rw,suid,dev,exec,auto,nouser,async`. the `auto` is
  what makes it mount at boot; `exec` and `suid` matter for containers
- findmnt adds `relatime` everywhere — a kernel default, not from fstab. it
  reduces write amplification by only updating a file's access time when it's
  older than the modify time

**`/mnt/hdd` has no `ro`, `noexec` or `nosuid`** — nothing in the mount options
will get in docker's way when it bind-mounts the library and postgres data.

**a formatting tell worth noting:** the `/mnt/hdd` line is single-space
separated while every other line is column-aligned. the aligned ones were
written by the debian installer; that one was added by hand in february.

---

## capacity & usage

how full each filesystem actually is. `lsblk` gives device *size*; this gives
*usage*. the two disagree on purpose — see the reserved-blocks note below.

```
df -h                # -h = human-readable units instead of 1K blocks
```

**findings:** ✔ verified on the live box 2026-07-22

| filesystem | size | used | avail | use% |
|---|---|---|---|---|
| `/` | 22G | 4.0G | 17G | 20% |
| `/boot` | 456M | 83M | 349M | 20% |
| `/boot/efi` | 511M | 5.9M | 506M | 2% |
| `/home` | 115G | **83G** | 26G | **77%** |
| `/var` | 7.6G | 1.2G | 6.0G | 17% |
| `/tmp` | 1.4G | 52K | 1.3G | 1% |
| `/mnt/hdd` | 13T | **76G** | 12T | **1%** |

- **`/home` is out of the danger zone** — 77% instead of 100%. the 83G used is
  unchanged (that's docker's data-root); the +30G `lvextend` is what created the
  26G of breathing room. the 83G still needs reclaiming, and that's runbook
  step 8, gated on a restic snapshot existing first.
- **`/mnt/hdd` holds 76G** — exactly the expected immich copy (library ~75G +
  database 339M + model-cache 766M). the data is still where step 3 left it.
- **`/var` is no longer a problem** at 17%. it was the original disaster; moving
  docker's data-root to `/home` is what defused it (and moved the problem).

**why df's sizes are smaller than lsblk's** (e.g. `/home`: 116.4G vs 115G):
lsblk reports the *block device*; df reports the *filesystem*, after ext4's own
metadata — inode tables, the journal, superblock backups — is subtracted. the
space isn't missing, it's the filesystem's own bookkeeping.

**why used + avail doesn't equal size:** `/home` is 83G + 26G = 109G, not 115G.
the missing ~6G is ext4's **reserved blocks**, 5% by default, usable only by
root. it exists so a full disk can't lock root out of a login and so the
allocator has room to avoid fragmentation.

> **worth revisiting later (not now):** that same 5% rule applies to
> `/mnt/hdd`, where 5% of 12.7T is roughly **600G held back on a pure data
> drive**. the reserve makes sense on the OS disk; on a drive that only stores
> photos and backups, no root process needs rescuing. it's adjustable live with
> `sudo tune2fs -m 1 /dev/sdb1` (no unmount, no data touched). confirm the
> current value first with `sudo tune2fs -l /dev/sdb1 | grep -i reserved`. not
> urgent — 12T is free — but it's free space for one command.

**the tmpfs lines are not disks.** `udev`, `/run`, `/dev/shm`, `/run/lock` and
`/run/user/*` are RAM-backed filesystems that exist only while the machine is
running. this is why `findmnt --real` filters them out.

- **inferred RAM: ~7.8G.** `/dev/shm` defaults to half of physical memory and
  shows 3.9G; `udev` shows 3.8G. worth knowing before the immich v3 upgrade,
  since the machine-learning container is the memory-hungry part of the stack.
- **`/run/user/106`** — a systemd user session for uid 106, a *system* account
  (below 1000), not the human user. probably the display manager, since xfce was
  installed. worth a glance in the identity section below.

---

## identity — host, os, users

hostname, OS, kernel; the real human users; group membership (esp. `docker`).

```
hostnamectl                       # hostname, os, kernel, virtualization
id                                # current user + groups
getent passwd | awk -F: '$3>=1000'   # real (non-system) user accounts
```

**findings:** ✔ verified on the live box 2026-07-22

**the machine:**

- **hostname:** `shelaria-s`
- **os:** Debian GNU/Linux **12 (bookworm)** — note: *not* 13. bookworm is
  oldstable as of trixie's release, so a distro upgrade is a future project.
  deliberately NOT folded into the immich migration.
- **kernel:** `6.1.0-35-amd64`, architecture `x86-64`
- **hardware:** Lenovo ThinkCentre M910s — a small-form-factor office desktop.
  worth remembering when planning storage: SFF cases have very few drive bays,
  so "just add another hdd to the server" may not be physically possible. the
  backup plan's second disk living in the *desktop* is therefore the right call
  by necessity as well as by design.

**the human user:**

- `uid=1000(shelaria) gid=1000(shelaria)`
- the two groups that matter: **`27(sudo)`** and **`995(docker)`**
- the rest are desktop-install leftovers from xfce: `cdrom, floppy, audio, dip,
  video, plugdev, users, netdev, lpadmin, scanner`

> **security fact worth internalising: membership in `docker` is equivalent to
> root.** it is not a lesser privilege. anyone in that group can start a
> container that bind-mounts `/` and edit any file on the host as root — no
> password, no sudo log entry. that's not a docker bug, it's inherent to the
> daemon running as root and accepting instructions over a socket. it's a fine
> trade on a single-user home box; it would not be on a shared machine. the
> practical consequence: **guard the `docker` group like you guard `sudo`.**

**loose end:** `df` showed a `/run/user/106` session. group `106` here is
`netdev`, but that's a coincidence of numbering — `/run/user/<n>` uses a **uid**,
and uids and gids are separate namespaces. resolve it with
`getent passwd 106` if curious; most likely the display manager, since xfce is
installed.

---

## docker ground-truth

the data-root footgun (immich's named volumes on the small ssd) + storage driver.

```
docker info                                     # full picture
docker info -f '{{.DockerRootDir}}'             # just the data-root path
```

**findings:** ✔ verified on the live box 2026-07-22

- **data-root is `/home/docker-data/docker`** — confirmed straight from the
  daemon with `docker info -f '{{.DockerRootDir}}'`. not the default
  `/var/lib/docker`. this was set deliberately in `/etc/docker/daemon.json`
  after `/var` (7.6G) filled up.
- **this is the footgun.** named volumes live under the data-root, so they land
  on the **small ssd**, not the 14tb drive. immich's volumes (~76G) are the 83G
  currently sitting on `/home`. moving the data-root didn't solve the problem,
  it relocated it from a 7.6G partition to a 116G one.
- the real fix is the bind mounts onto `/mnt/hdd` — the migration in progress.

### containers: the fossil record of the crash

`docker ps -a` (the `-a` matters — plain `docker ps` hides stopped containers
and reports an empty, misleading "nothing here"):

| container | image | status |
|---|---|---|
| `immich_redis.1.vx6s6jhs…` | valkey/valkey:8-bookworm | Exited (255) |
| `immich_database.1.7rb6hkh2…` | immich postgres 14-vectorchord | **Exited (1)** |
| `immich_database.1.wf8ipy6k…` | immich postgres 14-vectorchord | **Exited (1)** |
| `immich_database.1.qmx5m7og…` | immich postgres 14-vectorchord | **Exited (1)** |
| `hardcore_dewdney` | hello-world | Exited (0), 11 months ago |

what this tells us:

- **the `.1.<random>` suffix is swarm task naming.** plain compose names a
  container after the service; swarm names it
  `<stack>_<service>.<replica>.<taskID>`. these are leftover swarm tasks —
  independent confirmation of the swarm history, from a different angle than
  `docker info`.
- **three postgres containers, all `Exited (1)`.** that's not three deployments,
  it's a crash loop: postgres failed, swarm replaced the task, the replacement
  failed the same way. exit code 1 = the process died with an error. this is
  what "the disk filled up and things stopped working" looks like in the
  container record.
- **no `immich_server` or `immich_machine_learning` containers survive** — they
  were removed at some point; only the database's failed attempts remain.
- `hello-world` from 11 months ago is the very first docker test on this box.
  harmless.
- **no name collision with the new compose file.** it sets
  `container_name: immich_redis` / `immich_postgres` / `immich_server` /
  `immich_machine_learning`; the old ones all carry the `.1.<taskID>` suffix, so
  the strings differ and `docker compose up -d` won't hit "name already in use".
