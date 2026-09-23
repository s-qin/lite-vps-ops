#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=lib/core.sh
. "$root/lib/core.sh"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
FILES=("$tmp/journal.conf" "$tmp/core.conf" "$tmp/sysctl.conf")
TX_DIR="$tmp/transaction"
install() { mkdir -p "${@: -1}"; }
sysctl() {
  case "$1" in -n) printf '1\n' ;; -w) : ;; *) return 1 ;; esac
}
systemctl() { :; }
systemd-analyze() { :; }
printf '%s\n[Journal]\nSystemMaxUse=32M\n' "$MANAGED_MARKER" > "${FILES[0]}"
printf '%s\n[Coredump]\nStorage=none\n' "$MANAGED_MARKER" > "${FILES[1]}"
before_journal=$(sha "${FILES[0]}")
before_core=$(sha "${FILES[1]}")
snapshot
printf 'corrupted\n' > "${FILES[0]}"
printf 'corrupted\n' > "${FILES[1]}"
printf 'new\n' > "${FILES[2]}"
rollback
[[ $(sha "${FILES[0]}") == "$before_journal" ]]
[[ $(sha "${FILES[1]}") == "$before_core" ]]
[[ ! -e ${FILES[2]} ]]
printf 'PASS integration: snapshot, hash and rollback\n'
