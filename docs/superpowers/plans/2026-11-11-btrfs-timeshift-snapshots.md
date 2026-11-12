# btrfs snapshots: Timeshift + grub-btrfs — implementation plan

> **For agents:** mandatory sub-skill: `superpowers:executing-plans` (chosen: implementation in this session). Steps are marked with checkboxes.

**Goal:** on a PuraD btrfs installation, install Timeshift and grub-btrfs, create an initial snapshot on first boot and ensure actual booting into a read-only snapshot via overlayfs in initramfs.

**Architecture:** during the ISO build, the vendored grub-btrfs v4.14 is built into a local `.deb` and, together with `timeshift`/`inotify-tools`, placed into the apt repository on the medium. The Calamares module `purad-snapshots` after the `packages` step determines the file system of the target root: on ext4 it does nothing, on btrfs it installs the packages, writes the Timeshift config, sets the marker and enables the units. The first boot of the installed system creates a snapshot of `@`, updates GRUB and disables itself; booting into a snapshot brings up overlayfs on top of read-only btrfs.

**Stack:** Debian trixie, live-build, Calamares 3.3 (Python modules), systemd, Timeshift 24.06.6, grub-btrfs 4.14, initramfs-tools, overlayfs, btrfs.

**Spec:** `docs/superpowers/specs/2026-11-11-btrfs-timeshift-snapshots-design.md`

## Global constraints

- btrfs only: on ext4, `timeshift`, `grub-btrfs` are not installed, markers are not created, units are not enabled.
- The initial snapshot includes only `@`; `@home`, `@log`, `@cache` are not included.
- The snapshot schedule is disabled by default (`schedule_* = "false"`).
- `timeshift` is from Debian `main`; `grub-btrfs` is the vendored upstream v4.14, sha256 `4fe2f8a49b39e3e561fc51bbc5a0f81a7222c1e9ef8672e014e0ba3bedad20c6`.
- The `grub-btrfs` package version is `4.14-purad1`, `Architecture: all`, without maintainer scripts.
- Failure to install the snapshot packages does not interrupt the installation: `libcalamares.utils.warning(...)` and continuation.
- The Timeshift config uses string values `"true"/"false"` (the format of `/etc/timeshift/default.json`).
- Booting into a snapshot: `findmnt -no FSTYPE /` → `overlay`, the snapshot remains unchanged, changes are in RAM.

## Review focus

1. **Repeated snapshot when booting into a snapshot.** If you boot into the initial snapshot, it has no `first-snapshot.done`, while the unit is enabled. The script must see `findmnt -no FSTYPE / = overlay` and exit, otherwise it will create a nested snapshot.
2. **ext4 must not get artifacts.** On ext4 the module must exit before any changes; units and initramfs hooks must not appear.
3. **A package installation failure does not break the installation.** Absence of the network/package in the local repo is a warning, not a Calamares error.
4. **The `timeshift.json` format.** Boolean values as strings, `backup_device_uuid=""`, `btrfs_mode="true"`, `include_btrfs_home="false"`; otherwise Timeshift will switch into rsync mode or require a device.
5. **The apt source.** `purad-snapshots` must install packages from the local repository on the medium, without relying on the network and without mixing network `sources.list` files.

---

## Task 1: Vendoring grub-btrfs and building the `.deb`

**Files:**
- Create: `vendor/grub-btrfs/grub-btrfs-v4.14.tar.gz`
- Create: `vendor/grub-btrfs/README.md`
- Create: `vendor/grub-btrfs/build-deb.sh`
- Create: `vendor/grub-btrfs/initramfs-tools/hooks/grub-btrfs-overlay`
- Create: `vendor/grub-btrfs/initramfs-tools/scripts/local-bottom/grub-btrfs-overlay`
- Create: `scripts/test-snapshots-deb.sh`

**Interfaces:**
- `build-deb.sh <output-dir>` creates `<output-dir>/grub-btrfs_4.14-purad1_all.deb`, verifies the tarball's sha256.
- The package contains: `/etc/grub.d/41_snapshots-btrfs`, `/etc/default/grub-btrfs/config`, `/usr/bin/grub-btrfsd`, `/usr/lib/systemd/system/grub-btrfsd.service`, man8, doc, two initramfs scripts.

- [ ] **Step 1: Write a failing test `scripts/test-snapshots-deb.sh`**

The test must:
- run `vendor/grub-btrfs/build-deb.sh` into a temporary directory;
- check `dpkg-deb -f` for `Package: grub-btrfs`, `Version: 4.14-purad1`, `Architecture: all`, `Depends` contains `btrfs-progs`, `inotify-tools`, `initramfs-tools`;
- check `dpkg-deb -c` for the paths `etc/grub.d/41_snapshots-btrfs`, `etc/initramfs-tools/hooks/grub-btrfs-overlay`, `etc/initramfs-tools/scripts/local-bottom/grub-btrfs-overlay`;
- check `sh -n` on both initramfs scripts;
- print `PASS`/`FAIL` and return a code.

- [ ] **Step 2: Run the test and make sure it fails**

Run: `bash scripts/test-snapshots-deb.sh`
Expected: FAIL — there is no `vendor/grub-btrfs/build-deb.sh`.

- [ ] **Step 3: Download and pin the tarball**

Run:
```bash
mkdir -p vendor/grub-btrfs
curl -sL -o vendor/grub-btrfs/grub-btrfs-v4.14.tar.gz \
  https://github.com/Antynea/grub-btrfs/archive/refs/tags/v4.14.tar.gz
sha256sum vendor/grub-btrfs/grub-btrfs-v4.14.tar.gz
```
Expected: `4fe2f8a49b39e3e561fc51bbc5a0f81a7222c1e9ef8672e014e0ba3bedad20c6`.

- [ ] **Step 4: Write `vendor/grub-btrfs/build-deb.sh`**

Install the files manually (`install -Dm...`), not via `make install` (the latter requires root and may invoke `grub-mkconfig`). Add to `/etc/default/grub-btrfs/config` a line enabling `ro` for snapshots:
```sh
printf '\n# PuraD: boot snapshots read-only; the initramfs overlay makes them writable.\nGRUB_BTRFS_SNAPSHOT_KERNEL_PARAMETERS="ro"\n' >> "$pkgroot/etc/default/grub-btrfs/config"
```
Build with `dpkg-deb --build --root-owner-group`.

- [ ] **Step 5: Write the initramfs scripts (adaptation of PR #250)**

Hook: `manual_add_modules overlay`, `copy_exec /usr/bin/findmnt /usr/bin`, and, if present, `copy_exec` for `btrfs`.
Script `local-bottom`: find `btrfs`/`findmnt` among `/usr/bin` and `/bin`; check `findmnt -no FSTYPE -M "$rootmnt" = btrfs` and `btrfs property get "$rootmnt" ro != ro=false`; on a match, move the root, mount tmpfs and overlayfs; on error, put the root back and continue booting read-only. Without `set -e`.

- [ ] **Step 6: Write `vendor/grub-btrfs/README.md`**

State: upstream, tag, sha256, GPL-3.0 license, provenance of the initramfs scripts (PR #250, author Luis Marsano), why we vendor (there is no package in Debian, the PR is not merged), and that the scripts are adapted for usrmerge and Debian initramfs-tools.

- [ ] **Step 7: Run the test and make sure it passes**

Run: `bash scripts/test-snapshots-deb.sh`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
chmod +x vendor/grub-btrfs/build-deb.sh scripts/test-snapshots-deb.sh \
  vendor/grub-btrfs/initramfs-tools/hooks/grub-btrfs-overlay \
  vendor/grub-btrfs/initramfs-tools/scripts/local-bottom/grub-btrfs-overlay
git add vendor/grub-btrfs scripts/test-snapshots-deb.sh
git commit -m "vendor: grub-btrfs 4.14 and building the local .deb"
```

---

## Task 2: Local apt repository — timeshift, inotify-tools, grub-btrfs

**Files:**
- Modify: `config/hooks/normal/0500-purad-installer-repo.binary`
- Modify: `scripts/build.sh` (copying `vendor/`, hash)

**Interfaces:**
- During the ISO build, the hook places into `binary/pool/main` the packages `timeshift`, `inotify-tools`, `grub-btrfs_4.14-purad1_all.deb` and all missing dependencies; the `Packages`/`Release` index is updated.

- [ ] **Step 1: Write a failing check**

In `scripts/test-boot.sh`, in the `--installer` block after the `REPO_DIR_IDX` check, add a check:
```bash
for pkg in timeshift grub-btrfs inotify-tools; do
    grep -q "^Package: ${pkg}$" "${REPO_DIR_IDX}" || \
        echo "warning: local repository has no ${pkg}" >&2
done
```
Run the test on the current image: `bash scripts/test-boot.sh --installer` (or just the syntax: `bash -n scripts/test-boot.sh`). The check must warn about the missing packages.

- [ ] **Step 2: Modify hook 0500**

- Replace `PACKAGES="grub-pc grub-efi"` with groups separated by newlines: `grub-pc`, `grub-efi`, `timeshift inotify-tools` (grub-pc and grub-efi conflict, hence separate apt runs).
- Remove the cache gate `if [ -z "$(find ...)" ]`; always run `apt-get update -qq` and `apt-get -y -d install ...` for each group. Already downloaded `.deb` files are not re-downloaded by apt.
- After downloading, invoke `sh "${BUILD_DIR}/vendor/grub-btrfs/build-deb.sh" "${CACHE_DIR}/archives"`.
- Leave the copying `cp -f "${CACHE_DIR}"/archives/*.deb "${POOL}/"`.

- [ ] **Step 3: Modify `scripts/build.sh`**

After copying `profiles`, add:
```bash
rm -rf "${WORK_DIR}/vendor"
cp -a "${REPO_DIR}/vendor" "${WORK_DIR}/vendor"
```
Add `vendor` to `BINARY_HASH`:
```bash
BINARY_HASH="$(hash_paths config/common config/bootloaders config/includes.binary profiles VERSION vendor)"
```

- [ ] **Step 4: Check the repository build without a full ISO**

```bash
mkdir -p builds/trixie/vendor && cp -a vendor/. builds/trixie/vendor/
podman run --rm --privileged -v "$PWD/builds/trixie:/work:Z" -w /work/binary \
  -e LB_DISTRIBUTION=trixie -e LB_ARCHITECTURES=amd64 \
  localhost/purad-builder:trixie \
  sh /work/config/hooks/normal/0500-purad-installer-repo.binary
```
Expected: `builds/trixie/binary/pool/main` contains `timeshift_*.deb`, `inotify-tools_*.deb`, `grub-btrfs_4.14-purad1_all.deb`; `dists/trixie/main/binary-amd64/Packages` contains entries about them.

- [ ] **Step 5: Commit**

```bash
git add config/hooks/normal/0500-purad-installer-repo.binary scripts/build.sh scripts/test-boot.sh
git commit -m "repo: timeshift, inotify-tools and grub-btrfs on the medium"
```

---

## Task 3: Calamares module `purad-snapshots`

**Files:**
- Create: `config/includes.chroot/usr/lib/x86_64-linux-gnu/calamares/modules/purad-snapshots/main.py`
- Create: `.../purad-snapshots/module.desc`
- Modify: `config/includes.chroot/etc/calamares/settings.conf`
- Create: `scripts/test-snapshots-module.py`

**Interfaces:**
- `target_root_fs(root, partitions) -> str`: `"btrfs"`, `"ext4"` or `""`; first looks for `partitions[*].mountPoint == "/"`, then `etc/fstab` with `subvol=/@`.
- `write_timeshift_config(root)`: writes `etc/timeshift/timeshift.json` based on `default.json`.
- `run()`: on non-btrfs — debug and `None`; on btrfs — apt install, config, marker, `systemctl enable`.

- [ ] **Step 1: Write a failing test `scripts/test-snapshots-module.py`**

The test substitutes a stub `libcalamares` into `sys.modules`, imports `main.py` by path and checks:
- a btrfs partition → `target_root_fs(...) == "btrfs"`;
- an ext4 partition → `"ext4"`;
- without `partitions`, fstab with `subvol=/@` → `"btrfs"`;
- `write_timeshift_config` writes `backup_device_uuid == ""`, `btrfs_mode == "true"`, `include_btrfs_home == "false"`, `do_first_run == "false"`, all `schedule_* == "false"`.

- [ ] **Step 2: Run the test and make sure it fails**

Run: `python3 scripts/test-snapshots-module.py`
Expected: FAIL — the module has not been created yet.

- [ ] **Step 3: Implement `main.py`**

Logic:
```python
def target_root_fs(root, partitions):
    for part in partitions or []:
        if part.get("mountPoint") == "/":
            return (part.get("fs") or "").lower()
    try:
        with open(os.path.join(root, "etc/fstab")) as f:
            for line in f:
                fields = line.split()
                if len(fields) >= 4 and fields[1] == "/" and fields[2] == "btrfs":
                    opts = fields[3]
                    if "subvol=/@" in opts or "subvol=@" in opts:
                        return "btrfs"
    except OSError:
        pass
    return ""
```
`install_packages(root)`:
- if `etc/apt/sources.list.d/debian-live-media.list` exists, add `-o Dir::Etc::sourcelist=/etc/apt/sources.list.d/debian-live-media.list -o Dir::Etc::sourceparts=-` (install only from the medium);
- `apt-get update`, then `apt-get install -y --no-install-recommends timeshift grub-btrfs pkexec` via `libcalamares.utils.target_env_call(["/usr/bin/env", "DEBIAN_FRONTEND=noninteractive", "apt-get", ...])`;
- on a non-zero code — `RuntimeError`.

`write_timeshift_config(root)` — reads `etc/timeshift/default.json`, updates the keys, writes `timeshift.json`, `chmod 0644`.

`mark_btrfs(root)` — creates an empty `var/lib/purad/btrfs`.

`enable_units()` — `systemctl enable purad-first-snapshot.service grub-btrfsd.service`; errors — warning.

`run()` — `try/except`, on any error `libcalamares.utils.warning(...)`, return `None`.

- [ ] **Step 4: Create `module.desc`**

```yaml
type:       "job"
interface:  "python"
name:       "purad-snapshots"
script:     "main.py"
requiredModules: [ "partition", "mount" ]
```

- [ ] **Step 5: Add the module to `settings.conf`**

After `- packages` add `- purad-snapshots` (before `plymouthcfg`/`initramfscfg`/`initramfs`).
**Important:** the working tree already has uncommitted user edits in `settings.conf` (purad-session) and `docs/PLAN.md`. Before Task 3, stash them and restore only after the Task 5 commit:
```bash
git stash push -- config/includes.chroot/etc/calamares/settings.conf docs/PLAN.md
# ... Task 3, Task 4, Task 5 (edits and commits) ...
git stash pop
```

- [ ] **Step 6: Run the test**

Run: `python3 scripts/test-snapshots-module.py && python3 -m py_compile config/includes.chroot/usr/lib/x86_64-linux-gnu/calamares/modules/purad-snapshots/main.py`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add config/includes.chroot/usr/lib/x86_64-linux-gnu/calamares/modules/purad-snapshots \
  config/includes.chroot/etc/calamares/settings.conf scripts/test-snapshots-module.py
git commit -m "calamares: purad-snapshots module for btrfs"
```

---

## Task 4: First snapshot and grub-btrfsd

**Files:**
- Create: `config/includes.chroot/usr/lib/systemd/system/purad-first-snapshot.service`
- Create: `config/includes.chroot/usr/lib/purad/first-snapshot`
- Create: `config/includes.chroot/etc/systemd/system/grub-btrfsd.service.d/10-purad-timeshift.conf`

**Interfaces:**
- The `purad-first-snapshot.service` unit is enabled only by the module on btrfs; on first boot it creates a snapshot and disables itself.
- The drop-in overrides `ExecStart` to `--syslog --timeshift-auto`.

- [ ] **Step 1: Write a failing check**

Add to `scripts/test-snapshots-deb.sh` (or a separate `scripts/test-snapshots-static.sh`) checks:
- `test -f` for all three files;
- `sh -n` for `first-snapshot`;
- `grep -q 'ConditionPathExists=/var/lib/purad/btrfs'` in the unit;
- `grep -q 'timeshift --create --btrfs --scripted --yes'` in the script;
- `grep -q 'findmnt -no FSTYPE /'` in the script (protection against a nested snapshot);
- `grep -q 'ExecStart=/usr/bin/grub-btrfsd --syslog --timeshift-auto'` in the drop-in.

- [ ] **Step 2: Run and make sure it fails**

Expected: FAIL — the files are absent.

- [ ] **Step 3: Create the unit**

```ini
[Unit]
Description=PuraD: initial btrfs snapshot
After=local-fs.target
Before=grub-btrfsd.service
ConditionPathExists=/var/lib/purad/btrfs
ConditionPathExists=!/var/lib/purad/first-snapshot.done

[Service]
Type=oneshot
ExecStart=/usr/lib/purad/first-snapshot
RemainAfterExit=yes
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 4: Create `first-snapshot`**

```sh
#!/bin/sh
set -u

[ -f /var/lib/purad/btrfs ] || exit 0
[ -f /var/lib/purad/first-snapshot.done ] && exit 0
command -v timeshift >/dev/null 2>&1 || exit 0

# Booting into a snapshot: the root is overlayfs. The snapshot already exists, so one must not be created.
[ "$(findmnt -no FSTYPE / 2>/dev/null)" = "btrfs" ] || exit 0

# The root must be a mutable btrfs (not a read-only snapshot).
[ "$(btrfs property get / ro 2>/dev/null)" = "ro=false" ] || exit 0

# Protection against marker loss: has the snapshot already been created?
if timeshift --list --scripted 2>/dev/null | grep -Fq "PuraD: initial snapshot"; then
    touch /var/lib/purad/first-snapshot.done
    systemctl disable purad-first-snapshot.service >/dev/null 2>&1 || true
    exit 0
fi

if ! timeshift --create --btrfs --scripted --yes \
        --comments "PuraD: initial snapshot"; then
    echo "purad-first-snapshot: timeshift --create failed" >&2
    exit 1
fi

# GRUB menu with snapshot entries; an error does not cancel the already created snapshot.
update-grub >/dev/null 2>&1 || echo "purad-first-snapshot: update-grub failed" >&2

touch /var/lib/purad/first-snapshot.done
systemctl disable purad-first-snapshot.service >/dev/null 2>&1 || true
exit 0
```

- [ ] **Step 5: Create the drop-in**

```ini
[Service]
ExecStart=
ExecStart=/usr/bin/grub-btrfsd --syslog --timeshift-auto
```

- [ ] **Step 6: Run the check**

Run: `bash scripts/test-snapshots-deb.sh`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
chmod +x config/includes.chroot/usr/lib/purad/first-snapshot
git add config/includes.chroot/usr/lib/systemd/system/purad-first-snapshot.service \
  config/includes.chroot/usr/lib/purad/first-snapshot \
  config/includes.chroot/etc/systemd/system/grub-btrfsd.service.d/10-purad-timeshift.conf \
  scripts/test-snapshots-deb.sh
git commit -m "systemd: first btrfs snapshot and grub-btrfsd"
```

---

## Task 5: Documentation

**Files:**
- Modify: `docs/PLAN.md`
- Modify: `README.md`

- [ ] **Step 1: Add stage 10 to `docs/PLAN.md`**

Describe: Timeshift + grub-btrfs only on btrfs; initial snapshot on first boot; overlayfs in initramfs for booting into a snapshot; vendoring grub-btrfs as an explicit caveat from "clean Debian"; absence of `@var`; absence of a schedule by default.

- [ ] **Step 2: Add a section to `README.md`**

User-facing text: "btrfs snapshots" — how to open Timeshift, how to boot into a snapshot from GRUB, that changes in a snapshot are not saved, that `@home` is not included in the initial snapshot.

- [ ] **Step 3: Commit**

```bash
git add docs/PLAN.md README.md
git commit -m "docs: btrfs snapshots and booting into them"
```
**Important:** `docs/PLAN.md` contains uncommitted user edits (purad-session); they must be in the stash (see Task 3, Step 5) and restored after the commit.

---

## Task 6: Integration check

- [ ] **Step 1: Quick tests**

```bash
bash scripts/test-snapshots-deb.sh
python3 scripts/test-snapshots-module.py
python3 -m py_compile config/includes.chroot/usr/lib/x86_64-linux-gnu/calamares/modules/purad-snapshots/main.py
bash -n scripts/build.sh scripts/test-boot.sh
sh -n config/includes.chroot/usr/lib/purad/first-snapshot
```
Expected: everything PASS.

- [ ] **Step 2: Build the ISO**

Run: `make iso TARGET=trixie`
Expected: the build completes; `builds/trixie/binary/pool/main` contains `timeshift_*.deb`, `inotify-tools_*.deb`, `grub-btrfs_4.14-purad1_all.deb`; `Packages` contains entries about them.

- [ ] **Step 3: Installation on btrfs (qemu)**

Run: `make run-install TARGET=trixie`
In Calamares: btrfs, installation. After installation:
```bash
dpkg -l timeshift grub-btrfs
ls /etc/initramfs-tools/hooks/grub-btrfs-overlay
ls /etc/initramfs-tools/scripts/local-bottom/grub-btrfs-overlay
lsinitramfs /boot/initrd.img-$(uname -r) | grep grub-btrfs-overlay
systemctl status grub-btrfsd --no-pager
systemctl status purad-first-snapshot --no-pager
timeshift --list
grep -c 'timeshift-btrfs' /boot/grub/grub-btrfs.cfg
```
Expected: the packages are installed; the scripts are in the initramfs; `grub-btrfsd` active; `purad-first-snapshot` done; `timeshift --list` shows a snapshot with the comment `PuraD: initial snapshot`; `grub-btrfs.cfg` contains a snapshot entry.

- [ ] **Step 4: Booting into a snapshot (qemu)**

Reboot, in the GRUB menu select the snapshot. In the system:
```bash
findmnt -no FSTYPE /
mount | grep -E 'overlay|btrfs'
```
Expected: `overlay`; `mount` shows `lowerdir` with the snapshot path; the Plasma session starts; a created file disappears after a reboot.

- [ ] **Step 5: Installation on ext4 (qemu)**

Repeat the installation with ext4. Expected: `dpkg -l timeshift grub-btrfs` — not installed; no initramfs hooks; `systemctl is-enabled grub-btrfsd purad-first-snapshot` — not-found/disabled; `timeshift` is absent.

- [ ] **Step 6: Final commit (if there were edits as a result of the check)**

```bash
git add -A
git commit -m "test: checks for btrfs snapshots and booting into them"
```
