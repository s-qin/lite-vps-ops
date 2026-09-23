#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=tests/helpers.sh
. "$root/tests/helpers.sh"
make_fixture
trap 'rm -rf -- "$fixture"' EXIT
load_fixture

transaction_begin
first_tx=$TX_DIR
if (TX_ACTIVE=false; transaction_begin >/dev/null 2>&1); then
  echo 'concurrent transaction unexpectedly acquired lock' >&2
  exit 1
fi
TX_ACTIVE=false
transaction_release_lock
rm -rf -- "$first_tx"

root_tx="$(tx_state_dir)/transactions"
mkdir -p "$root_tx"/{01,02,03,04,05}
touch -t 202601010101 "$root_tx/01"
touch -t 202602010101 "$root_tx/02"
touch -t 202603010101 "$root_tx/03"
touch -t 202604010101 "$root_tx/04"
touch -t 202605010101 "$root_tx/05"
TRANSACTION_KEEP=3
TRANSACTION_MAX_AGE_DAYS=9999
TX_DIR="$root_tx/05"
prune_transactions
count=$(find "$root_tx" -mindepth 1 -maxdepth 1 -type d | wc -l)
[[ $count -eq 3 ]]
[[ -d $root_tx/05 && -d $root_tx/04 && -d $root_tx/03 ]]
printf 'PASS retention/lock: concurrent writer rejected and newest transactions retained\n'
