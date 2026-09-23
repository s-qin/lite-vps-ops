#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=tests/helpers.sh
. "$root/tests/helpers.sh"
make_fixture
trap 'rm -rf -- "$fixture"' EXIT
load_fixture
managed_paths_init

transaction_begin
snapshot_all
atomic_write_managed "${MANAGED_PATHS[0]}" 0644
TX_ROLLBACK=true
rollback_all
[[ ! -e ${MANAGED_PATHS[0]} ]]
TX_ACTIVE=false
transaction_release_lock

desired_config "${MANAGED_PATHS[0]}" > "${MANAGED_PATHS[0]}"
transaction_begin
snapshot_all
printf '%s\n' "$LVO_MANAGED_MARKER" 'changed' > "${MANAGED_PATHS[0]}"
printf 'tampered-backup\n' > "$TX_DIR/backups/1"
if rollback_all; then echo 'tampered backup unexpectedly restored' >&2; exit 1; fi
[[ $TX_ROLLBACK_OK == false ]]
TX_ACTIVE=false
transaction_release_lock
trap - EXIT INT TERM
rm -rf -- "$fixture"
printf 'PASS fault injection: rollback and rollback-failure detection\n'
