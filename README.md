# deskos-ubuntu-base

**Ubuntu 26.04 LTS as a bootc image with GNOME**, maintained by the DeskOS project.

**Support tier: `organization`.** There is no Canonical support for the result: Canonical does not
publish an Ubuntu bootc base, so this one is maintained by us. See "Provenance" and "Verified
status" to know what was tested and what was not.

This repository is **not DeskOS Core**. It is the *base* DeskOS compiles onto: the Ubuntu bootc
engineering (kernel, ostree/composefs, snapd, desktop) that someone has to maintain precisely
because **Canonical publishes no official bootc base**.

## Provenance and license

Fork of [`jmarrero/ubuntu-bootc`](https://github.com/jmarrero/ubuntu-bootc), taken at commit
`7dd974209f2278307e13be4dc9e449020802ae64`. **Apache-2.0** license (see `LICENSE`, from upstream).

The scripts under `shared/` share lineage with [`bootcrew/mono`](https://github.com/bootcrew/mono)
(bootcrew's Ubuntu recipe), also Apache-2.0.

Thanks to Joseph Marrero (Red Hat) for the original recipe, and to bootcrew for the bootc
integration work on Ubuntu.

## What we changed from upstream, and why

Everything below is **measured** (the recipe was built, installed to disk and booted):

1. **`libclang-dev` in the builder stage.** The build was broken at HEAD: `selinux-sys` uses
   bindgen and without libclang it fails with `Unable to find libclang` while generating manpages.
   It was made worse by `shared/build.sh` cloning `bootc` from **HEAD with no pin**: a floating
   dependency broke a build that used to be green. **Now pinned** to a `bootc` commit
   (`1a04bf23b438ec476c1cec31adf0d56312e5be5b`). Note: release `v1.17.1` **does not compile** in this
   environment (`make bin` fails with exit 101) while that commit does; that is why a commit is
   pinned rather than a tag.
2. **`kdump-tools` excluded** (`kdump-tools-`). It is a *Recommends* of `ubuntu-desktop-minimal`
   and its postinst hook generates a crash-dump initramfs which, inside a container build, dies
   with `mkinitramfs: failed to determine device for /`, breaking the kernel's configure step.
3. **Stock 26.04 kernel, without the questing 6.17 pin.** The upstream workaround targeted the
   Linux 7.0 fsverity regression; Ubuntu already merged stable v7.0.7 into `7.0.0-38.38`
   (`ovl: fix verity lazy-load guard broken by fsverity_active()`), and booting with the stock
   kernel was verified: composefs with `verity=require` boots fine.
4. **flatpak >= 1.17 from the Flatpak team PPA.** The 26.04 archive ships **1.16.6** and
   `flatpak preinstall` does not exist, so DeskOS's preinstallation mechanism cannot materialize.
   The PPA publishes `1.18.4-1~flatpak1~26.04.1` and `flatpak preinstall` works.
   **Caveat: it is a third-party PPA — a supply-chain decision, not Canonical's archive.**
5. **Locale generated in the image** (`es_EC.UTF-8`) plus timezone and keyboard. It cannot be done
   at runtime: `/usr/lib/locale` lives under a read-only `/usr`.
   **Design pending: locale, timezone and keyboard must be selectable per region and per user, not
   fixed for the whole fleet.**
6. **First-login wizard suppressed** (`gnome-initial-setup` markers).
7. **`/var` skeleton that `rm -rf /var` destroys.** Packages install directories under `/var`
   (snapd: `apparmor/snap-confine`, `void`, `hostfs`, `firstboot`, ...; ubuntu-advantage:
   `/var/lib/ubuntu-advantage`) and the recipe used to delete them. Measured effects:
   `apparmor.service` failed on first boot, and **`snap run firefox` died** with `cannot create
   void directory: /var/lib/snapd/void: Permission denied`. They are restored in the image,
   respecting the **0111** mode of `void` (it is a "void" used as a mount point, on purpose). With
   that: `apparmor` active on first boot and **snap Firefox running**. The mechanism is general:
   before the wipe the `/var` skeleton is saved (directories only, with mode and owner) and
   restored afterwards.
8. **`/var/lib/flatpak` excluded from that restore.** Restoring directories only leaves
   half-initialized what needs to be initialized coherently: with `/var/lib/flatpak/repo` present
   but missing its `config` file, `flatpak preinstall` fails with `opening repo: openat(config): No
   such file or directory`. If the directory does not exist, flatpak creates the whole thing.
   **Measured: with the exclusion, DeskOS's unit installs the app.**
9. **The package database is image content, not state** (ADR 0015). `rm -rf /var` took
   `/var/lib/dpkg` with it, so a derived image installed blindly: installing `curl` pulled **35
   packages, 34 of them already on disk**, because dpkg knew nothing. The database is now copied into
   `/usr/lib/sysimage/dpkg` before the wipe (the RPM family keeps its own at
   `/usr/lib/sysimage/rpm`), with `admindir=` in `/etc/dpkg/dpkg.cfg.d/` and `Dir::State::status` in
   `/etc/apt/apt.conf.d/`. **Measured: `dpkg -l` reports 1519 packages, `curl` resolves to 1 package,
   `jq` to 0, and a derived `FROM` this base installing `jq` reports "already the newest version".**
   The database lives in `/usr`, so on a booted machine it is readable but not writable: `apt` is a
   build-time tool here, not a way to change a running workstation.

## Verified status

| what | result |
|---|---|
| Build | OK (with the libclang fix) |
| `bootc container lint` | 12 checks, 3 warnings |
| Install to disk (`--composefs-backend`) | OK |
| Boot with `verity=require` | OK |
| GNOME + autologin | OK |
| `bootc switch` / `rollback` | OK. Note: rollback **needs two reboots** (the operation runs at the end of boot; the next boot uses the previous image). `/var` and `/etc` persist in both directions. |
| flatpak: runs apps | OK (bwrap under the `unpriv_bwrap` profile) |
| DeskOS `FlatpakSet` (preinstall on first boot) | OK with flatpak 1.18.4 |
| snap: trivial apps (`hello-world`) | OK |
| **snap: Firefox** | **OK** — `/snap/firefox/9057/usr/lib/firefox/firefox` running, 18 AppArmor profiles, UI in Spanish |
| `apparmor.service` on first boot | OK |
| **Package database** | OK — `dpkg -l` reports 1519 packages from `/usr/lib/sysimage/dpkg`; a derived image installs incrementally (`curl`: 1 package, `jq`: 0) |
| Secure boot | not verified (the kernel is signed, `systemd-boot` is not) |
| Intune / CrowdStrike / VPN | **not verifiable outside a real corporate environment** |

## Known blockers

- **Home outside `/home`.** Snap requires the home under `/home`, and the bootc/ostree layout uses
  `/var/home`. Since `/home` is a bind mount of `/var/home`, setting the user's home to `/home/poc`
  solves it without moving files. **Pending: decide it in the recipe, not by hand in the VM.**
- **Secure boot**: the stock kernel is signed, but the install uses `systemd-boot`, which is not.
  It requires a signed shim+grub chain or custom keys.
- **GPU inside the flatpak sandbox**: there were MESA/EGL errors (`failed to create dri2 screen`),
  i.e. software rendering.
- **The ESP is not where `bootctl` looks for it.** At boot we see
  `bootctl: Couldn't find EFI system partition, skipping.`, so bootc cannot manage the EFI boot
  entries. Boot order still works (through bootc's own mechanism), but this deserves investigation:
  on real hardware with secure boot it matters.
- **Upstream tmpfiles syntax bug**: `d ... root root -` produces `Invalid age '-'` (lines of type
  `d` do not take an age field like that). It shows up on every boot.

## Operational note (for whoever builds this)

- **Compiling `bootc` from scratch is heavy.** With 3 VMs running, `rustc` died with a **SIGSEGV**
  during LTO; with the VMs shut down it compiled fine. Free memory before building.
- **It consumes tens of GB.** The lab reached 100% disk with accumulated images and test disks;
  clean up (`podman rmi`, test disks) before each cycle.
- Changing the `bootc` pin (or any builder input) invalidates the cache: expect a long build.

## Build and test

    podman build -f Containerfile -t ubuntu-bootc:local .

    # layers must end up compressed: the composefs import rejects `vnd.oci.image.layer.v1.tar`
    skopeo inspect --raw containers-storage:localhost/ubuntu-bootc:local | python3 -c \
      "import json,sys;from collections import Counter;print(Counter(l['mediaType'] for l in json.load(sys.stdin)['layers']))"

    truncate -s 30G disk.raw
    sudo podman run --rm --privileged --pid=host --security-opt label=type:unconfined_t \
      -v /dev:/dev -v /var/lib/containers:/var/lib/containers -v $PWD:/output \
      ubuntu-bootc:local bootc install to-disk --via-loopback /output/disk.raw \
      --composefs-backend --bootloader systemd --wipe --filesystem ext4 --allow-missing-verity

    # boot with a virtual GPU: without it there is no compositor
    qemu-kvm -machine q35,accel=kvm -cpu host -m 6G -smp 4 \
      -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/ovmf/OVMF_CODE.fd \
      -drive if=pflash,format=raw,file=OVMF_VARS.fd \
      -drive file=disk.raw,format=raw,if=virtio \
      -vga none -device virtio-vga -vnc 127.0.0.1:5 \
      -monitor unix:mon.sock,server,nowait

## Context

This base exists because DeskOS compiles artifacts onto each platform's bootc base, and Ubuntu has
no official one. What was verified, with what evidence, and what is still pending, is in "Verified
status" and "Known blockers" above.
