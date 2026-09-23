#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
bash -n "$root/lite-vps-ops" "$root/bootstrap.sh" "$root"/lib/*.sh "$root"/tests/*.sh "$root/scripts/package.sh"
bash "$root/tests/unit.sh"
bash "$root/tests/integration.sh"
bash "$root/tests/fault-injection.sh"
bash "$root/tests/receipt.sh"
bash "$root/tests/dry-run.sh"
bash "$root/tests/retention-lock.sh"
