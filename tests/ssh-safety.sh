#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=tests/helpers.sh
. "$root/tests/helpers.sh"

run_failure_case() {
  local case_name=$1 expected=$2 case_fixture ssh_file rc=0
  make_fixture
  case_fixture=$fixture
  (
    fixture=$case_fixture
    load_fixture
    managed_paths_init
    ssh_file=$(path /etc/ssh/sshd_config.d/60-lite-vps-ops.conf)
    if [[ $case_name == conflict ]]; then printf 'foreign\n' > "$ssh_file"; fi
    transaction_begin
    snapshot_all
    case "$case_name" in
      authorized-keys) LVO_TEST_AUTHORIZED_KEYS=missing ;;
      syntax) LVO_TEST_SSHD_T=fail ;;
      reload) LVO_TEST_SSH_RELOAD=fail ;;
      native) LVO_TEST_NATIVE_VALIDATION=fail ;;
    esac
    apply_ssh_config
    if [[ $case_name == native ]]; then validate_native_configs || die 'Injected native validation failure'; fi
    echo "failure case unexpectedly passed: $case_name" >&2
    exit 1
  ) || rc=$?
  (( rc != 0 ))
  ssh_file="$case_fixture/etc/ssh/sshd_config.d/60-lite-vps-ops.conf"
  if [[ $expected == absent ]]; then [[ ! -e $ssh_file ]]; else [[ $(cat "$ssh_file") == foreign ]]; fi
  grep -Fq '"rollback":true' "$case_fixture"/var/lib/lite-vps-ops/transactions/*/receipt.json
  grep -Fq '"rollback_ok":true' "$case_fixture"/var/lib/lite-vps-ops/transactions/*/receipt.json
  rm -rf -- "$case_fixture"
}

run_failure_case authorized-keys absent
run_failure_case conflict foreign
run_failure_case syntax absent
run_failure_case reload absent
run_failure_case native absent

make_fixture
success_fixture=$fixture
trap 'rm -rf -- "$success_fixture"' EXIT
load_fixture
managed_paths_init
ssh_file=$(path /etc/ssh/sshd_config.d/60-lite-vps-ops.conf)
transaction_begin
snapshot_all
apply_ssh_config
[[ $SSH_APPLY_STATUS == changed-validated && -f $ssh_file ]]
ssh_validate_candidate
ssh_reload_and_verify
apply_ssh_config
[[ $SSH_APPLY_STATUS == unchanged ]]
[[ ! -e $(tx_state_dir)/ssh-guards ]]
[[ -z $(find "$fixture/run" -maxdepth 2 -type f \( -name 'ssh-*.ready' -o -name 'ssh-*.passed' \) -print) ]]
TX_ACTIVE=false
transaction_release_lock
trap - EXIT INT TERM
rm -rf -- "$success_fixture"

[[ ! -e $root/lib/ssh_guard.sh ]]
if grep -Eq -- '--ssh-blackbox-token|--ssh-confirm-timeout|SECOND SSH|ssh_guard_|SSH_GUARD_|SSH_BLACKBOX_' \
  "$root/lite-vps-ops" "$root/lib/core.sh" "$root/lib/phases.sh" "$root/lib/transaction.sh" "$root/lib/receipt.sh"; then
  echo 'obsolete SSH guard surface remains in production Bash' >&2
  exit 1
fi
if obsolete_output=$("$root/lite-vps-ops" --ssh-blackbox-token obsolete 2>&1); then
  echo 'obsolete SSH flag unexpectedly succeeded' >&2; exit 1
fi
grep -Fq 'Unknown option: --ssh-blackbox-token' <<< "$obsolete_output"

printf 'PASS SSH safety: noninteractive apply, preconditions, syntax/reload/native rollback, idempotence, old-artifact absence\n'
