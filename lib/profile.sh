#!/usr/bin/env bash

profile_resolve() {
  local mem_kib disk_mib free_mib
  mem_kib=$(read_meminfo_kib MemTotal)
  [[ $mem_kib =~ ^[0-9]+$ && $mem_kib -gt 0 ]] || die 'Cannot read total RAM'
  if [[ ${PROFILE:-auto} == auto ]]; then
    if (( mem_kib <= 2097152 )); then PROFILE=tiny; else PROFILE=standard; fi
  fi
  [[ $PROFILE == tiny || $PROFILE == standard ]] || die 'Invalid profile: use auto, tiny, or standard'
  # shellcheck disable=SC1090
  . "$SCRIPT_DIR/profiles/$PROFILE.conf"

  if [[ $LVO_TEST_MODE == true && -n $LVO_ROOT ]]; then
    disk_mib=${LVO_TEST_DISK_MIB:-40960}
    free_mib=${LVO_TEST_FREE_MIB:-30000}
  else
    disk_mib=$(df -Pm / | awk 'NR==2 {print $2}')
    free_mib=$(df -Pm / | awk 'NR==2 {print $4}')
  fi
  [[ $disk_mib =~ ^[0-9]+$ && $free_mib =~ ^[0-9]+$ ]] || die 'Cannot read root filesystem size'

  JOURNAL_MIB=$(( disk_mib * JOURNAL_PERCENT / 100 ))
  (( JOURNAL_MIB > JOURNAL_MAX_MIB )) && JOURNAL_MIB=$JOURNAL_MAX_MIB
  (( JOURNAL_MIB < JOURNAL_MIN_MIB )) && JOURNAL_MIB=$JOURNAL_MIN_MIB
  JOURNAL_KEEP_FREE_MIB=$(( disk_mib * JOURNAL_KEEP_FREE_PERCENT / 100 ))
  (( JOURNAL_KEEP_FREE_MIB < JOURNAL_KEEP_FREE_MIN_MIB )) && JOURNAL_KEEP_FREE_MIB=$JOURNAL_KEEP_FREE_MIN_MIB

  SWAP_MIB=$(( mem_kib / 2048 ))
  (( SWAP_MIB < SWAP_MIN_MIB )) && SWAP_MIB=$SWAP_MIN_MIB
  (( SWAP_MIB > SWAP_MAX_MIB )) && SWAP_MIB=$SWAP_MAX_MIB
  local disk_cap=$(( free_mib / 10 ))
  (( SWAP_MIB > disk_cap )) && SWAP_MIB=$disk_cap
  (( free_mib - SWAP_MIB >= 1024 )) || SWAP_MIB=0
}
