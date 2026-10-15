#!/usr/bin/env bash

set -xeuo pipefail

# Explicit pin of the bootc source.
#
# This used to clone HEAD with no pin, and that broke this build once: a floating dependency
# (selinux-sys -> bindgen) started requiring libclang, which the builder stage did not have. The
# symptom was `make manpages` failing with
# `cargo run --features=docgen -- internals dump-cli-json` and exit 101.
#
# A COMMIT is pinned, not a tag: measured, release v1.17.1 does not compile in this environment
# (`make bin` fails with exit 101) while this commit from main does. Moving this pin means
# rebuilding, installing to disk and re-testing (boot, snap, flatpak, update).
BOOTC_COMMIT="${BOOTC_COMMIT:-1a04bf23b438ec476c1cec31adf0d56312e5be5b}"

git init .
git remote add origin https://github.com/bootc-dev/bootc.git
git fetch --depth 1 origin "$BOOTC_COMMIT"
git checkout -q FETCH_HEAD

make bin install-all DESTDIR=/output
