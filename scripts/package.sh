#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
version=v0.1.0
name="lite-vps-ops-$version.tar.gz"
mkdir -p "$root/dist"
tar -czf "$root/dist/$name" -C "$root" lite-vps-ops lib profiles
(cd "$root/dist" && sha256sum "$name" > "$name.sha256")
cp "$root/bootstrap.sh" "$root/dist/bootstrap.sh"
printf 'Packaged %s\n' "$name"
