#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=tests/helpers.sh
. "$root/tests/helpers.sh"
make_fixture
trap 'rm -rf -- "$fixture"' EXIT
load_fixture

state="$(tx_state_dir)/state.json"
mkdir -p "$(dirname "$state")"
printf '{"schema_version":1,"tool":"lite-vps-ops","version":"1.0.0","profile":"tiny","ssh_blackbox_verified":true}\n' > "$state"
HEALTH_TIMER_REQUESTED=preserve
health_timer_policy_resolve
[[ $HEALTH_TIMER_POLICY == on && $HEALTH_TIMER_POLICY_SOURCE == schema-1-default && $MIGRATION_FROM == 1.0.0 ]]

HEALTH_TIMER_REQUESTED=off
health_timer_policy_resolve
[[ $HEALTH_TIMER_POLICY == off && $HEALTH_TIMER_POLICY_SOURCE == explicit ]]
printf '{"schema_version":2,"tool":"lite-vps-ops","version":"1.1.0","profile":"tiny","health_timer_policy":"off","health_timer_policy_source":"explicit","ssh_safety_status":"external-confirmed","ssh_reconnect_verified":true,"ssh_rollback_guard":"cancelled-after-confirmation","ssh_blackbox_verified":true}\n' > "$state"
HEALTH_TIMER_REQUESTED=preserve
MIGRATION_FROM=none
health_timer_policy_resolve
[[ $HEALTH_TIMER_POLICY == off && $HEALTH_TIMER_POLICY_SOURCE == explicit && $MIGRATION_FROM == 1.1.0 ]]
managed_paths_init
transaction_begin
snapshot_all
apply_managed_configs_except_ssh
checks_reset
add_check 0 migration PASS true migrated
transaction_commit
grep -Fq '"health_timer_policy":"off"' "$state"
grep -Fq '"migration_from":"1.1.0"' "$state"
if grep -Eq 'ssh_(apply_status|blackbox|reconnect|rollback_guard|safety_status)' "$state"; then echo 'run-specific SSH metadata persisted in state' >&2; exit 1; fi
if grep -Fq '"mem_available_mib"' "$state"; then echo 'volatile envelope input persisted in state' >&2; exit 1; fi
first_state_hash=$(sha_file "$state")

transaction_begin
snapshot_all
apply_managed_configs_except_ssh
checks_reset
add_check 0 migration PASS true migrated
transaction_commit
[[ $TX_CHANGED -eq 0 && $(sha_file "$state") == "$first_state_hash" ]]

HEALTH_TIMER_REQUESTED=preserve
health_timer_policy_resolve
[[ $HEALTH_TIMER_POLICY == off && $HEALTH_TIMER_POLICY_SOURCE == explicit ]]
[[ $MIGRATION_FROM == 1.1.0 ]]
LVO_TEST_TIMER_ENABLED=off
checks_reset
phase6_audit
checks_blocking_ok
printf 'PASS migration/timer: schema 1 read, v1.1.0 schema-2 convergence, stable idempotent state, timer persistence\n'
