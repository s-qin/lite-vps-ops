#!/usr/bin/env bash
# shellcheck disable=SC2034 # Resource Envelope values are consumed by other sourced modules.

clamp() {
  local value=$1 minimum=$2 maximum=$3
  (( value < minimum )) && value=$minimum
  (( value > maximum )) && value=$maximum
  printf '%s' "$value"
}

min_value() { (( $1 < $2 )) && printf '%s' "$1" || printf '%s' "$2"; }
max_value() { (( $1 > $2 )) && printf '%s' "$1" || printf '%s' "$2"; }
round_down() { local value=$1 step=$2; printf '%s' "$(( value / step * step ))"; }

read_cgroup_limit_mib() {
  local raw='' path_name
  if [[ -n ${LVO_TEST_CGROUP_LIMIT_MIB:-} ]]; then printf '%s' "$LVO_TEST_CGROUP_LIMIT_MIB"; return; fi
  for path_name in /sys/fs/cgroup/memory.max /sys/fs/cgroup/memory/memory.limit_in_bytes; do
    [[ -r $path_name ]] || continue
    raw=$(cat "$path_name" 2>/dev/null || true)
    [[ $raw =~ ^[0-9]+$ ]] || continue
    (( raw < 9223372036854771712 )) || continue
    printf '%s' "$(( raw / 1048576 ))"
    return
  done
  printf '0'
}

detect_swap_type() {
  if [[ -n ${LVO_TEST_SWAP_TYPE:-} ]]; then printf '%s' "$LVO_TEST_SWAP_TYPE"; return; fi
  local swaps
  swaps=$(path /proc/swaps)
  [[ -r $swaps ]] || { printf 'none'; return; }
  awk 'NR>1 {if ($2=="partition") partition=1; else file=1} END {if (partition && file) print "mixed"; else if (partition) print "partition"; else if (file) print "file"; else print "none"}' "$swaps"
}

profile_auto_defaults() {
  JOURNAL_MIN_MIB=16
  JOURNAL_MAX_MIB=256
  COREDUMP_MAX_MIB=128
  SWAP_MIN_MIB=256
  SWAP_MAX_MIB=2048
  SWAPPINESS=10
  DISK_RESERVE_PERCENT=5
  DISK_RESERVE_MIN_MIB=512
}

profile_resolve() {
  local mem_kib available_kib disk_mib free_mib cgroup_mib effective_mib free_after_reserve
  local journal_cap swap_base swap_cap availability_deficit coredump_cap tx_cap
  PROFILE_REQUESTED=${PROFILE:-auto}
  PROFILE=$PROFILE_REQUESTED
  [[ $PROFILE == auto || $PROFILE == tiny || $PROFILE == standard ]] || die 'Invalid profile: use auto, tiny, or standard'

  mem_kib=$(read_meminfo_kib MemTotal)
  available_kib=$(read_meminfo_kib MemAvailable)
  [[ $mem_kib =~ ^[0-9]+$ && $mem_kib -gt 0 ]] || die 'Cannot read total RAM'
  [[ $available_kib =~ ^[0-9]+$ ]] || die 'Cannot read available RAM'
  RESOURCE_MEM_TOTAL_MIB=$(( mem_kib / 1024 ))
  RESOURCE_MEM_AVAILABLE_MIB=$(( available_kib / 1024 ))
  cgroup_mib=$(read_cgroup_limit_mib)
  RESOURCE_CGROUP_LIMIT_MIB=$cgroup_mib
  effective_mib=$RESOURCE_MEM_TOTAL_MIB
  if (( cgroup_mib >= 128 && cgroup_mib < effective_mib )); then effective_mib=$cgroup_mib; fi
  RESOURCE_EFFECTIVE_MEMORY_MIB=$effective_mib

  if [[ $LVO_TEST_MODE == true && -n $LVO_ROOT ]]; then
    disk_mib=${LVO_TEST_DISK_MIB:-40960}
    free_mib=${LVO_TEST_FREE_MIB:-30000}
    RESOURCE_INODE_USED_PERCENT=${LVO_TEST_INODE_USED_PERCENT:-10}
  else
    disk_mib=$(df -Pm / | awk 'NR==2 {print $2}')
    free_mib=$(df -Pm / | awk 'NR==2 {print $4}')
    RESOURCE_INODE_USED_PERCENT=$(percent_used inodes)
  fi
  [[ $disk_mib =~ ^[0-9]+$ && $disk_mib -gt 0 && $free_mib =~ ^[0-9]+$ ]] || die 'Cannot read root filesystem size'
  RESOURCE_DISK_TOTAL_MIB=$disk_mib
  RESOURCE_DISK_FREE_MIB=$free_mib
  RESOURCE_DISK_USED_PERCENT=$(( (disk_mib - free_mib) * 100 / disk_mib ))
  (( RESOURCE_DISK_USED_PERCENT < 0 )) && RESOURCE_DISK_USED_PERCENT=0
  RESOURCE_SWAP_TOTAL_MIB=$(( $(read_meminfo_kib SwapTotal) / 1024 ))
  RESOURCE_SWAP_TYPE=$(detect_swap_type)

  if [[ $PROFILE == auto ]]; then
    profile_auto_defaults
  else
    # shellcheck disable=SC1090
    . "$SCRIPT_DIR/profiles/$PROFILE.conf"
  fi

  DISK_RESERVE_MIB=$(( disk_mib * DISK_RESERVE_PERCENT / 100 ))
  (( DISK_RESERVE_MIB < DISK_RESERVE_MIN_MIB )) && DISK_RESERVE_MIB=$DISK_RESERVE_MIN_MIB
  (( DISK_RESERVE_MIB > disk_mib / 2 )) && DISK_RESERVE_MIB=$(( disk_mib / 2 ))
  free_after_reserve=$(( free_mib - DISK_RESERVE_MIB ))
  (( free_after_reserve < 0 )) && free_after_reserve=0
  RESOURCE_FREE_AFTER_RESERVE_MIB=$free_after_reserve

  if [[ $PROFILE == auto ]]; then
    JOURNAL_RETENTION_SEC=$(( 1209600 + $(min_value "$(( effective_mib / 128 ))" 16) * 86400 ))
    TRANSACTION_KEEP=$(( 20 + $(min_value "$(( disk_mib / 51200 ))" 10) ))
    TRANSACTION_MAX_AGE_DAYS=$(( 30 + $(min_value "$(( disk_mib / 10240 ))" 30) ))
    TRANSACTION_MAX_MIB=$(clamp "$(( 32 + disk_mib / 512 ))" 32 256)
  fi
  (( RESOURCE_INODE_USED_PERCENT >= 85 && TRANSACTION_KEEP > 10 )) && TRANSACTION_KEEP=10

  JOURNAL_KEEP_FREE_MIB=$DISK_RESERVE_MIB
  JOURNAL_MIB=$(( 16 + disk_mib / 1024 ))
  journal_cap=$(( free_after_reserve / 20 ))
  (( journal_cap > JOURNAL_MAX_MIB )) && journal_cap=$JOURNAL_MAX_MIB
  (( RESOURCE_DISK_USED_PERCENT >= 80 )) && journal_cap=$(( journal_cap / 2 ))
  (( JOURNAL_MIB > journal_cap )) && JOURNAL_MIB=$journal_cap
  (( JOURNAL_MIB > JOURNAL_MAX_MIB )) && JOURNAL_MIB=$JOURNAL_MAX_MIB
  if (( JOURNAL_MIB < JOURNAL_MIN_MIB && journal_cap >= JOURNAL_MIN_MIB )); then JOURNAL_MIB=$JOURNAL_MIN_MIB; fi
  JOURNAL_MIB=$(round_down "$JOURNAL_MIB" 4)
  (( JOURNAL_MIB >= 4 )) || JOURNAL_MIB=4

  availability_deficit=$(( effective_mib / 4 - RESOURCE_MEM_AVAILABLE_MIB ))
  (( availability_deficit < 0 )) && availability_deficit=0
  swap_base=$(( effective_mib / 2 + availability_deficit / 2 ))
  SWAP_MIB=$(clamp "$swap_base" "$SWAP_MIN_MIB" "$SWAP_MAX_MIB")
  swap_cap=$(( free_after_reserve / 4 ))
  (( disk_mib / 20 < swap_cap )) && swap_cap=$(( disk_mib / 20 ))
  (( SWAP_MIB > swap_cap )) && SWAP_MIB=$swap_cap
  SWAP_MIB=$(round_down "$SWAP_MIB" 16)
  (( SWAP_MIB >= SWAP_MIN_MIB )) || SWAP_MIB=0

  COREDUMP_STORAGE=none
  COREDUMP_BUDGET_MIB=0
  if (( COREDUMP_MAX_MIB > 0 && effective_mib >= 1536 && free_after_reserve >= 2048 && RESOURCE_DISK_USED_PERCENT < 85 )); then
    coredump_cap=$(min_value "$(( effective_mib / 16 ))" "$(( free_after_reserve / 20 ))")
    coredump_cap=$(min_value "$coredump_cap" "$COREDUMP_MAX_MIB")
    coredump_cap=$(round_down "$coredump_cap" 16)
    if (( coredump_cap >= 16 )); then COREDUMP_STORAGE=external; COREDUMP_BUDGET_MIB=$coredump_cap; fi
  fi
  COREDUMP_MAX_MIB=$COREDUMP_BUDGET_MIB

  tx_cap=$(( free_after_reserve / 10 ))
  (( TRANSACTION_MAX_MIB > tx_cap )) && TRANSACTION_MAX_MIB=$tx_cap
  (( TRANSACTION_MAX_MIB < 16 )) && TRANSACTION_MAX_MIB=16
  (( RESOURCE_DISK_USED_PERCENT >= 90 )) && TRANSACTION_MAX_MIB=16
  TRANSACTION_MAX_BYTES=$(( TRANSACTION_MAX_MIB * 1048576 ))
}

resource_envelope_human() {
  printf 'RESOURCE_ENVELOPE profile=%s mem_total_mib=%s mem_available_mib=%s effective_memory_mib=%s cgroup_limit_mib=%s disk_total_mib=%s disk_free_mib=%s disk_used_percent=%s inode_used_percent=%s disk_reserve_mib=%s existing_swap_mib=%s swap_type=%s swap_budget_mib=%s journal_budget_mib=%s coredump_budget_mib=%s transaction_keep=%s transaction_age_days=%s transaction_budget_mib=%s health_timer=%s\n' \
    "$PROFILE" "$RESOURCE_MEM_TOTAL_MIB" "$RESOURCE_MEM_AVAILABLE_MIB" "$RESOURCE_EFFECTIVE_MEMORY_MIB" "$RESOURCE_CGROUP_LIMIT_MIB" \
    "$RESOURCE_DISK_TOTAL_MIB" "$RESOURCE_DISK_FREE_MIB" "$RESOURCE_DISK_USED_PERCENT" "$RESOURCE_INODE_USED_PERCENT" "$DISK_RESERVE_MIB" \
    "$RESOURCE_SWAP_TOTAL_MIB" "$RESOURCE_SWAP_TYPE" "$SWAP_MIB" "$JOURNAL_MIB" "$COREDUMP_MAX_MIB" "$TRANSACTION_KEEP" \
    "$TRANSACTION_MAX_AGE_DAYS" "$TRANSACTION_MAX_MIB" "${HEALTH_TIMER_POLICY:-unresolved}"
}

resource_envelope_json() {
  printf '{"profile":"%s","mem_total_mib":%s,"mem_available_mib":%s,"effective_memory_mib":%s,"cgroup_limit_mib":%s,"disk_total_mib":%s,"disk_free_mib":%s,"disk_used_percent":%s,"inode_used_percent":%s,"disk_reserve_mib":%s,"existing_swap_mib":%s,"swap_type":"%s","swap_budget_mib":%s,"journal_budget_mib":%s,"coredump_budget_mib":%s,"transaction_keep":%s,"transaction_age_days":%s,"transaction_budget_mib":%s}' \
    "$PROFILE" "$RESOURCE_MEM_TOTAL_MIB" "$RESOURCE_MEM_AVAILABLE_MIB" "$RESOURCE_EFFECTIVE_MEMORY_MIB" "$RESOURCE_CGROUP_LIMIT_MIB" \
    "$RESOURCE_DISK_TOTAL_MIB" "$RESOURCE_DISK_FREE_MIB" "$RESOURCE_DISK_USED_PERCENT" "$RESOURCE_INODE_USED_PERCENT" "$DISK_RESERVE_MIB" \
    "$RESOURCE_SWAP_TOTAL_MIB" "$(json_escape "$RESOURCE_SWAP_TYPE")" "$SWAP_MIB" "$JOURNAL_MIB" "$COREDUMP_MAX_MIB" "$TRANSACTION_KEEP" \
    "$TRANSACTION_MAX_AGE_DAYS" "$TRANSACTION_MAX_MIB"
}
