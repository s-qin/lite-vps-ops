#!/usr/bin/env bash

CHECK_IDS=()
CHECK_PHASES=()
CHECK_STATUSES=()
CHECK_BLOCKING=()
CHECK_MESSAGES=()

checks_reset() { CHECK_IDS=(); CHECK_PHASES=(); CHECK_STATUSES=(); CHECK_BLOCKING=(); CHECK_MESSAGES=(); }

add_check() {
  local phase=$1 id=$2 status=$3 blocking=$4 message=$5
  case "$status" in PASS|WARN|FAIL|SKIP|INCONCLUSIVE) ;; *) die "Invalid check status: $status" ;; esac
  CHECK_PHASES+=("$phase"); CHECK_IDS+=("$id"); CHECK_STATUSES+=("$status")
  CHECK_BLOCKING+=("$blocking"); CHECK_MESSAGES+=("$message")
}

checks_blocking_ok() {
  local i
  for i in "${!CHECK_IDS[@]}"; do
    [[ ${CHECK_BLOCKING[$i]} == true && ${CHECK_STATUSES[$i]} != PASS ]] && return 1
  done
  return 0
}

checks_human() {
  local i
  for i in "${!CHECK_IDS[@]}"; do
    printf 'Phase %s | %-13s | %-28s | %s\n' "${CHECK_PHASES[$i]}" "${CHECK_STATUSES[$i]}" "${CHECK_IDS[$i]}" "${CHECK_MESSAGES[$i]}"
  done
}

checks_json() {
  local i comma=
  printf '['
  for i in "${!CHECK_IDS[@]}"; do
    printf '%s{"phase":%s,"id":"%s","status":"%s","blocking":%s,"message":"%s"}' \
      "$comma" "${CHECK_PHASES[$i]}" "$(json_escape "${CHECK_IDS[$i]}")" "${CHECK_STATUSES[$i]}" \
      "${CHECK_BLOCKING[$i]}" "$(json_escape "${CHECK_MESSAGES[$i]}")"
    comma=,
  done
  printf ']'
}
