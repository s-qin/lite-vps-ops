#!/usr/bin/env bash

tx_state_dir() { path "$LVO_STATE_DIR"; }
tx_lock_file() { path "$LVO_LOCK_FILE"; }

transaction_begin() {
  local state lock
  state=$(tx_state_dir); lock=$(tx_lock_file)
  ensure_dir 0700 "$(dirname "$lock")" "$state/transactions"
  if [[ $LVO_TEST_MODE == true ]]; then
    TX_TEST_LOCK="$lock.testlock"
    mkdir "$TX_TEST_LOCK" 2>/dev/null || die 'Another apply/repair transaction is active'
  else
    exec 9>"$lock"
    flock -n 9 || die 'Another apply/repair transaction is active'
  fi
  RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  TX_DIR="$state/transactions/$RUN_ID"
  ensure_dir 0700 "$TX_DIR/backups"
  : > "$TX_DIR/manifest.tsv"
  : > "$TX_DIR/actions.log"
  TX_ACTIVE=true
  TX_ROLLBACK=false
  TX_ROLLBACK_OK=true
  TX_CHANGED=0
  trap 'transaction_abort $?' EXIT INT TERM
}

transaction_release_lock() {
  if [[ -n ${TX_TEST_LOCK:-} ]]; then rmdir "$TX_TEST_LOCK" 2>/dev/null || true; TX_TEST_LOCK=; fi
}

snapshot_one() {
  local file=$1 index=$2 backup
  backup="$TX_DIR/backups/$index"
  if [[ -L $file || ( -e $file && ! -f $file ) ]]; then die "Unsafe snapshot target: $file"; fi
  if [[ -f $file ]]; then
    cp -p -- "$file" "$backup"
    printf '%s\tpresent\t%s\t%s\t%s\t%s\t%s\n' "$file" "$backup" "$(sha_file "$backup")" \
      "$(stat -c %a "$file")" "$(stat -c %u "$file")" "$(stat -c %g "$file")" >> "$TX_DIR/manifest.tsv"
  else
    printf '%s\tabsent\t-\t-\t-\t-\t-\n' "$file" >> "$TX_DIR/manifest.tsv"
  fi
}

snapshot_all() {
  managed_paths_init
  local targets=("${MANAGED_PATHS[@]}" "$(path /etc/fstab)" "$(path /swapfile)" "$(tx_state_dir)/state.json" "$(tx_state_dir)/baseline-version")
  local i=0 file
  for file in "${targets[@]}"; do i=$((i + 1)); snapshot_one "$file" "$i"; done
  : > "$TX_DIR/sysctl-before.tsv"
  if [[ $LVO_TEST_MODE != true ]]; then
    local key value
    while IFS='=' read -r key _; do
      key=${key//[[:space:]]/}
      [[ -n $key && $key != \#* ]] || continue
      value=$(/usr/sbin/sysctl -n "$key" 2>/dev/null || true)
      [[ -n $value ]] || die "Cannot snapshot sysctl $key"
      printf '%s\t%s\n' "$key" "$value" >> "$TX_DIR/sysctl-before.tsv"
    done < <(desired_config "$(path /etc/sysctl.d/60-lite-vps-ops.conf)")
  fi
  sha256sum "$TX_DIR/manifest.tsv" | awk '{print $1}' > "$TX_DIR/manifest.sha256"
}

atomic_write_managed() {
  local file=$1 mode=${2:-0644} dir tmp
  dir=$(dirname "$file")
  ensure_dir 0755 "$dir"
  tmp=$(mktemp "$dir/.lite-vps-ops.XXXXXXXX")
  desired_config "$file" > "$tmp"
  chmod "$mode" "$tmp"
  mv -f -- "$tmp" "$file"
  printf 'WRITE\t%s\t%s\n' "$file" "$(sha_file "$file")" >> "$TX_DIR/actions.log"
  TX_CHANGED=$((TX_CHANGED + 1))
}

atomic_write_text() {
  local file=$1 mode=$2 content=$3 dir tmp
  dir=$(dirname "$file")
  ensure_dir 0755 "$dir"
  tmp=$(mktemp "$dir/.lite-vps-ops.XXXXXXXX")
  printf '%s' "$content" > "$tmp"
  chmod "$mode" "$tmp"
  if [[ -f $file ]] && cmp -s "$file" "$tmp"; then rm -f -- "$tmp"; return 0; fi
  mv -f -- "$tmp" "$file"
  printf 'WRITE\t%s\t%s\n' "$file" "$(sha_file "$file")" >> "$TX_DIR/actions.log"
  TX_CHANGED=$((TX_CHANGED + 1))
}

rollback_all() {
  local file state backup digest mode uid gid key value
  if [[ -f $TX_DIR/actions.log ]] && grep -Fq $'SWAPON\t' "$TX_DIR/actions.log" && [[ $LVO_TEST_MODE != true ]]; then
    swapoff "$(path /swapfile)" >/dev/null 2>&1 || TX_ROLLBACK_OK=false
  fi
  if [[ -f $TX_DIR/actions.log ]] && grep -Fq $'ENABLE_TIMER\t' "$TX_DIR/actions.log" && [[ $LVO_TEST_MODE != true ]]; then
    systemctl disable --now lite-vps-ops-health.timer >/dev/null 2>&1 || TX_ROLLBACK_OK=false
  fi
  while IFS=$'\t' read -r file state backup digest mode uid gid; do
    [[ -n $file ]] || continue
    if [[ $state == absent ]]; then
      rm -f -- "$file" || TX_ROLLBACK_OK=false
    else
      [[ $(sha_file "$backup") == "$digest" ]] || { TX_ROLLBACK_OK=false; continue; }
      ensure_dir 0755 "$(dirname "$file")"
      cp -p -- "$backup" "$file" || TX_ROLLBACK_OK=false
      chmod "$mode" "$file" || TX_ROLLBACK_OK=false
      if [[ $LVO_TEST_MODE != true ]]; then chown "$uid:$gid" "$file" || TX_ROLLBACK_OK=false; fi
    fi
  done < "$TX_DIR/manifest.tsv"
  if [[ $LVO_TEST_MODE != true ]]; then
    systemctl daemon-reload >/dev/null 2>&1 || TX_ROLLBACK_OK=false
    systemctl try-restart systemd-journald.service >/dev/null 2>&1 || TX_ROLLBACK_OK=false
    while IFS=$'\t' read -r key value; do
      [[ -n $key ]] || continue
      /usr/sbin/sysctl -w "$key=$value" >/dev/null 2>&1 || TX_ROLLBACK_OK=false
      [[ $(/usr/sbin/sysctl -n "$key" 2>/dev/null) == "$value" ]] || TX_ROLLBACK_OK=false
    done < "$TX_DIR/sysctl-before.tsv"
    /usr/sbin/sshd -t >/dev/null 2>&1 || TX_ROLLBACK_OK=false
    systemctl reload ssh.service >/dev/null 2>&1 || TX_ROLLBACK_OK=false
  fi
  [[ $TX_ROLLBACK_OK == true ]]
}

transaction_abort() {
  local status=$1
  [[ ${TX_ACTIVE:-false} == true ]] || return "$status"
  trap - EXIT INT TERM
  # shellcheck disable=SC2034 # consumed by receipt.sh after all modules are sourced
  TX_ROLLBACK=true
  if rollback_all; then
    receipt_write FAIL false || true
  else
    receipt_write ROLLBACK_FAILED false || true
  fi
  TX_ACTIVE=false
  transaction_release_lock
  prune_transactions || true
  exit "$status"
}

transaction_commit() {
  local state
  state=$(tx_state_dir)
  write_state
  atomic_write_text "$state/baseline-version" 0600 "$LVO_VERSION"$'\n'
  receipt_write PASS true
  TX_ACTIVE=false
  trap - EXIT INT TERM
  transaction_release_lock
  prune_transactions
}

prune_transactions() {
  local root current count dir
  root="$(tx_state_dir)/transactions"; current=${TX_DIR:-}
  [[ -d $root ]] || return 0
  while IFS= read -r dir; do
    [[ $dir == "$current" ]] || rm -rf -- "$dir"
  done < <(find "$root" -mindepth 1 -maxdepth 1 -type d -mtime "+$TRANSACTION_MAX_AGE_DAYS" -print 2>/dev/null)
  count=0
  while IFS= read -r dir; do
    count=$((count + 1))
    if (( count > TRANSACTION_KEEP )) && [[ $dir != "$current" ]]; then rm -rf -- "$dir"; fi
  done < <(find "$root" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)
}
