#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
bash -n "$root/lite-vps-ops" "$root/bootstrap.sh" "$root"/lib/*.sh "$root"/tests/*.sh "$root/scripts/package.sh"
bash "$root/tests/unit.sh"
bash "$root/tests/resource-envelope.sh"
bash "$root/tests/migration-timer.sh"
if command -v pwsh >/dev/null 2>&1; then pwsh -NoProfile -File "$root/tests/ux.ps1"; fi
bash "$root/tests/integration.sh"
bash "$root/tests/ssh-guard.sh"
bash "$root/tests/fault-injection.sh"
bash "$root/tests/receipt.sh"
bash "$root/tests/dry-run.sh"
bash "$root/tests/retention-lock.sh"
bash "$root/tests/bootstrap-cleanup.sh"
