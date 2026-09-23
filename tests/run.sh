#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
bash -n "$root/lite-vps-ops" "$root/bootstrap.sh" "$root/lib/core.sh" "$root/tests/unit.sh" "$root/tests/integration.sh"
bash "$root/tests/unit.sh"
bash "$root/tests/integration.sh"
