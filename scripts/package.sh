#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
version=v1.1.1
name="lite-vps-ops-$version.tar.gz"
dist="$root/dist"
mkdir -p "$dist"
rm -f -- "$dist"/lite-vps-ops-v*.tar.gz "$dist"/lite-vps-ops-v*.tar.gz.sha256 \
  "$dist/checksums.txt" "$dist/bootstrap.sh" "$dist/release-notes.md"
tar -czf "$dist/$name" -C "$root" lite-vps-ops lib profiles
cp "$root/bootstrap.sh" "$dist/bootstrap.sh"
(cd "$dist" && sha256sum "$name" > "$name.sha256" && sha256sum "$name" bootstrap.sh > checksums.txt)
cp "$root/RELEASE_NOTES.md" "$dist/release-notes.md"
printf 'Packaged %s\n' "$name"
