#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=lib/core.sh
. "$SCRIPT_DIR/lib/core.sh"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
PROFILE=tiny JOURNAL_MIB=48 MODE=apply
FILES=("$tmp/journald.conf" "$tmp/coredump.conf" "$tmp/sysctl.conf")
desired() {
  case "$1" in
    *journald.conf) printf '%s\n[Journal]\nSystemMaxUse=%sM\n' "$MANAGED_MARKER" "$JOURNAL_MIB" ;;
    *coredump.conf) printf '%s\n[Coredump]\nStorage=none\n' "$MANAGED_MARKER" ;;
    *sysctl.conf) printf '%s\nfs.protected_hardlinks = 1\n' "$MANAGED_MARKER" ;;
  esac
}
[[ $(file_status "${FILES[0]}" /dev/null) == NOT_CONFIGURED ]]
make_plan > "$tmp/plan1"
[[ $PLAN_CHANGED == 3 ]]
for file in "${FILES[@]}"; do desired "$file" > "$file"; done
make_plan > "$tmp/plan2"
[[ $PLAN_CHANGED == 0 ]]
cmp -s "${FILES[0]}" <(desired "${FILES[0]}")
printf 'unowned\n' > "${FILES[0]}"
[[ $(file_status "${FILES[0]}" /dev/null) == CONFLICT ]]
printf 'PASS unit: desired state, idempotence and conflict guard\n'
