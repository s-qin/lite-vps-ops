#!/usr/bin/env bash
set -euo pipefail

LVO_VERSION=1.1.0
LVO_SCHEMA_VERSION=2
LVO_ROOT=${LVO_ROOT:-}
LVO_TEST_MODE=${LVO_TEST_MODE:-false}
LVO_STATE_DIR=${LVO_STATE_DIR:-/var/lib/lite-vps-ops}
LVO_LOCK_FILE=${LVO_LOCK_FILE:-/run/lock/lite-vps-ops.lock}
LVO_MANAGED_MARKER='# Managed by lite-vps-ops v1. Do not edit directly.'
LVO_LEGACY_MARKER='# Managed by lite-vps-ops. Edit through the tool or remove after backup.'

LIB_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
. "$LIB_DIR/common.sh"
# shellcheck source=lib/profile.sh
. "$LIB_DIR/profile.sh"
# shellcheck source=lib/checks.sh
. "$LIB_DIR/checks.sh"
# shellcheck source=lib/health.sh
. "$LIB_DIR/health.sh"
# shellcheck source=lib/config.sh
. "$LIB_DIR/config.sh"
# shellcheck source=lib/ssh_guard.sh
. "$LIB_DIR/ssh_guard.sh"
# shellcheck source=lib/transaction.sh
. "$LIB_DIR/transaction.sh"
# shellcheck source=lib/phases.sh
. "$LIB_DIR/phases.sh"
# shellcheck source=lib/receipt.sh
. "$LIB_DIR/receipt.sh"
