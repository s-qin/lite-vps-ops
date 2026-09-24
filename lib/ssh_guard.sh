#!/usr/bin/env bash

SSH_CONFIRM_TIMEOUT=${SSH_CONFIRM_TIMEOUT:-120}
SSH_CONFIRM_POLL_SECONDS=${SSH_CONFIRM_POLL_SECONDS:-1}
SSH_SAFETY_STATUS=not-evaluated
SSH_GUARD_STATUS=not-required
SSH_GUARD_DIR=
SSH_GUARD_UNIT=
SSH_GUARD_SCRIPT=
SSH_GUARD_READY=
SSH_GUARD_PROOF=

ssh_confirmation_token() {
  if [[ -n ${SSH_BLACKBOX_TOKEN:-} ]]; then
    safe_token "$SSH_BLACKBOX_TOKEN" || die 'Invalid SSH confirmation token'
    printf '%s' "$SSH_BLACKBOX_TOKEN"
    return
  fi
  if [[ -r /dev/urandom ]] && has od; then
    od -An -N16 -tx1 /dev/urandom | tr -d ' \n'
  else
    printf '%s-%s-%s' "${RUN_ID:-run}" "$$" "$(date +%s)" | sha256sum | awk '{print substr($1,1,32)}'
  fi
}

ssh_manifest_entry() {
  local target=$1
  awk -F '\t' -v target="$target" '$1 == target {print; found=1; exit} END {exit !found}' "$TX_DIR/manifest.tsv"
}

ssh_guard_prepare() {
  local target=$1 token=$2 entry state backup digest mode uid gid guard_root previous=- previous_digest=- script
  safe_token "$token" || die 'Invalid SSH confirmation token'
  entry=$(ssh_manifest_entry "$target") || die 'SSH snapshot is missing from the transaction manifest'
  IFS=$'\t' read -r _ state backup digest mode uid gid <<< "$entry"
  [[ $state == present || $state == absent ]] || die "Unsupported SSH snapshot state: $state"

  guard_root="$(tx_state_dir)/ssh-guards"
  ensure_dir 0700 "$guard_root"
  SSH_GUARD_DIR="$guard_root/$token"
  [[ ! -e $SSH_GUARD_DIR ]] || die 'SSH rollback guard token already exists'
  ensure_dir 0700 "$SSH_GUARD_DIR"
  if [[ $state == present ]]; then
    previous="$SSH_GUARD_DIR/previous.conf"
    cp -p -- "$backup" "$previous"
    previous_digest=$(sha_file "$previous")
    [[ $previous_digest == "$digest" ]] || die 'SSH rollback guard snapshot verification failed'
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$state" "$previous_digest" "${mode:--}" "${uid:--}" "${gid:--}" > "$SSH_GUARD_DIR/restore.tsv"
  printf '{"tool":"lite-vps-ops","purpose":"ssh-rollback-guard","token":"%s"}\n' "$token" > "$SSH_GUARD_DIR/owner.json"
  chmod 0600 "$SSH_GUARD_DIR/restore.tsv" "$SSH_GUARD_DIR/owner.json"

  script="$SSH_GUARD_DIR/rollback.sh"
  cat > "$script" <<EOF
#!/usr/bin/env bash
set -euo pipefail
guard_dir='$SSH_GUARD_DIR'
target='$target'
token='$token'
if [[ -f "\$guard_dir/confirmed" ]] && grep -Fxq "\$token" "\$guard_dir/confirmed"; then
  printf 'confirmation-observed\n' > "\$guard_dir/result"
  exit 0
fi
IFS=\$'\\t' read -r state digest mode uid gid < "\$guard_dir/restore.tsv"
if [[ \$state == present ]]; then
  [[ \$(sha256sum "\$guard_dir/previous.conf" | awk '{print \$1}') == "\$digest" ]]
  install -m "\$mode" -o "\$uid" -g "\$gid" "\$guard_dir/previous.conf" "\$target"
else
  rm -f -- "\$target"
fi
if [[ '${LVO_TEST_MODE}' != true ]]; then
  /usr/sbin/sshd -t
  systemctl reload ssh.service
fi
printf 'restored\n' > "\$guard_dir/result"
EOF
  chmod 0700 "$script"
  SSH_GUARD_SCRIPT=$script
  SSH_GUARD_READY="$(path /run/lite-vps-ops)/ssh-$token.ready"
  SSH_GUARD_PROOF="$(path /run/lite-vps-ops)/ssh-$token.passed"
  ensure_dir 0700 "$(dirname "$SSH_GUARD_READY")"
  printf '%s\n' "$token" > "$SSH_GUARD_READY"
  chmod 0600 "$SSH_GUARD_READY"
}

ssh_guard_prune_stale() {
  local root dir unit
  root="$(tx_state_dir)/ssh-guards"
  [[ -d $root && ! -L $root ]] || return 0
  while IFS= read -r dir; do
    [[ -d $dir && ! -L $dir && $(dirname "$dir") == "$root" ]] || continue
    [[ -f $dir/owner.json && -f $dir/result ]] || continue
    grep -Fq '"tool":"lite-vps-ops"' "$dir/owner.json" || continue
    grep -Fq '"purpose":"ssh-rollback-guard"' "$dir/owner.json" || continue
    unit="lite-vps-ops-ssh-rollback-$(basename "$dir")"
    if [[ $LVO_TEST_MODE == true ]] || ! systemctl is-active --quiet "$unit.timer" "$unit.service"; then rm -rf -- "$dir"; fi
  done < <(find "$root" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null)
}

ssh_guard_arm() {
  local token=$1
  SSH_GUARD_UNIT="lite-vps-ops-ssh-rollback-$token"
  if [[ $LVO_TEST_MODE != true ]]; then
    systemd-run --quiet --unit="$SSH_GUARD_UNIT" --on-active="${SSH_CONFIRM_TIMEOUT}s" --property=Type=oneshot "$SSH_GUARD_SCRIPT"
  fi
  SSH_GUARD_STATUS=armed
  printf 'SSH_GUARD\tARMED\t%s\t%ss\n' "$SSH_GUARD_UNIT" "$SSH_CONFIRM_TIMEOUT" >> "$TX_DIR/actions.log"
}

ssh_guard_cancel_units() {
  if [[ $LVO_TEST_MODE != true && -n ${SSH_GUARD_UNIT:-} ]]; then
    systemctl stop "$SSH_GUARD_UNIT.timer" "$SSH_GUARD_UNIT.service" >/dev/null 2>&1 || true
    systemctl reset-failed "$SSH_GUARD_UNIT.service" >/dev/null 2>&1 || true
  fi
}

ssh_guard_cleanup() {
  ssh_guard_cancel_units
  rm -f -- "${SSH_GUARD_READY:-}" "${SSH_GUARD_PROOF:-}"
  if [[ -n ${SSH_GUARD_DIR:-} && -d $SSH_GUARD_DIR ]]; then rm -rf -- "$SSH_GUARD_DIR"; fi
  SSH_GUARD_DIR=
  SSH_GUARD_SCRIPT=
  SSH_GUARD_READY=
  SSH_GUARD_PROOF=
}

ssh_guard_restore_now() {
  [[ -n ${SSH_GUARD_SCRIPT:-} && -x $SSH_GUARD_SCRIPT ]] || return 0
  rm -f -- "$SSH_GUARD_DIR/confirmed"
  "$SSH_GUARD_SCRIPT"
  SSH_GUARD_STATUS=restored
  SSH_SAFETY_STATUS=rolled-back
  printf 'SSH_GUARD\tRESTORED\n' >> "$TX_DIR/actions.log"
}

ssh_guard_wait_for_confirmation() {
  local token=$1 elapsed=0
  if [[ $LVO_TEST_MODE == true && ${LVO_TEST_SSH_AUTO_CONFIRM:-false} == true ]]; then printf '%s\n' "$token" > "$SSH_GUARD_PROOF"; fi
  while (( elapsed < SSH_CONFIRM_TIMEOUT )); do
    if [[ -f $SSH_GUARD_PROOF ]] && grep -Fxq "$token" "$SSH_GUARD_PROOF"; then return 0; fi
    sleep "$SSH_CONFIRM_POLL_SECONDS"
    elapsed=$((elapsed + 1))
  done
  return 1
}

ssh_guard_confirm() {
  local token=$1
  printf '%s\n' "$token" > "$SSH_GUARD_DIR/confirmed"
  chmod 0600 "$SSH_GUARD_DIR/confirmed"
  # shellcheck disable=SC2034 # receipt.sh consumes sourced-module state.
  SSH_BLACKBOX_PASSED=true
  # shellcheck disable=SC2034 # receipt.sh consumes sourced-module state.
  SSH_SAFETY_STATUS=external-confirmed
  SSH_GUARD_STATUS=cancelled-after-confirmation
  printf 'SSH_RECONNECT\tPASS\nSSH_GUARD\tCANCELLED\n' >> "$TX_DIR/actions.log"
  ssh_guard_cleanup
}

ssh_guard_abort_active() {
  if [[ ${SSH_GUARD_STATUS:-not-required} == armed ]]; then ssh_guard_restore_now || true; fi
  ssh_guard_cleanup
}
