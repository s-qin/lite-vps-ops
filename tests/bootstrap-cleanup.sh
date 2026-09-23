#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
mkdir -p "$fixture/bin" "$fixture/payload" "$fixture/staging"

cat >"$fixture/payload/lite-vps-ops" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'fixture command completed\n'
EOF
chmod +x "$fixture/payload/lite-vps-ops"
tar -czf "$fixture/archive.tar.gz" -C "$fixture/payload" lite-vps-ops
(cd "$fixture" && sha256sum archive.tar.gz > archive.tar.gz.sha256)

cat >"$fixture/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output=
url=
while (($#)); do
  case "$1" in
    -o) output=$2; shift 2 ;;
    --output) output=$2; shift 2 ;;
    -*) shift ;;
    *) url=$1; shift ;;
  esac
done
[[ -n $output && -n $url ]]
if [[ $url == *.sha256 ]]; then
  sed 's/archive.tar.gz/lite-vps-ops-v1.0.0.tar.gz/' "$LVO_TEST_SHA" >"$output"
else
  cp "$LVO_TEST_ARCHIVE" "$output"
fi
EOF
chmod +x "$fixture/bin/curl"

PATH="$fixture/bin:$PATH" \
TMPDIR="$fixture/staging" \
LVO_TEST_ARCHIVE="$fixture/archive.tar.gz" \
LVO_TEST_SHA="$fixture/archive.tar.gz.sha256" \
  bash "$root/bootstrap.sh" --version >/dev/null

if find "$fixture/staging" -mindepth 1 -print -quit | grep -q .; then
  echo 'bootstrap staging directory was not cleaned' >&2
  exit 1
fi
printf 'bootstrap cleanup PASS\n'
