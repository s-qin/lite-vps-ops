#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=tests/helpers.sh
. "$root/tests/helpers.sh"
make_fixture
trap 'rm -rf -- "$fixture"' EXIT
load_fixture

[[ $PROFILE == tiny ]]
[[ $JOURNAL_MIB == 64 ]]
[[ $SWAP_MIB == 512 ]]
[[ $(json_escape $'a"b\\c\n') == 'a\"b\\c\n' ]]

managed_paths_init
for file in "${MANAGED_PATHS[@]}"; do
  [[ $(file_status "$file") == NOT_CONFIGURED ]]
  mkdir -p "$(dirname "$file")"
  desired_config "$file" > "$file"
  [[ $(file_status "$file") == ALREADY_COMPLIANT ]]
done
printf 'foreign\n' > "${MANAGED_PATHS[0]}"
[[ $(file_status "${MANAGED_PATHS[0]}") == CONFLICT ]]

checks_reset
add_check 0 one PASS true ok
add_check 6 advisory WARN false advisory
checks_blocking_ok
add_check 3 required WARN true missing
if checks_blocking_ok; then echo 'blocking WARN unexpectedly passed' >&2; exit 1; fi
checks_json | python -m json.tool >/dev/null
printf 'PASS unit: profiles, desired state, ownership, status model, JSON\n'
