#!/usr/bin/env bash

SSH_BLACKBOX_PASSED=false
PACKAGE_ACTION=none
SWAP_ACTION=none
HEALTH_TIMER_POLICY=on
HEALTH_TIMER_POLICY_SOURCE=default
MIGRATION_FROM=none

health_timer_policy_resolve() {
  local persisted previous schema
  persisted=$(state_string_value health_timer_policy)
  previous=$(state_string_value version)
  schema=$(state_number_value schema_version)
  # shellcheck disable=SC2034 # receipt.sh consumes this sourced-module value.
  if [[ -n $previous && $previous != "$LVO_VERSION" ]]; then MIGRATION_FROM=$previous; fi
  case ${HEALTH_TIMER_REQUESTED:-preserve} in
    on|off) HEALTH_TIMER_POLICY=$HEALTH_TIMER_REQUESTED; HEALTH_TIMER_POLICY_SOURCE=explicit ;;
    preserve)
      if [[ $persisted == on || $persisted == off ]]; then
        HEALTH_TIMER_POLICY=$persisted; HEALTH_TIMER_POLICY_SOURCE=state
      elif [[ -n $schema ]]; then
        HEALTH_TIMER_POLICY=on; HEALTH_TIMER_POLICY_SOURCE="schema-${schema}-default"
      else
        HEALTH_TIMER_POLICY=on; HEALTH_TIMER_POLICY_SOURCE=default
      fi
      ;;
    *) die 'Invalid health timer policy: use on or off' ;;
  esac
}

package_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -Fq 'install ok installed'; }

phase0_audit() {
  local os_release ID='' VERSION_ID='' value disk inode state tx_count
  os_release=$(path /etc/os-release)
  # shellcheck disable=SC1090
  . "$os_release"
  [[ ${ID:-} == debian && ${VERSION_ID:-} == 13 ]] && add_check 0 os PASS true "Debian $VERSION_ID" || add_check 0 os FAIL true "unsupported ${ID:-unknown} ${VERSION_ID:-unknown}"
  if [[ $LVO_TEST_MODE == true ]]; then
    add_check 0 systemd PASS true 'test fixture'; add_check 0 architecture PASS true 'test fixture'
  else
    [[ -d /run/systemd/system ]] && add_check 0 systemd PASS true "$(systemctl --version | head -n1)" || add_check 0 systemd FAIL true 'not booted'
    value=$(uname -m); [[ $value == x86_64 || $value == aarch64 ]] && add_check 0 architecture PASS true "$value" || add_check 0 architecture FAIL true "$value"
  fi
  add_check 0 identity PASS false "user=$(id -un 2>/dev/null || printf unknown) uid=$EUID"
  if (( EUID == 0 )) || sudo -n true >/dev/null 2>&1; then add_check 0 sudo PASS true 'non-interactive privilege available'; else add_check 0 sudo WARN false 'audit works; apply requires root/sudo'; fi
  add_check 0 host PASS false "hostname=$(hostname 2>/dev/null || printf unknown) uptime=$(cut -d. -f1 "$(path /proc/uptime)" 2>/dev/null || printf unknown)s boot_id=$(cat "$(path /proc/sys/kernel/random/boot_id)" 2>/dev/null || printf unknown)"
  add_check 0 memory PASS true "total_kib=$(read_meminfo_kib MemTotal) available_kib=$(read_meminfo_kib MemAvailable)"
  value=$(read_meminfo_kib SwapTotal); [[ $value -gt 0 ]] && add_check 0 swap_present PASS true "total_kib=$value" || add_check 0 swap_present WARN true 'no active swap'
  add_check 0 load PASS false "$(cat "$(path /proc/loadavg)" 2>/dev/null || printf inconclusive)"
  for value in memory io; do
    if [[ -r $(path "/proc/pressure/$value") ]]; then add_check 0 "${value}_psi" PASS false "$(head -n1 "$(path "/proc/pressure/$value")")"; else add_check 0 "${value}_psi" SKIP false 'kernel PSI unavailable'; fi
  done
  value=$(awk '$1=="oom_kill" {print $2}' "$(path /proc/vmstat)" 2>/dev/null || printf 0)
  [[ ${value:-0} -eq 0 ]] && add_check 0 oom PASS true 'oom_kill=0' || add_check 0 oom WARN true "oom_kill=$value"
  disk=$(percent_used blocks); inode=$(percent_used inodes)
  if (( disk >= 90 )); then add_check 0 root_disk FAIL true "used=${disk}%"; elif (( disk >= 80 )); then add_check 0 root_disk WARN true "used=${disk}%"; else add_check 0 root_disk PASS true "used=${disk}%"; fi
  if (( inode >= 90 )); then add_check 0 root_inode FAIL true "used=${inode}%"; elif (( inode >= 80 )); then add_check 0 root_inode WARN true "used=${inode}%"; else add_check 0 root_inode PASS true "used=${inode}%"; fi
  if [[ $LVO_TEST_MODE == true ]]; then
    add_check 0 journal_usage PASS false 'test fixture'
  elif has journalctl; then add_check 0 journal_usage PASS false "$(journalctl --disk-usage 2>/dev/null | tail -n1 || printf inconclusive)"; else add_check 0 journal_usage INCONCLUSIVE false 'journalctl missing'; fi
  state="$(tx_state_dir)/state.json"; tx_count=0
  if [[ -d $(tx_state_dir)/transactions && -r $(tx_state_dir)/transactions ]]; then tx_count=$(find "$(tx_state_dir)/transactions" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
  elif sudo -n test -d "$(tx_state_dir)/transactions" 2>/dev/null; then tx_count=$(sudo -n find "$(tx_state_dir)/transactions" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l); fi
  if [[ -r $state ]]; then add_check 0 lvo_state PASS false "version=$(grep -o '"version":"[^"]*' "$state" | cut -d\" -f4 || true) transactions=$tx_count"
  elif sudo -n test -f "$state" 2>/dev/null; then add_check 0 lvo_state PASS false "version=$(sudo -n grep -o '"version":"[^"]*' "$state" | cut -d\" -f4 || true) transactions=$tx_count"
  else add_check 0 lvo_state WARN false "not configured; transactions=$tx_count"; fi
  if [[ $LVO_TEST_MODE == true ]]; then add_check 0 failed_units PASS true 'test fixture'
  else
    value=$(systemctl --failed --no-legend --plain 2>/dev/null | wc -l)
    [[ $value -eq 0 ]] && add_check 0 failed_units PASS true '0' || add_check 0 failed_units WARN true "$value"
  fi
}

phase1_audit() {
  local active=none
  if [[ $LVO_TEST_MODE == true ]]; then add_check 1 apt PASS true 'test fixture'; add_check 1 unattended PASS true 'test fixture'; add_check 1 time_sync PASS true 'test fixture'; return; fi
  has apt-get && [[ -s /etc/apt/sources.list || -d /etc/apt/sources.list.d ]] && add_check 1 apt PASS true 'apt and sources present' || add_check 1 apt FAIL true 'apt or sources missing'
  if package_installed unattended-upgrades; then add_check 1 unattended PASS true 'package installed'; else add_check 1 unattended FAIL true 'package missing'; fi
  if timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -Fxq yes; then active=synchronized; fi
  [[ $active == synchronized ]] && add_check 1 time_sync PASS true "$active" || add_check 1 time_sync WARN true 'not synchronized'
  [[ -e /run/reboot-required ]] && add_check 1 reboot_required WARN false 'yes (tool never auto-reboots)' || add_check 1 reboot_required PASS false 'no'
  local updates
  updates=$(apt-get -s -o Debug::NoLocking=1 upgrade 2>/dev/null | awk '/^Inst / {n++} END {print n+0}')
  [[ $updates -eq 0 ]] && add_check 1 package_updates PASS false '0 pending' || add_check 1 package_updates WARN false "$updates pending; unattended-upgrades will service policy"
}

ssh_effective_value() {
  local key=$1 output=
  if (( EUID == 0 )); then output=$(/usr/sbin/sshd -T 2>/dev/null || true)
  elif sudo -n true >/dev/null 2>&1; then output=$(sudo -n /usr/sbin/sshd -T 2>/dev/null || true)
  else output=$(/usr/sbin/sshd -T 2>/dev/null || true)
  fi
  awk -v key="$key" '$1==key {print $2; exit}' <<< "$output"
}

authorized_keys_guard() {
  [[ $LVO_TEST_MODE == true ]] && return 0
  local candidates=() user home file
  user=${SUDO_USER:-$(id -un)}
  if [[ $user != root ]]; then home=$(getent passwd "$user" | cut -d: -f6); [[ -n $home ]] && candidates+=("$home/.ssh/authorized_keys"); fi
  candidates+=(/root/.ssh/authorized_keys)
  for file in "${candidates[@]}"; do
    if [[ -f $file ]] && awk 'NF && $1 !~ /^#/ {ok=1} END {exit !ok}' "$file"; then return 0; fi
  done
  return 1
}

phase2_audit() {
  local pass kbd root forward
  if [[ $LVO_TEST_MODE == true ]]; then add_check 2 authorized_keys PASS true 'test fixture'; add_check 2 ssh_effective PASS true 'test fixture'; return; fi
  authorized_keys_guard && add_check 2 authorized_keys PASS true 'at least one non-empty key file' || add_check 2 authorized_keys FAIL true 'no usable authorized_keys'
  if [[ ! -x /usr/sbin/sshd ]]; then add_check 2 ssh_effective FAIL true 'sshd missing'; return; fi
  pass=$(ssh_effective_value passwordauthentication); kbd=$(ssh_effective_value kbdinteractiveauthentication)
  root=$(ssh_effective_value permitrootlogin); forward=$(ssh_effective_value allowtcpforwarding)
  if [[ $pass == no && $kbd == no && ( $root == prohibit-password || $root == without-password || $root == no ) && $forward != no ]]; then
    add_check 2 ssh_effective PASS true "password=$pass kbd=$kbd root=$root forwarding=$forward"
  else
    add_check 2 ssh_effective FAIL true "password=$pass kbd=$kbd root=$root forwarding=$forward"
  fi
  if [[ $SSH_BLACKBOX_PASSED == true ]] || grep -Fq '"ssh_blackbox_verified":true' "$(tx_state_dir)/state.json" 2>/dev/null || sudo -n grep -Fq '"ssh_blackbox_verified":true' "$(tx_state_dir)/state.json" 2>/dev/null; then
    add_check 2 ssh_blackbox PASS true 'controller proof recorded'
  else add_check 2 ssh_blackbox INCONCLUSIVE true 'no controller proof for v1'; fi
}

phase3_audit() {
  local swap_total used pct=0
  swap_total=$(read_meminfo_kib SwapTotal); used=$(( swap_total - $(read_meminfo_kib SwapFree) ))
  (( swap_total > 0 )) && pct=$(( used * 100 / swap_total ))
  if (( swap_total == 0 )); then add_check 3 swap_buffer FAIL true 'no active swap'
  elif (( pct >= 75 )); then add_check 3 swap_buffer WARN true "used=${pct}% total_kib=$swap_total"
  else add_check 3 swap_buffer PASS true "used=${pct}% total_kib=$swap_total"; fi
  local swappiness
  if [[ $LVO_TEST_MODE == true ]]; then swappiness=$SWAPPINESS; else swappiness=$(/usr/sbin/sysctl -n vm.swappiness 2>/dev/null || printf inconclusive); fi
  [[ $swappiness == "$SWAPPINESS" ]] && add_check 3 swappiness PASS true "$swappiness" || add_check 3 swappiness FAIL true "effective=$swappiness desired=$SWAPPINESS"
}

managed_file_check() {
  local phase=$1 id=$2 file=$3 blocking=${4:-true} status
  status=$(file_status "$file")
  case "$status" in
    ALREADY_COMPLIANT) add_check "$phase" "$id" PASS "$blocking" "$file" ;;
    CONFLICT) add_check "$phase" "$id" FAIL "$blocking" "CONFLICT $file" ;;
    *) add_check "$phase" "$id" FAIL "$blocking" "$status $file" ;;
  esac
}

phase4_audit() {
  managed_file_check 4 journald_policy "$(path /etc/systemd/journald.conf.d/60-lite-vps-ops.conf)"
  managed_file_check 4 coredump_policy "$(path /etc/systemd/coredump.conf.d/60-lite-vps-ops.conf)"
  managed_file_check 4 tmpfiles_policy "$(path /etc/tmpfiles.d/lite-vps-ops.conf)"
  if [[ $LVO_TEST_MODE == true ]] || package_installed logrotate; then add_check 4 logrotate PASS true 'installed'; else add_check 4 logrotate FAIL true 'package missing'; fi
  local count=0 bytes_kib=0 root dir
  root="$(tx_state_dir)/transactions"
  if [[ -d $root && -r $root ]]; then
    while IFS= read -r dir; do transaction_owned_dir "$dir" || continue; count=$((count + 1)); done < <(find "$root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
    bytes_kib=$(transactions_owned_kib "$root")
  fi
  if (( count <= TRANSACTION_KEEP && bytes_kib * 1024 <= TRANSACTION_MAX_BYTES )); then
    add_check 4 transaction_retention PASS true "count=$count/$TRANSACTION_KEEP bytes_kib=$bytes_kib budget_mib=$TRANSACTION_MAX_MIB"
  else
    add_check 4 transaction_retention WARN false "count=$count/$TRANSACTION_KEEP bytes_kib=$bytes_kib budget_mib=$TRANSACTION_MAX_MIB; pruned after commit"
  fi
}

phase5_audit() {
  local file key desired actual failed=0
  file=$(path /etc/sysctl.d/60-lite-vps-ops.conf)
  managed_file_check 5 sysctl_policy "$file"
  if [[ $LVO_TEST_MODE == true ]]; then add_check 5 sysctl_effective PASS true 'test fixture'; add_check 5 bpf_audit WARN false 'audit-only by design'; return; fi
  if [[ ! -f $file ]]; then add_check 5 sysctl_effective FAIL true 'managed sysctl file missing'; add_check 5 bpf_audit WARN false 'audit-only; baseline not configured'; return; fi
  while IFS='=' read -r key desired; do
    key=${key//[[:space:]]/}; desired=${desired//[[:space:]]/}
    [[ -n $key && $key != \#* ]] || continue
    actual=$(/usr/sbin/sysctl -n "$key" 2>/dev/null || printf missing)
    [[ $actual == "$desired" ]] || failed=$((failed + 1))
  done < <(desired_config "$file")
  (( failed == 0 )) && add_check 5 sysctl_effective PASS true 'all managed values effective' || add_check 5 sysctl_effective FAIL true "$failed mismatches"
  actual=$(/usr/sbin/sysctl -n kernel.unprivileged_bpf_disabled 2>/dev/null || printf unavailable)
  [[ $actual == 1 || $actual == 2 ]] && add_check 5 bpf_audit PASS false "effective=$actual; audit-only to avoid irreversible latch" || add_check 5 bpf_audit WARN false "effective=$actual; audit-only"
}

phase6_audit() {
  managed_file_check 6 health_runner "$(path /usr/local/libexec/lite-vps-ops-health)"
  managed_file_check 6 health_service "$(path /etc/systemd/system/lite-vps-ops-health.service)"
  managed_file_check 6 health_timer "$(path /etc/systemd/system/lite-vps-ops-health.timer)"
  if [[ $LVO_TEST_MODE == true ]]; then
    local test_timer=${LVO_TEST_TIMER_ENABLED:-$HEALTH_TIMER_POLICY}
    [[ $test_timer == "$HEALTH_TIMER_POLICY" ]] && add_check 6 timer_policy PASS true "policy=$HEALTH_TIMER_POLICY source=$HEALTH_TIMER_POLICY_SOURCE" || add_check 6 timer_policy FAIL true "policy=$HEALTH_TIMER_POLICY actual=$test_timer"
    add_check 6 firewall WARN false 'audit-only conservative policy'; return
  fi
  if [[ $HEALTH_TIMER_POLICY == on ]]; then
    if systemctl is-enabled --quiet lite-vps-ops-health.timer && systemctl is-active --quiet lite-vps-ops-health.timer; then add_check 6 timer_policy PASS true 'policy=on enabled and active'; else add_check 6 timer_policy FAIL true 'policy=on but not enabled/active'; fi
  elif ! systemctl is-enabled --quiet lite-vps-ops-health.timer && ! systemctl is-active --quiet lite-vps-ops-health.timer; then
    add_check 6 timer_policy PASS true 'policy=off disabled and inactive; manual health available'
  else
    add_check 6 timer_policy FAIL true 'policy=off but timer enabled or active'
  fi
  if has nft && nft list ruleset 2>/dev/null | grep -qE 'hook input|type filter'; then add_check 6 firewall PASS false 'existing host firewall detected; not overwritten'
  elif has ufw && ufw status 2>/dev/null | grep -Fq 'Status: active'; then add_check 6 firewall PASS false 'active ufw detected; not overwritten'
  else add_check 6 firewall WARN false 'no host firewall; cloud firewall remains external boundary'; fi
}

run_all_checks() {
  checks_reset
  phase0_audit; phase1_audit; phase2_audit; phase3_audit; phase4_audit; phase5_audit; phase6_audit
}

install_dependencies() {
  if [[ $LVO_TEST_MODE == true ]]; then PACKAGE_ACTION=test-skip; return; fi
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends ca-certificates curl logrotate openssh-server procps systemd-coredump systemd-timesyncd unattended-upgrades util-linux
  PACKAGE_ACTION=apt-install
  printf 'PACKAGES\t%s\n' "$PACKAGE_ACTION" >> "$TX_DIR/actions.log"
}

apply_managed_configs_except_ssh() {
  local file status
  managed_paths_init
  for file in "${MANAGED_PATHS[@]}"; do
    [[ $file == "$(path /etc/ssh/sshd_config.d/60-lite-vps-ops.conf)" ]] && continue
    status=$(file_status "$file")
    [[ $status == CONFLICT ]] && die "CONFLICT: $file"
    [[ $status == ALREADY_COMPLIANT ]] || atomic_write_managed "$file" "$([[ $file == *libexec* ]] && printf 0755 || printf 0644)"
  done
}

apply_swap() {
  local fstab swapfile swap_total content
  fstab=$(path /etc/fstab); swapfile=$(path /swapfile)
  swap_total=$(read_meminfo_kib SwapTotal)
  if (( swap_total > 0 )); then SWAP_ACTION=preserved-existing; printf 'SWAP\t%s\n' "$SWAP_ACTION" >> "$TX_DIR/actions.log"; return; fi
  if awk '$1 !~ /^#/ && NF >= 3 && $3 == "swap" {found=1} END {exit !found}' "$fstab" 2>/dev/null; then die 'CONFLICT: configured but inactive swap exists'; fi
  (( SWAP_MIB >= 256 )) || die 'Insufficient free disk for emergency swap'
  [[ ! -e $swapfile ]] || die "CONFLICT: $swapfile exists without active swap"
  if [[ $LVO_TEST_MODE == true ]]; then truncate -s "${SWAP_MIB}M" "$swapfile"
  else
    fallocate -l "${SWAP_MIB}M" "$swapfile" 2>/dev/null || dd if=/dev/zero of="$swapfile" bs=1M count="$SWAP_MIB" status=none
  fi
  chmod 600 "$swapfile"
  if [[ $LVO_TEST_MODE != true ]]; then mkswap "$swapfile" >/dev/null; fi
  content=$(cat "$fstab" 2>/dev/null || true)
  [[ -z $content || $content == *$'\n' ]] || content+=$'\n'
  content+="# lite-vps-ops swap begin"$'\n'"/swapfile none swap sw 0 0"$'\n'"# lite-vps-ops swap end"$'\n'
  atomic_write_text "$fstab" 0644 "$content"
  if [[ $LVO_TEST_MODE != true ]]; then swapon "$swapfile"; fi
  printf 'SWAPON\t%s\n' "$swapfile" >> "$TX_DIR/actions.log"
  SWAP_ACTION="created-${SWAP_MIB}MiB"
}

validate_native_configs() {
  [[ $LVO_TEST_MODE == true ]] && return 0
  apt-config dump >/dev/null
  /usr/sbin/sshd -t
  systemd-analyze cat-config systemd/journald.conf >/dev/null
  systemd-analyze cat-config systemd/coredump.conf >/dev/null
  systemd-analyze verify /etc/systemd/system/lite-vps-ops-health.service /etc/systemd/system/lite-vps-ops-health.timer >/dev/null
  logrotate --debug /etc/logrotate.conf >/dev/null
  /usr/sbin/sysctl -p /etc/sysctl.d/60-lite-vps-ops.conf >/dev/null
  systemd-tmpfiles --create /etc/tmpfiles.d/lite-vps-ops.conf
}

activate_services() {
  [[ $LVO_TEST_MODE == true ]] && return 0
  systemctl daemon-reload
  systemctl try-restart systemd-journald.service
  systemctl enable --now systemd-timesyncd.service
  systemctl enable --now unattended-upgrades.service
  if [[ $HEALTH_TIMER_POLICY == on ]]; then
    printf 'TIMER_POLICY\ton\n' >> "$TX_DIR/actions.log"
    systemctl enable --now lite-vps-ops-health.timer
  else
    printf 'TIMER_POLICY\toff\n' >> "$TX_DIR/actions.log"
    systemctl disable --now lite-vps-ops-health.timer
  fi
  systemctl start lite-vps-ops-health.service
}

ssh_gate_needed() {
  local file state status
  file=$(path /etc/ssh/sshd_config.d/60-lite-vps-ops.conf); state=$(tx_state_dir)/state.json
  status=$(file_status "$file")
  [[ $status != ALREADY_COMPLIANT ]] && return 0
  grep -Fq '"ssh_blackbox_verified":true' "$state" 2>/dev/null || return 0
  return 1
}

apply_ssh_with_blackbox() {
  local file status gate ready proof attempts=60
  file=$(path /etc/ssh/sshd_config.d/60-lite-vps-ops.conf)
  if ! ssh_gate_needed; then SSH_BLACKBOX_PASSED=true; return; fi
  [[ -n ${SSH_BLACKBOX_TOKEN:-} ]] || die 'SSH phase requires --ssh-blackbox-token and the controller launcher'
  safe_token "$SSH_BLACKBOX_TOKEN" || die 'Invalid SSH black-box token'
  authorized_keys_guard || die 'SSH authorized_keys guard failed'
  status=$(file_status "$file"); [[ $status == CONFLICT ]] && die "CONFLICT: $file"
  [[ $status == ALREADY_COMPLIANT ]] || atomic_write_managed "$file" 0644
  if [[ $LVO_TEST_MODE == true ]]; then SSH_BLACKBOX_PASSED=true; return; fi
  /usr/sbin/sshd -t
  systemctl reload ssh.service
  gate=/run/lite-vps-ops; ready="$gate/ssh-$SSH_BLACKBOX_TOKEN.ready"; proof="$gate/ssh-$SSH_BLACKBOX_TOKEN.passed"
  install -d -m 0700 "$gate"; printf '%s\n' "$SSH_BLACKBOX_TOKEN" > "$ready"; chmod 0600 "$ready"
  while (( attempts > 0 )); do
    if [[ -f $proof ]] && grep -Fxq "$SSH_BLACKBOX_TOKEN" "$proof"; then SSH_BLACKBOX_PASSED=true; break; fi
    sleep 1
    attempts=$((attempts - 1))
  done
  rm -f -- "$ready" "$proof"
  [[ $SSH_BLACKBOX_PASSED == true ]] || die 'SSH black-box verification timed out'
  /usr/sbin/sshd -t
  systemctl is-active --quiet ssh.service
  printf 'SSH_BLACKBOX\tPASS\n' >> "$TX_DIR/actions.log"
}

preflight_write() {
  (( EUID == 0 )) || die 'apply/repair requires root'
  managed_paths_init
  local file status
  for file in "${MANAGED_PATHS[@]}"; do
    status=$(file_status "$file")
    [[ $status == CONFLICT ]] && die "CONFLICT: unowned managed path $file"
  done
  if ssh_gate_needed; then
    [[ -n ${SSH_BLACKBOX_TOKEN:-} ]] || die 'No changes made: SSH controller black-box token is required'
    safe_token "$SSH_BLACKBOX_TOKEN" || die 'Invalid SSH black-box token'
  fi
  if [[ ${MODE:-apply} == repair && ! -f $(tx_state_dir)/state.json ]]; then die 'repair requires existing v1 state'; fi
}

apply_or_repair() {
  preflight_write
  transaction_begin
  snapshot_all
  install_dependencies
  apply_managed_configs_except_ssh
  apply_swap
  apply_ssh_with_blackbox
  validate_native_configs
  activate_services
  run_all_checks
  checks_human
  checks_blocking_ok || die 'Post-apply validation failed'
  transaction_commit
  say "Changed: $TX_CHANGED"
  say "Receipt: $TX_DIR/receipt.json"
}

dry_run_plan() {
  resource_envelope_human
  config_plan || die 'Plan contains CONFLICT'
  local swap_total
  swap_total=$(read_meminfo_kib SwapTotal)
  if (( swap_total > 0 )); then say "ALREADY_COMPLIANT active swap total_kib=$swap_total"; else say "NOT_CONFIGURED emergency swap target=${SWAP_MIB}MiB"; fi
  if ssh_gate_needed; then say 'INCONCLUSIVE SSH change requires controller black-box token'; else say 'ALREADY_COMPLIANT SSH black-box proof recorded'; fi
  say "PLAN_CHANGED=$PLAN_CHANGED"
}

health_command() {
  local runner
  runner=$(path /usr/local/libexec/lite-vps-ops-health)
  if [[ -x $runner && -z $LVO_ROOT ]]; then "$runner"; return; fi
  run_all_checks
  checks_human
  checks_blocking_ok
}
