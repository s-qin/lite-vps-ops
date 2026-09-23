#!/usr/bin/env bash
set -euo pipefail

LVO_VERSION=0.1.0
STATE_DIR=/var/lib/lite-vps-ops
MANAGED_MARKER='# Managed by lite-vps-ops. Edit through the tool or remove after backup.'
FILES=(
  /etc/systemd/journald.conf.d/60-lite-vps-ops.conf
  /etc/systemd/coredump.conf.d/60-lite-vps-ops.conf
  /etc/sysctl.d/60-lite-vps-ops.conf
)

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*"; }
has() { command -v "$1" >/dev/null 2>&1; }
sha() { sha256sum "$1" | cut -d' ' -f1; }

require_platform() {
  [[ -r /etc/os-release ]] || die 'Cannot read /etc/os-release'
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ ${ID:-} == debian && ${VERSION_ID:-} == 13 ]] || die 'Only Debian 13 is supported'
  [[ -d /run/systemd/system ]] || die 'systemd is required'
  [[ $(uname -m) == x86_64 || $(uname -m) == aarch64 ]] || die 'Only amd64/arm64 is supported'
}

require_apply_dependencies() {
  has systemd-analyze || die 'systemd-analyze required'
  has sysctl || die 'procps sysctl required for apply'
  has dpkg-query || die 'dpkg-query required'
  dpkg-query -W -f='${Status}' systemd-coredump 2>/dev/null | grep -Fq 'install ok installed' || die 'Install systemd-coredump before apply'
}

profile_resolve() {
  local mem_kib
  mem_kib=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
  [[ $mem_kib =~ ^[0-9]+$ ]] || die 'Cannot read RAM'
  if [[ $PROFILE == auto ]]; then
    if (( mem_kib <= 2097152 )); then PROFILE=tiny; else PROFILE=standard; fi
  fi
  [[ $PROFILE == tiny || $PROFILE == standard ]] || die 'Invalid profile'
  # shellcheck disable=SC1090
  . "$SCRIPT_DIR/profiles/$PROFILE.conf"
  local disk_mib
  disk_mib=$(df -Pm / | awk 'NR==2 {print $2}')
  [[ $disk_mib =~ ^[0-9]+$ ]] || die 'Cannot read root filesystem size'
  JOURNAL_MIB=$(( disk_mib * JOURNAL_PERCENT / 100 ))
  if (( JOURNAL_MIB > JOURNAL_MAX_MIB )); then JOURNAL_MIB=$JOURNAL_MAX_MIB; fi
  if (( JOURNAL_MIB < 16 )); then JOURNAL_MIB=16; fi
}

desired() {
  case "$1" in
    /etc/systemd/journald.conf.d/*)
      printf '%s\n[Journal]\nStorage=persistent\nCompress=yes\nSystemMaxUse=%sM\n' "$MANAGED_MARKER" "$JOURNAL_MIB" ;;
    /etc/systemd/coredump.conf.d/*)
      if [[ $PROFILE == tiny ]]; then
        printf '%s\n[Coredump]\nStorage=none\nProcessSizeMax=0\n' "$MANAGED_MARKER"
      else
        printf '%s\n[Coredump]\nStorage=external\nMaxUse=64M\nKeepFree=1G\n' "$MANAGED_MARKER"
      fi ;;
    /etc/sysctl.d/*)
      printf '%s\nfs.protected_hardlinks = 1\nfs.protected_symlinks = 1\nnet.ipv4.tcp_syncookies = 1\n' "$MANAGED_MARKER" ;;
  esac
}

file_status() {
  local file=$1 desired_file=$2
  if [[ -L $file ]]; then printf 'CONFLICT'; return; fi
  if [[ ! -e $file ]]; then printf 'NOT_CONFIGURED'; return; fi
  if [[ ! -f $file || -L $file ]]; then printf 'CONFLICT'; return; fi
  if ! grep -Fxq "$MANAGED_MARKER" "$file"; then printf 'CONFLICT'; return; fi
  if cmp -s "$file" "$desired_file"; then printf 'ALREADY_COMPLIANT'; else printf 'UPDATE_REQUIRED'; fi
}

make_plan() {
  local file status
  PLAN_CHANGED=0
  for file in "${FILES[@]}"; do
    status=$(file_status "$file" <(desired "$file"))
    say "$status $file"
    [[ $status == CONFLICT ]] && die "Unowned or unsafe path: $file"
    [[ $MODE == repair && $status == NOT_CONFIGURED ]] && die "Repair cannot create missing object: $file"
    [[ $MODE == validate && $status != ALREADY_COMPLIANT ]] && die "Baseline drift: $file"
    [[ $status == ALREADY_COMPLIANT ]] || PLAN_CHANGED=$((PLAN_CHANGED + 1))
  done
}

snapshot() {
  local file index=0 backup
  install -d -m 700 "$TX_DIR"
  : > "$TX_DIR/manifest"
  for file in "${FILES[@]}"; do
    index=$((index + 1))
    backup="$TX_DIR/$index.bak"
    if [[ -f $file ]]; then
      cp -p -- "$file" "$backup"
      printf '%s\t%s\t%s\n' "$file" "$backup" "$(sha "$backup")" >> "$TX_DIR/manifest"
    else
      printf '%s\t-\t-\n' "$file" >> "$TX_DIR/manifest"
    fi
  done
  : > "$TX_DIR/sysctl-before"
  local key value
  for key in fs.protected_hardlinks fs.protected_symlinks net.ipv4.tcp_syncookies; do
    value=$(sysctl -n "$key") || die "Cannot snapshot sysctl $key"
    printf '%s\t%s\n' "$key" "$value" >> "$TX_DIR/sysctl-before"
  done
}

validate_config() {
  local file=$1 effective
  case "$file" in
    */journald.conf.d/*)
      effective=$(systemd-analyze cat-config systemd/journald.conf)
      [[ $(awk -F= '$1=="SystemMaxUse" {gsub(/[[:space:]]/,"",$2); value=$2} END {print value}' <<< "$effective") == "${JOURNAL_MIB}M" ]] ;;
    */coredump.conf.d/*)
      effective=$(systemd-analyze cat-config systemd/coredump.conf)
      if [[ $PROFILE == tiny ]]; then
        [[ $(awk -F= '$1=="Storage" {gsub(/[[:space:]]/,"",$2); value=$2} END {print value}' <<< "$effective") == none ]]
      else
        [[ $(awk -F= '$1=="MaxUse" {gsub(/[[:space:]]/,"",$2); value=$2} END {print value}' <<< "$effective") == 64M ]]
      fi ;;
    */sysctl.d/*) sysctl -p "$file" >/dev/null ;;
  esac
}

rollback() {
  local file backup oldhash key value
  while IFS=$'\t' read -r file backup oldhash; do
    [[ -n $file ]] || continue
    if [[ $backup == - ]]; then rm -f -- "$file"; else
      [[ $(sha "$backup") == "$oldhash" ]] || return 1
      cp -p -- "$backup" "$file"
    fi
  done < "$TX_DIR/manifest"
  systemctl try-restart systemd-journald.service >/dev/null 2>&1 || true
  while IFS=$'\t' read -r key value; do
    sysctl -w "$key=$value" >/dev/null 2>&1 || return 1
    [[ $(sysctl -n "$key") == "$value" ]] || return 1
  done < "$TX_DIR/sysctl-before"
  while IFS=$'\t' read -r file backup oldhash; do
    if [[ $backup == - ]]; then [[ ! -e $file ]] || return 1
    else [[ $(sha "$file") == "$oldhash" ]] || return 1; fi
  done < "$TX_DIR/manifest"
  systemd-analyze cat-config systemd/journald.conf >/dev/null 2>&1 || return 1
  systemd-analyze cat-config systemd/coredump.conf >/dev/null 2>&1 || return 1
}

transaction_exit() {
  local exit_status=$1
  if [[ ${TX_ACTIVE:-false} == true && $exit_status -ne 0 ]]; then
    trap - EXIT
    [[ -z ${CURRENT_TMP:-} ]] || rm -f -- "$CURRENT_TMP"
    ROLLED_BACK=true READY=false
    if rollback; then receipt FAIL "$CHANGED"; else receipt ROLLBACK_FAILED "$CHANGED"; fi
  fi
}

receipt() {
  local outcome=$1 changed=$2 receipt_file="$TX_DIR/receipt.json"
  printf '{"tool":"lite-vps-ops","version":"%s","run_id":"%s","timestamp_utc":"%s","mode":"%s","profile":"%s","outcome":"%s","changed":%s,"rollback":%s,"backup_manifest":"%s","managed_baseline_ready":%s,"node_baseline_ready":false}\n' \
    "$LVO_VERSION" "$RUN_ID" "$(date -u +%FT%TZ)" "$MODE" "$PROFILE" "$outcome" "$changed" "$ROLLED_BACK" "$TX_DIR/manifest" "$READY" > "$receipt_file"
  chmod 600 "$receipt_file"
  say "Receipt: $receipt_file"
}

apply_transaction() {
  [[ $EUID -eq 0 ]] || die 'Apply/repair requires root'
  require_apply_dependencies
  has flock || die 'flock required'
  [[ ! -L $STATE_DIR ]] || die 'State directory is a symlink'
  install -d -m 700 "$STATE_DIR"
  exec 9>"$STATE_DIR/maintenance.lock"
  flock -n 9 || die 'Another write transaction is active'
  RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  TX_DIR="$STATE_DIR/transactions/$RUN_ID"
  make_plan
  snapshot
  local file tmp status
  CHANGED=0 JOURNAL_CHANGED=false TX_ACTIVE=true
  trap 'transaction_exit $?' EXIT
  ROLLED_BACK=false READY=false
  for file in "${FILES[@]}"; do
    status=$(file_status "$file" <(desired "$file"))
    if [[ $status != ALREADY_COMPLIANT ]]; then
      mkdir -p "$(dirname "$file")"
      tmp=$(mktemp "$(dirname "$file")/.lite-vps-ops.XXXXXXXX")
      CURRENT_TMP=$tmp
      desired "$file" > "$tmp"
      chmod 644 "$tmp"
      mv -- "$tmp" "$file"
      CURRENT_TMP=
      validate_config "$file"
      CHANGED=$((CHANGED + 1))
      [[ $file == "${FILES[0]}" ]] && JOURNAL_CHANGED=true
    fi
  done
  if [[ $JOURNAL_CHANGED == true ]]; then systemctl try-restart systemd-journald.service >/dev/null; fi
  READY=true
  printf '%s\n' "$LVO_VERSION" > "$STATE_DIR/baseline-version"
  receipt PASS "$CHANGED"
  TX_ACTIVE=false
  trap - EXIT
  say "Changed: $CHANGED"
}
