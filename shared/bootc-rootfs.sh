#!/usr/bin/env bash
#
# SPDX-License-Identifier: Apache-2.0
#
# From bootcrew/mono and jmarrero/ubuntu-bootc (both Apache-2.0), modified by the
# Project DeskOS. What changed is recorded in README.md, "What we changed from
# upstream, and why". The two `printf`s that write bootc-base-dirs.conf end in a
# newline on purpose: without it the last line of one and the first of the next are
# concatenated and systemd skips both.

set -xeuo pipefail

rm -rf /boot /home /root /usr/local /srv /opt /mnt /var

mkdir -p /sysroot /boot /usr/lib/ostree /var /home /root /opt /mnt /srv

# Only /ostree and /usr/local remain as symlinks; /home /root /opt /mnt /srv
# are real directories backed by systemd bind mount units for snap compatibility
# (snap-confine can't rbind-mount through symlinks on composefs)
ln -sT sysroot/ostree /ostree && ln -sT ../var/usrlocal /usr/local

printf "d /var/lib/snapd/snap 0755 root root -\n" >> /usr/lib/tmpfiles.d/bootc-base-dirs.conf

echo "$(for dir in opt home srv mnt usrlocal ; do echo "d /var/$dir 0755 root root -" ; done)" | tee -a "/usr/lib/tmpfiles.d/bootc-base-dirs.conf"

printf "d /var/roothome 0700 root root -\nd /run/media 0755 root root -\n" | tee -a "/usr/lib/tmpfiles.d/bootc-base-dirs.conf"

printf '[composefs]\nenabled = yes\n[sysroot]\nreadonly = true\n' | tee "/usr/lib/ostree/prepare-root.conf"
