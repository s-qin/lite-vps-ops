#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=tests/helpers.sh
. "$root/tests/helpers.sh"
make_fixture
trap 'rm -rf -- "$fixture"' EXIT

load_fixture
PROFILE=auto
LVO_TEST_DISK_MIB=40960 LVO_TEST_FREE_MIB=30000
sed -i 's/MemTotal:        1048576/MemTotal:        2097152/; s/MemAvailable:     786432/MemAvailable:    1572864/' "$fixture/proc/meminfo"
profile_resolve
before=$(resource_envelope_json)
swap_before=$SWAP_MIB
journal_before=$JOURNAL_MIB
profile_resolve
[[ $(resource_envelope_json) == "$before" ]]

sed -i 's/MemTotal:        2097152/MemTotal:        2098176/; s/MemAvailable:    1572864/MemAvailable:    1573888/' "$fixture/proc/meminfo"
PROFILE=auto
profile_resolve
(( SWAP_MIB - swap_before <= 16 && swap_before - SWAP_MIB <= 16 ))
(( JOURNAL_MIB - journal_before <= 4 && journal_before - JOURNAL_MIB <= 4 ))
[[ $PROFILE == auto ]]

LVO_TEST_CGROUP_LIMIT_MIB=768 LVO_TEST_FREE_MIB=900 LVO_TEST_INODE_USED_PERCENT=90 LVO_TEST_SWAP_TYPE=file PROFILE=auto
profile_resolve
[[ $RESOURCE_EFFECTIVE_MEMORY_MIB == 768 ]]
[[ $RESOURCE_SWAP_TYPE == file ]]
[[ $TRANSACTION_KEEP -eq 10 ]]
(( DISK_RESERVE_MIB <= RESOURCE_DISK_FREE_MIB || RESOURCE_FREE_AFTER_RESERVE_MIB == 0 ))
resource_envelope_json | python -m json.tool >/dev/null
printf 'PASS resource envelope: deterministic, continuous boundary, cgroup/disk/inode/swap inputs\n'
