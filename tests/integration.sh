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
apply_managed_configs_except_ssh
SSH_BLACKBOX_TOKEN=aaaaaaaaaaaaaaaa
apply_ssh_with_blackbox
for file in "${MANAGED_PATHS[@]}"; do [[ $(file_status "$file") == ALREADY_COMPLIANT ]]; done
first_hash=$(find "$fixture/etc" "$fixture/usr/local/libexec" -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | awk '{print $1}')
for file in "${MANAGED_PATHS[@]}"; do [[ $(file_status "$file") == ALREADY_COMPLIANT ]]; done
second_hash=$(find "$fixture/etc" "$fixture/usr/local/libexec" -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | awk '{print $1}')
[[ $first_hash == "$second_hash" ]]

printf 'corrupt\n' > "${MANAGED_PATHS[0]}"
rollback_all
for file in "${MANAGED_PATHS[@]}"; do [[ ! -e $file ]]; done
[[ $(cat "$fixture/etc/fstab") == '# fixture fstab' ]]
TX_ACTIVE=false
transaction_release_lock
trap - EXIT INT TERM
rm -rf -- "$fixture"
printf 'PASS integration: snapshot, ownership, idempotence, rollback\n'
