#!/usr/bin/env bash
set -euo pipefail
VERSION=${LVO_VERSION:-v0.1.0}
REPO=${LVO_REPO:-s-qin/lite-vps-ops}
[[ $VERSION =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid version' >&2; exit 2; }
[[ $REPO == s-qin/lite-vps-ops ]] || { echo 'Invalid repository' >&2; exit 2; }
for command_name in curl sha256sum tar mktemp; do command -v "$command_name" >/dev/null || { echo "Missing: $command_name" >&2; exit 2; }; done
STAGING=$(mktemp -d)
trap 'rm -rf -- "$STAGING"' EXIT
ASSET="lite-vps-ops-$VERSION.tar.gz"
BASE="https://github.com/$REPO/releases/download/$VERSION"
curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 "$BASE/$ASSET" -o "$STAGING/$ASSET"
curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 "$BASE/$ASSET.sha256" -o "$STAGING/$ASSET.sha256"
(cd "$STAGING" && sha256sum -c "$ASSET.sha256")
tar -tzf "$STAGING/$ASSET" | while IFS= read -r member; do
  case "$member" in /*|..|../*|*/..|*/../*) echo 'Unsafe archive path' >&2; exit 1 ;; esac
done
mkdir "$STAGING/run"
tar -xzf "$STAGING/$ASSET" -C "$STAGING/run" --no-same-owner --no-same-permissions
"$STAGING/run/lite-vps-ops" "$@"
