#!/usr/bin/env bash
set -euo pipefail

test_python() {
  if command -v python >/dev/null 2>&1; then python "$@"; else python3 "$@"; fi
}

make_fixture() {
  fixture=$(mktemp -d)
  export fixture
  mkdir -p "$fixture/etc/apt/apt.conf.d" "$fixture/etc/ssh/sshd_config.d" \
    "$fixture/etc/systemd/journald.conf.d" "$fixture/etc/systemd/coredump.conf.d" \
    "$fixture/etc/sysctl.d" "$fixture/etc/tmpfiles.d" "$fixture/etc/systemd/system" \
    "$fixture/usr/local/libexec" "$fixture/proc/pressure" "$fixture/proc/sys/kernel/random" \
    "$fixture/var/lib" "$fixture/run"
  cat > "$fixture/etc/os-release" <<'EOF'
ID=debian
VERSION_ID=13
PRETTY_NAME="Debian GNU/Linux 13 (trixie)"
EOF
  cat > "$fixture/proc/meminfo" <<'EOF'
MemTotal:        1048576 kB
MemAvailable:     786432 kB
SwapTotal:        524288 kB
SwapFree:         524288 kB
EOF
  cat > "$fixture/proc/vmstat" <<'EOF'
oom_kill 0
EOF
  cat > "$fixture/proc/swaps" <<'EOF'
Filename                                Type            Size            Used            Priority
/dev/vda2                               partition       524284          0               -2
EOF
  printf 'some avg10=0.00 avg60=0.00 avg300=0.00 total=0\n' > "$fixture/proc/pressure/memory"
  printf 'some avg10=0.00 avg60=0.00 avg300=0.00 total=0\n' > "$fixture/proc/pressure/io"
  printf '0.00 0.00 0.00 1/1 1\n' > "$fixture/proc/loadavg"
  printf '1000.00 0.00\n' > "$fixture/proc/uptime"
  printf '00000000-0000-0000-0000-000000000001\n' > "$fixture/proc/sys/kernel/random/boot_id"
  printf '# fixture fstab\n' > "$fixture/etc/fstab"
}

load_fixture() {
  export LVO_ROOT=$fixture
  export LVO_TEST_MODE=true
  export LVO_STATE_DIR=/var/lib/lite-vps-ops
  export LVO_LOCK_FILE=/run/lock/lite-vps-ops.lock
  export LVO_TEST_DISK_MIB=40960
  export LVO_TEST_FREE_MIB=30000
  SCRIPT_DIR=$root
  PROFILE=tiny
  MODE=apply
  HEALTH_TIMER_REQUESTED=preserve
  # shellcheck source=lib/core.sh
  . "$root/lib/core.sh"
  profile_resolve
  health_timer_policy_resolve
}
