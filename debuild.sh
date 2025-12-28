#!/usr/bin/env bash

set -eu

status() {
    echo -e "\e[1;32m$1\e[0m"
}

DEBIAN_VER="trixie"

WORKING_DIR="$HOME/debuild-tmp"
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_DIR="${SCRIPT_PATH%/*}"
REPO_DIR="$SCRIPT_DIR/repo"
PWD_0="$(pwd)"

. "$SCRIPT_DIR/debuild.conf"

if [ ! -d "$REPO_DIR" ]; then
    echo "Repository directory $REPO_DIR not found!" >&2
    exit 1
fi

debuild_files=("$REPO_DIR"/*.debuild)
if [ ${#debuild_files[@]} -eq 0 ]; then
    echo "No .debuild files found in $REPO_DIR!" >&2
    exit 1
fi

if [ -d "$WORKING_DIR" ]; then
    docker run --rm -v "$WORKING_DIR":/del "debian:$DEBIAN_VER" sh -c "rm -r /del/*"
    rmdir "$WORKING_DIR"
fi
mkdir -p "$WORKING_DIR"
mkdir -p "$WORKING_DIR/out"

n=1
repo_updated=0
for debuild_file in "${debuild_files[@]}"; do
    _filename="${debuild_file##*/}"
    package_name="${_filename%.*}"

    source_dir="$WORKING_DIR/source/$package_name"
    done_dir="$WORKING_DIR/done/$package_name"
    mkdir -p "$source_dir"
    mkdir -p "$done_dir"

    # shellcheck disable=SC1090
    source "$debuild_file"

    # Download & unpack sources on host machine
    status "[$n/${#debuild_files[@]}] Getting sources for $package_name ..."
    cd "$source_dir"
    new_version=$("${package_name}__version-pre")
    if [ -n "$new_version" ]; then
        dest_file="$APT_REPO_DIR/${package_name}_${new_version}_amd64.deb"
        if [ -f "$dest_file" ]; then
            status "[$n/${#debuild_files[@]}] Package $package_name version $new_version already built, skipping ..."
            ((n++))
            continue
        fi
    fi

    "${package_name}__get-sources"

    status "[$n/${#debuild_files[@]}] Building package $package_name ..."
    docker run --rm -v "$source_dir":/src -v "$done_dir":/out -v "$REPO_DIR:/debuild" -it "debian:$DEBIAN_VER" bash -c "
        set -eu
        . /debuild/$_filename
        cd /src
        ${package_name}__build /out
        ${package_name}__version > /src/VERSION
    "

    export version=$(cat "$source_dir/VERSION")
    dest_file="$APT_REPO_DIR/${package_name}_${version}_amd64.deb"
    if [ -f "$dest_file" ]; then
        status "[$n/${#debuild_files[@]}] Package $package_name version $version already built, skipping rebuild ..."
        ((n++))
        continue
    fi

    ready_deb_file="$done_dir/${package_name}_${version}_amd64.deb"
    if [ -f "$ready_deb_file" ]; then
        status "[$n/${#debuild_files[@]}] Copying ready .deb for $package_name ..."
        cp "$ready_deb_file" "$WORKING_DIR/out/"

    else
        # Building package metadata
        status "[$n/${#debuild_files[@]}] Building metadata for $package_name ..."
        export size=$(du -d0 "$done_dir" | awk '{ print $1 }')
        md5sums=$(cd "$done_dir" && find . -type f -exec md5sum {} \;)
        control_file_skeleton="$REPO_DIR/$package_name.control"
        mkdir -p "$done_dir/DEBIAN"
        envsubst < "$control_file_skeleton" > "$done_dir/DEBIAN/control"
        echo "$md5sums" | sed -e 's/\s\s\.\//  /g' > "$done_dir/DEBIAN/md5sums"

        # Build .deb package
        status "[$n/${#debuild_files[@]}] Building .deb for $package_name ..."
        cd "$done_dir"
        fakeroot dpkg-deb --build . "$WORKING_DIR/out/${package_name}_${version}_amd64.deb"
    fi

    cd "$PWD_0"
    status "[$n/${#debuild_files[@]}] Finished building $package_name."
    repo_updated=1
    ((n++))
done

if [ "$repo_updated" -eq 1 ]; then
    status "Copying packages to the repository ..."
    cd "$WORKING_DIR/out"
    rsync -avzh --no-g --progress ./* "$APT_REPO_DIR/"
    cd "$PWD_0"

    status "Updating repository metadata ..."
    "$SCRIPT_DIR/update-repo.sh"
else
    status "No new packages were built, repository update skipped."
fi

status "Cleaning up ..."
docker run --rm -v "$WORKING_DIR":/del "debian:$DEBIAN_VER" sh -c "rm -r /del/*"
rmdir "$WORKING_DIR"

status "All done!"
