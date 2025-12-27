#!/usr/bin/env bash

set -eu

SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_DIR="${SCRIPT_PATH%/*}"
. "$SCRIPT_DIR/debuild.conf"

cd "$APT_REPO_DIR"

dpkg-scanpackages -m . > Packages
gzip -9c < Packages > Packages.gz

PKGS=$(wc -c Packages)
PKGS_GZ=$(wc -c Packages.gz)

cat <<EOF > Release
Architectures: all
Date: $(date -R -u)
MD5Sum:
 $(md5sum Packages  | cut -d" " -f1) $PKGS
 $(md5sum Packages.gz  | cut -d" " -f1) $PKGS_GZ
SHA1:
 $(sha1sum Packages  | cut -d" " -f1) $PKGS
 $(sha1sum Packages.gz  | cut -d" " -f1) $PKGS_GZ
SHA256:
 $(sha256sum Packages | cut -d" " -f1) $PKGS
 $(sha256sum Packages.gz | cut -d" " -f1) $PKGS_GZ
EOF

gpg --yes -u "$GPG_KEY" --sign -bao Release.gpg Release
