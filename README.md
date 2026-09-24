# Lite VPS Ops

[简体中文](README.zh-CN.md) · English

[![CI](https://github.com/s-qin/lite-vps-ops/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/s-qin/lite-vps-ops/actions/workflows/ci.yml) [![Debian 13](https://img.shields.io/badge/Debian_13-Trixie-A81D33?style=flat&logo=debian&logoColor=white)](https://www.debian.org/releases/trixie/) [![Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/) [![Release](https://img.shields.io/github/v/release/s-qin/lite-vps-ops?display_name=tag&style=flat&logo=github)](https://github.com/s-qin/lite-vps-ops/releases/tag/v1.1.1) [![License](https://img.shields.io/github/license/s-qin/lite-vps-ops?style=flat&logo=opensourceinitiative&logoColor=white)](LICENSE)

Lite VPS Ops is a lightweight, idempotent bootstrap, resilience, hardening, and health-baseline tool for **Debian 13 (Trixie)** VPS hosts using systemd and apt on amd64 or arm64. It is designed for small, long-lived servers—typically 512 MiB to a few GiB of RAM and 20–80 GiB disks—not for CIS scoring or application deployment.

Version **1.1.1** implements the complete node baseline through a Shell-first Deploy/Check workflow. The default command remains read-only.

## Capabilities

- Full host audit: OS/kernel/architecture, identity/sudo, boot/uptime, RAM/MemAvailable, swap, load, memory and IO PSI, OOM, root disk/inodes, journal, logrotate/coredump, SSH effective configuration, time sync, unattended upgrades, failed units, pending updates, reboot-required, firewall state, managed drift, state and transaction count.
- Fresh Debian maintenance: `apt update`, automatic minimal dependencies, unattended upgrades with automatic reboot disabled, and systemd-timesyncd validation.
- SSH safety: authorized-key access guard, owned `sshd_config.d` drop-in, atomic write, `sshd -t`, reload and active-service validation inside the normal transaction. Apply failures restore and revalidate the previous configuration. TCP forwarding remains available.
- Tiny-VPS resilience: a deterministic Resource Envelope derived from memory, MemAvailable, trusted cgroup limits, root disk/free space, inode pressure, and existing swap; emergency swap, conservative swappiness, conflict detection, idempotence and rollback.
- Disk protection: bounded persistent journald, coredump policy, logrotate, tmpfiles, apt autoclean policy, and owned transaction/backup/receipt retention by count, age, and aggregate bytes.
- Conservative sysctl: SYN cookies, source-route and redirect protections, protected links, kptr/dmesg restrictions and ptrace scope. It does not set BBR, MTU, TCP buffers, strict rp_filter, `ip_forward`, or IPv6 RA behavior.
- Long-term operations: read-only `health`, plus an optional daily systemd service/timer. PSI uses multiple windows to distinguish transient from sustained pressure; warnings do not retune the host or restart services.
- Transactional delivery: ownership guards, SHA-256 snapshots, atomic writes, maintenance lock, native validators, rollback/revalidation, drift repair, versioned state, and JSON/Markdown receipts.

## Quick start

SSH into the Debian 13 VPS, download the fixed-version bootstrap, and deploy:

```bash
curl -fL --proto '=https' --tlsv1.2 \
  -o bootstrap.sh https://github.com/s-qin/lite-vps-ops/releases/download/v1.1.1/bootstrap.sh
sudo bash bootstrap.sh deploy
```

Deploy performs Audit → Plan → Apply → Validate → Health → Receipt. Bootstrap downloads the matching archive into `mktemp`, verifies SHA-256, runs it, and cleans staging; no Git clone or program source remains on the server.

SSH changes are noninteractive: deploy verifies authorized-key access and ownership, writes the managed drop-in atomically, validates it with `sshd -t`, reloads SSH, verifies the service, and continues through post-apply validation. A failure uses the normal transaction rollback and revalidation path.

Check the committed baseline and current health at any time:

```bash
sudo bash bootstrap.sh check
```

## Advanced CLI

The release archive exposes the lifecycle API for troubleshooting and automation:

```text
lite-vps-ops deploy     # full Audit → Plan → Apply → Validate → Health workflow
lite-vps-ops check      # validate the baseline and run manual health
lite-vps-ops audit      # default, read-only
lite-vps-ops apply      # transactional convergence
lite-vps-ops validate   # read-only full acceptance
lite-vps-ops repair     # repair a committed managed baseline
lite-vps-ops health     # read-only operational health
```

Options include `--profile auto|tiny|standard`, `--health-timer on|off`, `--dry-run`, `--json`, `--version`, `--help`, and `--receipt-dir PATH`. The PowerShell Controller remains available as an optional compatibility and test harness.

`auto` continuously computes bounded Swap, Journal, Coredump, disk-reserve, and transaction budgets. `tiny` and `standard` provide explicit policy ceilings. Existing active swap is preserved rather than rebuilt. Resource inputs and budgets are written to dry-run output, state, and receipts.

The daily health timer defaults to `on`. `--health-timer off` disables scheduled runs while keeping manual health available; the choice is persisted and respected by repair.

## Persistent objects

The tool owns only fixed, marked files:

- `/etc/apt/apt.conf.d/52lite-vps-ops-periodic`
- `/etc/apt/apt.conf.d/53lite-vps-ops-unattended`
- `/etc/ssh/sshd_config.d/60-lite-vps-ops.conf`
- `/etc/systemd/journald.conf.d/60-lite-vps-ops.conf`
- `/etc/systemd/coredump.conf.d/60-lite-vps-ops.conf`
- `/etc/sysctl.d/60-lite-vps-ops.conf`
- `/etc/tmpfiles.d/lite-vps-ops.conf`
- `/usr/local/libexec/lite-vps-ops-health`
- `/etc/systemd/system/lite-vps-ops-health.service` and `.timer`
- `/swapfile` and one marked `/etc/fstab` block only when no swap already exists
- `/var/lib/lite-vps-ops/` state, receipts, and bounded transactions

An existing unmarked target is a `CONFLICT`; unknown business data is never deleted. Retention removes only directly owned Lite VPS Ops transaction directories and never the active transaction. Package installation is additive and is recorded but not automatically removed during rollback. The tool never automatically reboots.

## Firewall and optional defenses

Host firewall state is audited. v1.1.1 does not invent a default-deny port allow-list because that could break services, IPv6, cloud firewall policy, or management paths. Existing nftables/UFW rules are not overwritten. Fail2Ban/sshguard, AIDE, full auditd/CIS, PAM/account policy, and application-specific health are optional/out of the default baseline.

## Migration from v1.0.0 or v1.1.0

Run the v1.1.1 deploy directly over a committed v1.0.0 or v1.1.0 baseline. Schema-1 state migrates to schema 2; existing schema-2 state, managed objects, swap, transaction history, Resource Envelope, and Health Timer policy remain compatible. Obsolete v1.1.0 reconnect-proof metadata is removed from persistent state; each receipt records the current SSH apply status. Resource-derived managed values may change; the plan and receipt record the resulting budgets.

## Testing

```bash
bash tests/run.sh
shellcheck -S warning lite-vps-ops bootstrap.sh lib/*.sh tests/*.sh scripts/*.sh
bash scripts/package.sh
```

Tests cover syntax, desired state, ownership/conflict, JSON, snapshots, idempotence, rollback and rollback failure, noninteractive SSH apply and syntax/reload/native failure recovery, lock contention, schema migration, Resource Envelope boundaries, count/age/byte retention, timer policy, transient/sustained health, dry-run, receipts, staging cleanup, and package integrity. CI labels its Debian container check as a platform boundary only. Release acceptance also runs on a booted Debian 13 systemd host through the Shell-first workflow.

## Planned platform support

Planned support is not current support. Future releases may add independently tested adaptations for Debian 12 (Bookworm), Ubuntu 24.04 LTS, and other Debian/Ubuntu-family systems compatible with the systemd + apt architecture.

## Attribution

The design draws on [DannyRuizB/debian-hardening](https://github.com/DannyRuizB/debian-hardening), [Nuver-Labs/vps-audit](https://github.com/Nuver-Labs/vps-audit), and [dev-sec/ansible-collection-hardening](https://github.com/dev-sec/ansible-collection-hardening). The implementation is independent and intentionally excludes broad CIS settings.

[Changelog](CHANGELOG.md) · [v1.1.1 Release Notes](RELEASE_NOTES.md) · [Releases](https://github.com/s-qin/lite-vps-ops/releases) · [CI](https://github.com/s-qin/lite-vps-ops/actions/workflows/ci.yml) · MIT licensed, see [LICENSE](LICENSE).
