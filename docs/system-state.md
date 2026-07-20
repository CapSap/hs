# system state — ground-truth facts about this server

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

> placeholder — commands are in place, findings still to be filled in by direct
> investigation.

---

## block devices

what physical disks and partitions exist, how big, what model.

```
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL
```

`-o` picks the columns: name, size, type (disk/part/lvm), filesystem, mountpoint,
drive model.

**findings:**

_(paste output / write facts here)_

---

## filesystems & UUIDs

what each partition is formatted as, and the UUIDs that `/etc/fstab` references.

```
sudo blkid
```

**findings:**

_(paste output / write facts here)_

---

## LVM

the logical volume stack: which disks are physical volumes (PVs) → which volume
group (VG) → which logical volumes (LVs), plus free space left in the VG.

```
sudo pvs      # physical volumes — which disks feed LVM
sudo vgs      # volume groups — name + total/free space
sudo lvs      # logical volumes — /home, root, swap, sizes
```

**findings:**

_(VG name, LV sizes, free space in the VG, etc.)_

---

## mounts

what is mounted where (running state) vs what is *declared* in fstab (intent).
the interesting facts live in the gap — anything mounted but not in fstab won't
survive a reboot.

```
findmnt --real          # the live mount tree (real filesystems only)
cat /etc/fstab          # the declared mounts
```

**findings:**

| mount point | device / source | fstype | in fstab? |
|---|---|---|---|
| | | | |

---

## identity — host, os, users

hostname, OS, kernel; the real human users; group membership (esp. `docker`).

```
hostnamectl                       # hostname, os, kernel, virtualization
id                                # current user + groups
getent passwd | awk -F: '$3>=1000'   # real (non-system) user accounts
```

**findings:**

_(hostname, username, os/kernel, docker group membership, etc.)_

---

## docker ground-truth

the data-root footgun (immich's named volumes on the small ssd) + storage driver.

```
docker info                                     # full picture
docker info -f '{{.DockerRootDir}}'             # just the data-root path
```

**findings:**

_(data-root path, storage driver, etc.)_
