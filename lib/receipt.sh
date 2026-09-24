#!/usr/bin/env bash

managed_hashes_json() {
  managed_paths_init
  local file comma=
  printf '{'
  for file in "${MANAGED_PATHS[@]}"; do
    printf '%s"%s":"%s"' "$comma" "$(json_escape "${file#"${LVO_ROOT%/}"}")" "$(sha_file "$file")"
    comma=,
  done
  printf '}'
}

write_state() {
  local state content
  state=$(tx_state_dir)/state.json
  content=$(printf '{"schema_version":%s,"tool":"lite-vps-ops","version":"%s","profile":"%s","health_timer_policy":"%s","health_timer_policy_source":"%s","migration_from":"%s","resource_envelope":%s,"managed_hashes":%s}\n' \
    "$LVO_SCHEMA_VERSION" "$LVO_VERSION" "$PROFILE" "$HEALTH_TIMER_POLICY" "$HEALTH_TIMER_POLICY_SOURCE" "$MIGRATION_FROM" \
    "$(resource_envelope_state_json)" "$(managed_hashes_json)")
  atomic_write_text "$state" 0600 "$content"
}

receipt_write() {
  local outcome=$1 ready=$2 file="$TX_DIR/receipt.json" markdown="$TX_DIR/receipt.md" checks='[]' manifest_hash=-
  [[ ${#CHECK_IDS[@]} -eq 0 ]] || checks=$(checks_json)
  [[ -f $TX_DIR/manifest.sha256 ]] && manifest_hash=$(cat "$TX_DIR/manifest.sha256")
  local host kernel arch os_version reboot=false
  host=$(hostname 2>/dev/null || printf unknown); kernel=$(uname -r 2>/dev/null || printf unknown); arch=$(uname -m 2>/dev/null || printf unknown)
  os_version=$(awk -F= '$1=="PRETTY_NAME" {gsub(/^"|"$/,"",$2); print $2}' "$(path /etc/os-release)" 2>/dev/null || printf unknown)
  [[ -e $(path /run/reboot-required) ]] && reboot=true
  printf '{"schema_version":%s,"tool":"lite-vps-ops","version":"%s","run_id":"%s","timestamp_utc":"%s","hostname":"%s","os":"%s","kernel":"%s","architecture":"%s","mode":"%s","profile":"%s","health_timer_policy":"%s","health_timer_policy_source":"%s","migration_from":"%s","resource_envelope":%s,"retention":{"keep":%s,"max_age_days":%s,"max_bytes":%s},"outcome":"%s","changed":%s,"package_action":"%s","swap_action":"%s","rollback":%s,"rollback_ok":%s,"manifest_sha256":"%s","reboot_required":%s,"ssh":{"apply_status":"%s"},"checks":%s,"node_baseline_ready":%s}\n' \
    "$LVO_SCHEMA_VERSION" "$LVO_VERSION" "$(json_escape "${RUN_ID:-none}")" "$(utc_now)" "$(json_escape "$host")" \
    "$(json_escape "$os_version")" "$(json_escape "$kernel")" "$(json_escape "$arch")" "$(json_escape "${MODE:-unknown}")" \
    "$(json_escape "${PROFILE:-unknown}")" "${HEALTH_TIMER_POLICY:-on}" "${HEALTH_TIMER_POLICY_SOURCE:-default}" "${MIGRATION_FROM:-none}" \
    "$(resource_envelope_json)" "$TRANSACTION_KEEP" "$TRANSACTION_MAX_AGE_DAYS" "$TRANSACTION_MAX_BYTES" "$outcome" "${TX_CHANGED:-0}" "$(json_escape "${PACKAGE_ACTION:-none}")" \
    "$(json_escape "${SWAP_ACTION:-none}")" "${TX_ROLLBACK:-false}" "${TX_ROLLBACK_OK:-true}" "$manifest_hash" "$reboot" \
    "${SSH_APPLY_STATUS:-not-evaluated}" "$checks" "$ready" > "$file"
  chmod 0600 "$file"
  {
    printf '# Lite VPS Ops Receipt\n\n'
    printf -- '- Run: `%s`\n- Version: `%s`\n- Mode/Profile: `%s` / `%s`\n- Outcome: **%s**\n' "${RUN_ID:-none}" "$LVO_VERSION" "${MODE:-unknown}" "${PROFILE:-unknown}" "$outcome"
    printf -- '- Changed: `%s`\n- Rollback: `%s` (ok: `%s`)\n- SSH apply: `%s`\n- NODE_BASELINE_READY: `%s`\n\n' \
      "${TX_CHANGED:-0}" "${TX_ROLLBACK:-false}" "${TX_ROLLBACK_OK:-true}" "${SSH_APPLY_STATUS:-not-evaluated}" "$ready"
    printf -- '- Health timer: `%s`\n- Migration from: `%s`\n- Transaction retention: `%s` objects / `%s` days / `%s` MiB\n\n' \
      "${HEALTH_TIMER_POLICY:-on}" "${MIGRATION_FROM:-none}" "$TRANSACTION_KEEP" "$TRANSACTION_MAX_AGE_DAYS" "$TRANSACTION_MAX_MIB"
    [[ ${#CHECK_IDS[@]} -eq 0 ]] || { printf '## Checks\n\n```text\n'; checks_human; printf '```\n'; }
  } > "$markdown"
  chmod 0600 "$markdown"
}
