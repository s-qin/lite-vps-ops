#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=tests/helpers.sh
. "$root/tests/helpers.sh"
make_fixture
trap 'rm -rf -- "$fixture"' EXIT
load_fixture
managed_paths_init
transaction_begin
snapshot_all
apply_managed_configs_except_ssh
apply_ssh_config
checks_reset
add_check 0 os PASS true 'Debian 13'
receipt_write PASS true
  test_python - "$TX_DIR/receipt.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
d = json.loads(p.read_text())
assert d["schema_version"] == 2
assert d["node_baseline_ready"] is True
assert d["ssh"]["apply_status"] == "changed-validated"
assert "ssh_blackbox_verified" not in d
assert "ssh_safety" not in d
assert d["health_timer_policy"] == "on"
assert d["resource_envelope"]["transaction_budget_mib"] == 64
assert d["retention"]["max_bytes"] == 67108864
assert d["checks"][0]["status"] == "PASS"
PY
TX_ACTIVE=false
transaction_release_lock
trap - EXIT INT TERM
rm -rf -- "$fixture"
printf 'PASS receipt: valid structured JSON, SSH apply status, and readiness fields\n'
