#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=tests/helpers.sh
. "$root/tests/helpers.sh"
make_fixture
trap 'rm -rf -- "$fixture"' EXIT
load_fixture
before=$(find "$fixture" -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | awk '{print $1}')
dry_run_plan >/tmp/lvo-dry-run.$$
after=$(find "$fixture" -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | awk '{print $1}')
rm -f -- /tmp/lvo-dry-run.$$
[[ $before == "$after" ]]
[[ ! -e $fixture/var/lib/lite-vps-ops/maintenance.lock ]]
printf 'PASS dry-run: fixture and state unchanged\n'
