# desktop state — ground-truth facts about `sheelah-d`

**what this file is:** the same thing `system-state.md` is, but for the *desktop*
machine instead of the server. exact devices, UUIDs, mount points, and the state
of the backup drive. the two boxes are separate hardware with separate disk
layouts and nothing in `system-state.md` applies here.

**why it exists:** the backup plan is a two-machine plan (see
`decisions/backup-software-decision.md`), and half of it lives on this box. that
half had never been written down — it was reconstructed from `journalctl` in july
2026, six months after it was built, because nothing recorded it at the time.

**how to maintain it:** same rule as `system-state.md` — each section prints the
command that reveals the truth. run it, read the output, write the facts
underneath. keep it secret-free. **disk UUIDs and the borg repo id are fine
(they're printed on the hardware / in a world-readable file); the borg `key =`
blob and the repo passphrase are never to appear here.**

> **status (2026-07-29 verification session):**
>
> ✔ **verified live:** block devices · filesystems & UUIDs · mounts · capacity ·
> the backup drive's history · the borg repo (passphrase confirmed working, all
> three archives listed).
>
> ⚠️ **one fact not re-derived:** the reserved-block percentage (see capacity).

---

## the machine

```
hostnamectl        # hostname, os, kernel
id                 # current user + groups
```

**findings:** ✔ verified 2026-07-29

- **hostname:** `sheelah-d` (the server is `shelaria-s` — different box entirely)
- **kernel:** `6.12.73+deb13-amd64` — debian **13 (trixie)**. note the server is
  still on 12 (bookworm). the two machines are a full release apart, which
  matters for any tool that must be version-matched across them (borg is exactly
  such a tool — see the borg section).
- **user:** `sheelah`, uid 1000

---

## block devices

```
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL
```

**findings:** ✔ verified 2026-07-29

| device | size | model | role |
|---|---|---|---|
| `nvme0n1` | 1.9T | TEAM TM8FP6002T | nvme ssd — os + home, the working disk |
| `sda` | 12.7T | WUH721414ALE6L0 | **the backup hdd** — same hgst ultrastar model as the server's |
| `sdb` | 0B | Ultra HS-SD/MMC | card reader, no card inserted (0B = empty slot, not a fault) |
| `sdc` | 58.9G | STORAGE DEVICE | usb stick, exfat |

partitions:

| partition | size | fstype | mounted at |
|---|---|---|---|
| `nvme0n1p1` | 512M | vfat | `/boot/efi` |
| `nvme0n1p2` | 27.9G | ext4 | `/` |
| `nvme0n1p3` | 977M | swap | `[SWAP]` |
| `nvme0n1p4` | 1.8T | ext4 | `/home` |
| **`sda1`** | **12.7T** | **ext4** | **see mounts — this is the interesting one** |
| `sdc1` | 58.9G | exfat | `/media/sheelah/4A21-0000` |

things this settles:

- **no LVM on this machine.** the server puts `/`, `/var`, `/home`, `/tmp` and
  swap on logical volumes inside `shelaria-s-vg`; the desktop uses plain
  partitions straight on the nvme. so `lvextend` is not available here — growing
  `/home` would mean repartitioning, which is a different and much less pleasant
  operation. worth knowing before `/home` fills (it is close — see capacity).
- **the two 14tb drives are the same model in both machines.** `sda` here,
  `sdb` on the server. the letters differ because letters are assigned in kernel
  enumeration order per machine and mean nothing across boxes — which is the
  whole reason both fstabs must use UUIDs.

---

## filesystems & UUIDs

```
lsblk -f          # label + UUID without needing sudo
sudo blkid        # the fuller version
```

**findings:** ✔ verified 2026-07-29

| device | fstype | label | UUID |
|---|---|---|---|
| **`/dev/sda1`** | **ext4** | **`top-d`** | **`50613f6f-0dd8-4a82-97a3-85a03f95faf9`** |
| `/dev/nvme0n1p1` | vfat | — | `91D3-5B77` |
| `/dev/nvme0n1p2` | ext4 | — | `df02666e-f222-4509-9fae-b65371a96ee3` |
| `/dev/nvme0n1p3` | swap | — | `15254ee5-3a86-4de7-a47e-02ea25237e75` |
| `/dev/nvme0n1p4` | ext4 | — | `6092c4a4-0867-401f-aeba-20499c6b96d4` |
| `/dev/sdc1` | exfat | — | `4A21-0000` |

**the label `top-d` is load-bearing in a way labels usually aren't** — see the
mounts section. it's not decoration; it determines the path the drive appears at
when the file manager mounts it.

---

## mounts — **the open gap**

```
findmnt --real          # live mount tree
cat /etc/fstab          # declared intent
```

**findings:** ✔ verified 2026-07-29. **there IS a gap, and it's the one
outstanding piece of desktop-side backup setup.**

fstab declares four things and *none of them is the backup drive*:

| mount point | declared in fstab as | live source | fstype |
|---|---|---|---|
| `/` | `UUID=df02666e-…` | `/dev/nvme0n1p2` | ext4 |
| `/boot/efi` | `UUID=91D3-5B77` | `/dev/nvme0n1p1` | vfat |
| `/home` | `UUID=6092c4a4-…` | `/dev/nvme0n1p4` | ext4 |
| swap | `UUID=15254ee5-…` | — | swap |
| **`/mnt/top-d`** | **absent** | **—** | **—** |

**`/dev/sda1` is not in fstab.** as of 2026-07-29 it was found mounted at
**`/media/sheelah/top-d`**, which is *not* where it was set up in february
(`/mnt/top-d`, which still exists and is still empty).

### why the path moved: udisks2 vs fstab

the drive was mounted by **udisks2** — the daemon behind "click the disk in your
file manager" — not from the command line. no `sudo mount` appears in the journal
for it. the two mechanisms are genuinely different and produce different results:

| | udisks2 | fstab |
|---|---|---|
| path | `/media/<user>/<LABEL>` — derived from the filesystem label, hence `top-d` | whatever you write in the file |
| when | only when a logged-in desktop user clicks it | at boot, before anyone logs in |
| lifetime | until unmount / logout / reboot | permanent |
| access | granted to the mounting user via an ACL (the `+` in `drwxr-x---+` on `/media/sheelah`) | ordinary file ownership + mount options |

**udisks only offers to mount filesystems that are *not* in fstab** — it
deliberately stays out of the way of declared mounts. so the drive showing up in
the file manager at all is itself the symptom of the missing fstab entry.

### why this matters more than it looks

when nothing is mounted over it, `/mnt/top-d` is an ordinary directory on the
**root filesystem, which has ~8.6G free**. so there are two silent failure modes,
and a scheduled backup job hits one or the other:

- pointed at `/media/sheelah/top-d/…` → **path does not exist** when the job runs
  without a desktop session (systemd timer, cron, backrest at boot). udisks
  hasn't mounted anything.
- pointed at `/mnt/top-d/…` → **succeeds, and writes into `/`**, filling an 8.6G
  partition with backup data. no error until root is full.

this is the desktop-side twin of the fact `system-state.md` calls load-bearing
about the server's `/mnt/hdd`: *the fstab entry is what makes a backup target
real.*

### the fix (not yet applied)

```
UUID=50613f6f-0dd8-4a82-97a3-85a03f95faf9 /mnt/top-d ext4 defaults,nofail 0 2
```

- **`UUID=`, not `/dev/sda1`** — letters move between boots
- **`nofail`** — on a *data* disk, a missing drive must not drop the boot into an
  emergency shell. (the server's `/mnt/hdd` line uses bare `defaults` and is
  arguably wrong for the same reason.)
- **`2`** in the last field — fsck'd after root, in the periodic rotation

applying it, without a reboot:

```bash
udisksctl unmount -b /dev/sda1   # release the file-manager mount first
sudo systemctl daemon-reload     # systemd generates .mount units from fstab; re-read it
sudo mount -a                    # mount everything declared that isn't already mounted
findmnt /mnt/top-d               # verify: /dev/sda1, ext4, rw
```

after this the drive stops appearing as a removable device in the file manager,
and the february borg commands' paths become correct again.

### the guard worth putting in any script that writes here

```bash
mountpoint -q /mnt/top-d || { echo "hdd not mounted, aborting" >&2; exit 1; }
```

`mountpoint` asks the kernel "is a filesystem mounted here?", not "does this
directory exist?" — that is exactly the difference between writing to 12.7T of
disk and writing to 8.6G of root partition.

---

## capacity & usage

```
df -h
```

**findings:** ✔ verified 2026-07-29

| filesystem | size | used | avail | use% |
|---|---|---|---|---|
| `/` | 28G | 18G | 8.6G | 68% |
| `/boot/efi` | 511M | 4.4M | 507M | 1% |
| **`/home`** | **1.9T** | **1.7T** | **~42G** | **98%** |
| **`/dev/sda1`** (the hdd) | **13T** | **195G** | **12.3T** | **2%** |
| `/dev/sdc1` (usb) | 59G | 11G | 49G | 19% |

- **`/home` at 98% is a live problem on this machine**, independent of the server
  work. and with no LVM here, there is no `lvextend` escape hatch — the 12.7T hdd
  is the relief valve, by moving data rather than growing the partition.
- **the hdd's 195G is the borg repo** (see below), not stray files.

⚠️ **reserved blocks — recorded, not re-verified.** the journal shows
`tune2fs -m 1 /dev/sda1` was run on 2026-01-31, dropping ext4's root-reserved
share from the default 5% to 1%. the arithmetic corroborates it: 12.3T avail +
195G used ≈ 12.5T of the 12.7T device, leaving ~240G unaccounted for. a 5%
reserve alone would be ~635G. confirm properly with:

```bash
sudo tune2fs -l /dev/sda1 | grep -i reserved
```

why it was worth doing: the 5% reserve exists so a full disk can't lock root out
of a login and so the allocator can avoid fragmentation. on a pure data drive no
root process needs rescuing, so 5% of 12.7T is ~600G held back for nothing.
`system-state.md` flags the same change as still-to-do on the server's `/mnt/hdd`
— **this drive has already had it; that one hasn't.**

---

## the backup drive's setup history

reconstructed 2026-07-29 from `journalctl | grep -i -e top-d -e sda1 -e borg`.
recorded here so it never has to be reconstructed again.

```
Jan 31 14:21  apt install borgbackup
Jan 31 14:49  mkfs.ext4 -L top-d /dev/sda1        # format + label
Jan 31 14:52  tune2fs -m 1 /dev/sda1              # reserved blocks 5% → 1%
Jan 31 14:55  mkdir -p /mnt/top-d                 # mount point
Jan 31 14:55  mount /dev/sda1 /mnt/top-d          # BY HAND — never added to fstab
Jan 31 14:57  mkdir sheelah-d-backup server-backup archive
Feb 01 00:31  chown -R sheelah:sheelah /mnt/top-d
Feb 01 12:34  fsck.ext4 -f /dev/sda1              # clean
Feb 01 19:21  borg create … ::system-sheelah-d-2026-02-01        /etc /var/lib
Feb 01 19:22  borg create … ::system-sheelah-d-2026-02-01_19-22  /etc /var/lib
Feb 01 19:40  umount /mnt/top-d                   # stayed unmounted until july
```

> **methodological warning, learned the hard way during this session.**
> **`journalctl` logs `sudo` invocations — it is a record of privilege
> escalations, not a record of what you did.** the timeline above is missing a
> third borg archive, `desktop-sheelah-d-2026-02-01` (13:24, six hours before the
> `system-*` pair), because it ran as plain `sheelah` and needed no root. it is
> almost certainly where the 195G actually is. reading the journal alone gave a
> confidently wrong picture — "only system config is backed up" — until
> `borg list` contradicted it. **`~/.bash_history` is the other half of the
> record, and neither half is complete on its own. the repository itself is the
> only authority on what a backup contains.**

---

## the borg repository

```
borg list /mnt/top-d/sheelah-d-backup        # (path once fstab is fixed)
borg info /mnt/top-d/sheelah-d-backup
```

**findings:** ✔ verified 2026-07-29 — **passphrase confirmed working, repo opens,
all three archives listed.**

- **location:** `sheelah-d-backup/` on the hdd. **195G.**
- **borg version:** 1.4.0 (debian trixie)
- **encryption:** repokey mode — the key blob lives in the repo's `config`,
  wrapped in the passphrase. **the passphrase is the single point of failure for
  all 195G; without it the repo is unrecoverable noise. it is in keepassxc and
  was verified to work on 2026-07-29.** re-verify whenever the keepass db moves.
- **repo id:** `58867a6b2d6dc63a327acf610f399adf3dc7efeecb1425e167f37dc558ef8025`
  (not a secret — it identifies a repo, useful for telling an original from a copy)
- **`append_only = 0`**

archives present:

| archive | when | contents |
|---|---|---|
| `desktop-sheelah-d-2026-02-01` | feb 1, 13:24 | run without sudo — the bulk of the 195G. **contents not yet enumerated** |
| `system-sheelah-d-2026-02-01` | feb 1, 19:19 | `/etc` + `/var/lib`, zstd,6, `--one-file-system` |
| `system-sheelah-d-2026-02-01_19-22` | feb 1, 19:22 | same, three minutes later |

**still to do:** enumerate the desktop archive so it's known what's actually
protected —

```bash
borg info /mnt/top-d/sheelah-d-backup::desktop-sheelah-d-2026-02-01
borg list /mnt/top-d/sheelah-d-backup::desktop-sheelah-d-2026-02-01 | head -20
```

### the relocation warning

opening the repo at its udisks path printed:

```
Warning: The repository at location /media/sheelah/top-d/sheelah-d-backup
was previously located at /mnt/top-d/sheelah-d-backup
```

borg caches the path it last saw itself at and stops if it changes, because the
usual cause is operating on a *copy* of a repo instead of the original — the
mistake that silently forks backup history. here it's benign (same disk, moved
mount point). **it will fire once more, in the opposite direction, when the fstab
entry moves the drive back to `/mnt/top-d` — and then stop, because the path stops
moving.** `BORG_RELOCATED_REPO_ACCESS_IS_OK=yes` suppresses it and should *not* be
used: that disables a real safety check to paper over an unstable path.

---

## divergence from the backup decision doc

`decisions/backup-software-decision.md` (april 2026) chose **restic + backrest**.
this machine's reality, six months on, is different, and the doc has never been
reconciled with it:

| | the doc says | this disk has |
|---|---|---|
| tool | restic + backrest | **borg 1.4.0** — restic and backrest are **not installed** |
| desktop-local repo | `/mnt/backup/restic/desktop-local/` | `sheelah-d-backup/` (borg, 195G) |
| server-remote repo | `/mnt/backup/restic/server-remote/` | `server-backup/` (empty) |
| mount point | `/mnt/backup` | `/mnt/top-d` (and not in fstab) |
| — | — | `archive/` (empty, not in the plan) |

the borg work (january) **predates** the restic decision (april), so this is a
decision made and then not carried out, not a reversal.

**worth reopening rather than mechanically following the doc.** the doc's reasons
for restic were the self-hosted web gui (backrest) and install simplicity — it
explicitly concedes that borg's append-only support is the cleaner design, and
its own "when to revisit" list names *"if borg 2.0 ships stable and we want
append-only enough to switch"* as a trigger. what's changed since april is
cheaper than that trigger: there is now a **working, verified, 195G borg repo
with a passphrase that opens it**. "keep borg, add borgmatic for scheduling" is a
defensible answer.

**the one genuine cost of staying on borg**, which the doc predicted and the
hardware now confirms: borg must be **version-matched on both ends** of an ssh
backup. this desktop runs debian 13 with borg 1.4.0; the server runs debian 12,
whose borg is older. any cross-machine borg flow has to resolve that — matched
versions, or a distro upgrade on the server, or `borg serve` from a pinned
binary. restic has no such coupling, since its destination is dumb storage. **if
the cross-machine flows are what get built first, that coupling is the argument
that decides this.**

---

## what is NOT set up on this machine

so the next session doesn't re-derive it:

- ❌ **fstab entry for the hdd** — the one blocking item (see mounts)
- ❌ **restic / backrest** — not installed
- ❌ **any schedule at all** — no cron, no systemd timer, no borgmatic. the three
  archives are hand-run one-offs from a single evening in february. **nothing has
  backed anything up since 2026-02-01.**
- ❌ **the server→desktop flow** — `server-backup/` is an empty directory. this is
  the flow `backup-software-decision.md` calls *load-bearing for the photos*,
  since the server's own hdd repo is same-disk and therefore accidental-delete
  protection only. it does not exist yet in any form.
- ❌ **a restore drill** — never performed. `borg list` opening the repo proves
  the passphrase and the repo header, **not** that the data restores.
- ❌ **SMART baseline** — `smartctl -A /dev/sda` was run on 2026-07-29 but the
  output was not recorded. worth capturing here for a 12.7T drive holding the
  only copy of anything.

## what IS set up and verified

- ✔ partitioned, ext4, labelled `top-d`, reserved blocks tuned to 1%
- ✔ owned by `sheelah` — no sudo needed to write to it once mounted
- ✔ directory skeleton: `sheelah-d-backup/`, `server-backup/`, `archive/`
- ✔ fsck clean as of 2026-02-01
- ✔ a real, openable, encrypted 195G borg repo with three archives
- ✔ 12.3T free
