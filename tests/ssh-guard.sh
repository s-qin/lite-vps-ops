#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=tests/helpers.sh
. "$root/tests/helpers.sh"
make_fixture
trap 'rm -rf -- "$fixture"' EXIT
load_fixture

managed_paths_init
ssh_file=$(path /etc/ssh/sshd_config.d/60-lite-vps-ops.conf)
transaction_begin
snapshot_all
atomic_write_managed "$ssh_file" 0644

token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
ssh_guard_prepare "$ssh_file" "$token"
SSH_CONFIRM_TIMEOUT=15
SSH_CONFIRM_POLL_SECONDS=0
ssh_guard_arm "$token"
[[ $SSH_GUARD_STATUS == armed && -x $SSH_GUARD_SCRIPT && -f $SSH_GUARD_READY ]]
[[ -f $ssh_file ]]

# No second connection proof: the guard restores the pre-transaction SSH state.
if ssh_guard_wait_for_confirmation "$token"; then echo 'unexpected SSH confirmation' >&2; exit 1; fi
ssh_guard_restore_now
[[ ! -e $ssh_file && $SSH_SAFETY_STATUS == rolled-back && $SSH_GUARD_STATUS == restored ]]
grep -Fxq restored "$SSH_GUARD_DIR/result"
ssh_guard_cleanup

TX_ACTIVE=false
transaction_release_lock
trap - EXIT INT TERM
rm -rf -- "$fixture"
printf 'PASS ssh guard: timed guard ownership, missing-proof rollback, cleanup\n'
