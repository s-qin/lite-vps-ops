#!/usr/bin/env bash
set -euo pipefail
VERSION=${LVO_VERSION:-v1.0.0}
REPO=${LVO_REPO:-s-qin/lite-vps-ops}
[[ $VERSION =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid version' >&2; exit 2; }
[[ $REPO == s-qin/lite-vps-ops ]] || { echo 'Invalid repository' >&2; exit 2; }
missing=false
for command_name in curl sha256sum tar mktemp; do command -v "$command_name" >/dev/null || missing=true; done
if [[ $missing == true ]]; then
  command -v apt-get >/dev/null || { echo 'Missing bootstrap dependencies and apt-get is unavailable' >&2; exit 2; }
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then privilege=();
  elif command -v sudo >/dev/null && sudo -n true >/dev/null 2>&1; then privilege=(sudo -n);
  else echo 'Bootstrap dependencies require root or passwordless sudo' >&2; exit 2; fi
  "${privilege[@]}" apt-get update
  "${privilege[@]}" apt-get install -y --no-install-recommends ca-certificates coreutils curl tar
fi
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
