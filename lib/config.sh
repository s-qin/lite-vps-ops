#!/usr/bin/env bash

MANAGED_PATHS=()

managed_paths_init() {
  MANAGED_PATHS=(
    "$(path /etc/apt/apt.conf.d/52lite-vps-ops-periodic)"
    "$(path /etc/apt/apt.conf.d/53lite-vps-ops-unattended)"
    "$(path /etc/ssh/sshd_config.d/60-lite-vps-ops.conf)"
    "$(path /etc/systemd/journald.conf.d/60-lite-vps-ops.conf)"
    "$(path /etc/systemd/coredump.conf.d/60-lite-vps-ops.conf)"
    "$(path /etc/sysctl.d/60-lite-vps-ops.conf)"
    "$(path /etc/tmpfiles.d/lite-vps-ops.conf)"
    "$(path /usr/local/libexec/lite-vps-ops-health)"
    "$(path /etc/systemd/system/lite-vps-ops-health.service)"
    "$(path /etc/systemd/system/lite-vps-ops-health.timer)"
  )
}

desired_config() {
  local file=${1#"${LVO_ROOT%/}"}
  case "$file" in
    /etc/apt/apt.conf.d/52lite-vps-ops-periodic)
      printf '%s\n' "$LVO_MANAGED_MARKER"
      cat <<'EOF'
APT::Periodic::Enable "1";
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
      ;;
    /etc/apt/apt.conf.d/53lite-vps-ops-unattended)
      printf '%s\n' "$LVO_MANAGED_MARKER"
      cat <<'EOF'
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
EOF
      ;;
    /etc/ssh/sshd_config.d/60-lite-vps-ops.conf)
      printf '%s\n' "$LVO_MANAGED_MARKER"
      cat <<'EOF'
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
EOF
      ;;
    /etc/systemd/journald.conf.d/60-lite-vps-ops.conf)
      printf '%s\n[Journal]\n' "$LVO_MANAGED_MARKER"
      printf 'Storage=persistent\nCompress=yes\nSystemMaxUse=%sM\nSystemKeepFree=%sM\nMaxRetentionSec=%s\n' \
        "$JOURNAL_MIB" "$JOURNAL_KEEP_FREE_MIB" "$JOURNAL_RETENTION_SEC"
      ;;
    /etc/systemd/coredump.conf.d/60-lite-vps-ops.conf)
      printf '%s\n[Coredump]\n' "$LVO_MANAGED_MARKER"
      if [[ $COREDUMP_STORAGE == none ]]; then
        printf 'Storage=none\nProcessSizeMax=0\n'
      else
        printf 'Storage=external\nCompress=yes\nMaxUse=%sM\nKeepFree=%sM\n' "$COREDUMP_MAX_MIB" "$JOURNAL_KEEP_FREE_MIB"
      fi
      ;;
    /etc/sysctl.d/60-lite-vps-ops.conf)
      printf '%s\n' "$LVO_MANAGED_MARKER"
      cat <<'EOF'
# Network spoofing and redirect protections. No rp_filter/ip_forward/accept_ra tuning.
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
# Local kernel information and link protections.
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.yama.ptrace_scope = 1
vm.swappiness = 10
EOF
      ;;
    /etc/tmpfiles.d/lite-vps-ops.conf)
      printf '%s\n' "$LVO_MANAGED_MARKER"
      printf 'd /var/lib/lite-vps-ops 0700 root root -\n'
      printf 'd /var/lib/lite-vps-ops/transactions 0700 root root %sd\n' "$TRANSACTION_MAX_AGE_DAYS"
      printf 'D /run/lite-vps-ops 0700 root root -\n'
      ;;
    /usr/local/libexec/lite-vps-ops-health)
      cat <<'EOF'
#!/usr/bin/env bash
# Managed by lite-vps-ops v1. Do not edit directly.
set -euo pipefail
status=PASS
warn() { printf 'WARN %s\n' "$*"; [[ $status == FAIL ]] || status=WARN; }
fail() { printf 'FAIL %s\n' "$*"; status=FAIL; }
disk=$(df -P / | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
inode=$(df -Pi / | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
mem_total=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
mem_available=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
swap_total=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)
swap_free=$(awk '/^SwapFree:/ {print $2}' /proc/meminfo)
oom=$(awk '$1=="oom_kill" {print $2}' /proc/vmstat)
(( disk >= 90 )) && fail "root_disk_percent=$disk" || { (( disk >= 80 )) && warn "root_disk_percent=$disk" || true; }
(( inode >= 90 )) && fail "root_inode_percent=$inode" || { (( inode >= 80 )) && warn "root_inode_percent=$inode" || true; }
(( mem_available * 10 < mem_total )) && warn "mem_available_kib=$mem_available"
(( swap_total == 0 )) && warn 'swap=missing'
(( swap_total > 0 && (swap_total-swap_free)*100/swap_total >= 50 )) && warn "swap_pressure_kib=$((swap_total-swap_free))"
(( oom > 0 )) && warn "oom_kills_since_boot=$oom"
if [[ -r /proc/pressure/memory ]]; then grep -qE 'avg10=([1-9]|0\.[5-9])' /proc/pressure/memory && warn 'memory_psi=elevated' || true; fi
if [[ -r /proc/pressure/io ]]; then grep -qE 'avg10=([1-9]|0\.[5-9])' /proc/pressure/io && warn 'io_psi=elevated' || true; fi
sync=$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)
[[ $sync == yes ]] || warn "time_sync=${sync:-inconclusive}"
failed=$(systemctl --failed --no-legend --plain 2>/dev/null | wc -l)
(( failed > 0 )) && warn "failed_units=$failed"
updates=$(apt-get -s -o Debug::NoLocking=1 upgrade 2>/dev/null | awk '/^Inst / {n++} END {print n+0}')
(( updates > 0 )) && warn "upgradable_packages=$updates"
[[ -e /run/reboot-required ]] && warn 'reboot_required=yes'
journalctl --disk-usage 2>/dev/null | tail -n 1 || warn 'journal_usage=inconclusive'
printf 'HEALTH=%s disk=%s inode=%s mem_available_kib=%s swap_total_kib=%s\n' "$status" "$disk" "$inode" "$mem_available" "$swap_total"
[[ $status != FAIL ]]
EOF
      ;;
    /etc/systemd/system/lite-vps-ops-health.service)
      printf '%s\n' "$LVO_MANAGED_MARKER"
      cat <<'EOF'
[Unit]
Description=Lite VPS Ops periodic health check
After=local-fs.target time-sync.target

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/lite-vps-ops-health
User=root
NoNewPrivileges=yes
PrivateTmp=yes
ProtectHome=yes
ProtectSystem=strict
EOF
      ;;
    /etc/systemd/system/lite-vps-ops-health.timer)
      printf '%s\n' "$LVO_MANAGED_MARKER"
      cat <<'EOF'
[Unit]
Description=Run Lite VPS Ops health check daily

[Timer]
OnCalendar=daily
RandomizedDelaySec=1h
Persistent=true
Unit=lite-vps-ops-health.service

[Install]
WantedBy=timers.target
EOF
      ;;
    *) return 1 ;;
  esac
}

file_status() {
  local file=$1
  if [[ -L $file || ( -e $file && ! -f $file ) ]]; then
    printf 'CONFLICT'; return
  fi
  if [[ ! -e $file ]]; then printf 'NOT_CONFIGURED'; return; fi
  if ! grep -Fqx "$LVO_MANAGED_MARKER" "$file" && ! grep -Fqx "$LVO_LEGACY_MARKER" "$file"; then
    printf 'CONFLICT'; return
  fi
  if cmp -s "$file" <(desired_config "$file"); then printf 'ALREADY_COMPLIANT'; else printf 'UPDATE_REQUIRED'; fi
}

config_plan() {
  managed_paths_init
  PLAN_CHANGED=0
  local file status
  for file in "${MANAGED_PATHS[@]}"; do
    status=$(file_status "$file")
    printf '%s %s\n' "$status" "$file"
    [[ $status == CONFLICT ]] && return 1
    [[ $status == ALREADY_COMPLIANT ]] || PLAN_CHANGED=$((PLAN_CHANGED + 1))
  done
}
