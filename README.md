# Lite VPS Ops

[简体中文](README.zh-CN.md) · English

Lite VPS Ops is a lightweight, idempotent bootstrap, resilience, hardening, and health-baseline tool for **Debian 13 (Trixie)** VPS hosts using systemd and apt on amd64 or arm64. It is designed for small, long-lived servers—typically 512 MiB to a few GiB of RAM and 20–80 GiB disks—not for CIS scoring or application deployment.

Version **1.0.0** implements the complete core node baseline. The default command is read-only.

## Capabilities

- Full host audit: OS/kernel/architecture, identity/sudo, boot/uptime, RAM/MemAvailable, swap, load, memory and IO PSI, OOM, root disk/inodes, journal, logrotate/coredump, SSH effective configuration, time sync, unattended upgrades, failed units, pending updates, reboot-required, firewall state, managed drift, state and transaction count.
- Fresh Debian maintenance: `apt update`, automatic minimal dependencies, unattended upgrades with automatic reboot disabled, and systemd-timesyncd validation.
- SSH safety: authorized-key and sudo guards, an owned `sshd_config.d` drop-in, `sshd -t`, reload, and a mandatory second real controller connection before commit. TCP forwarding remains available.
- Tiny-VPS resilience: resource-aware emergency swap, persistent fstab entry, conservative swappiness, pressure/OOM checks, conflict detection, idempotence and rollback.
- Disk protection: bounded persistent journald, coredump policy, logrotate, tmpfiles, apt autoclean policy, and bounded transaction/backup/receipt retention.
- Conservative sysctl: SYN cookies, source-route and redirect protections, protected links, kptr/dmesg restrictions and ptrace scope. It does not set BBR, MTU, TCP buffers, strict rp_filter, `ip_forward`, or IPv6 RA behavior.
- Long-term operations: read-only `health`, plus a daily systemd service/timer covering disk, inodes, memory, swap, PSI, OOM, journal, time, failed units, updates and reboot-required.
- Transactional delivery: ownership guards, SHA-256 snapshots, atomic writes, maintenance lock, native validators, rollback/revalidation, drift repair, versioned state, and JSON/Markdown receipts.

## Commands

```text
lite-vps-ops audit      # default, read-only
lite-vps-ops apply      # full convergence; root + controller SSH proof
lite-vps-ops validate   # read-only full acceptance
lite-vps-ops repair     # repair a committed v1 managed baseline
lite-vps-ops health     # read-only operational health
```

Options: `--profile auto|tiny|standard`, `--dry-run`, `--json`, `--version`, `--help`, and `--receipt-dir PATH`. `--ssh-blackbox-token` is reserved for the controller launcher.

`auto` selects `tiny` at up to 2 GiB RAM. Budgets are computed from both the profile and actual RAM/disk. Swap is an emergency buffer, never treated as replacement RAM.

## Safe installation

Pin a release, inspect the small bootstrap, then run it. The bootstrap installs its own download prerequisites when apt and root/passwordless sudo are available, downloads the matching archive into `mktemp`, verifies SHA-256, runs it, and cleans staging. It never leaves a Git clone on the server.

```bash
curl -fL --proto '=https' --tlsv1.2 \
  -o bootstrap.sh https://github.com/s-qin/lite-vps-ops/releases/download/v1.0.0/bootstrap.sh
less bootstrap.sh
bash bootstrap.sh audit --profile auto
bash bootstrap.sh apply --profile tiny --dry-run
```

An apply that may create or update the SSH drop-in must be launched from Windows with the controller so a second independent connection can prove continuity:

```powershell
.\controller\lite-vps-ops.ps1 -HostAlias glm-edge-us -Profile tiny -Command apply -Version v1.0.0
```

If the controller proof is absent or times out, no SSH change is committed and the transaction rolls back. A later non-SSH-changing apply can run through `sudo bash bootstrap.sh apply --profile tiny` after the v1 proof is recorded.

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
- `/var/lib/lite-vps-ops/` state and bounded transactions

An existing unmarked target is a `CONFLICT`; unknown business data is never deleted. Package installation is additive and is recorded but not automatically removed during rollback. The tool never automatically reboots.

## Firewall and optional defenses

Host firewall state is audited. v1.0.0 deliberately does not invent a default-deny port allow-list because that could break future services, IPv6, cloud firewall policy, or management paths. Existing nftables/UFW rules are not overwritten. Fail2Ban/sshguard, AIDE, full auditd/CIS, PAM/account policy, and application-specific health are optional/out of the default baseline.

## Migration from v0.1.0

The v0.1.0 tag and release remain immutable. v1 recognizes the exact v0.1 ownership marker for the three historical journald/coredump/sysctl files, snapshots them, and migrates them in place. It adds the missing Phase 1/2/3/4/5/6/7 objects and replaces the old narrow readiness meaning. Only complete validation can report `NODE_BASELINE_READY=true`.

## Testing

```bash
bash tests/run.sh
shellcheck -S warning lite-vps-ops bootstrap.sh lib/*.sh tests/*.sh scripts/*.sh
bash scripts/package.sh
```

Tests cover syntax, desired state, ownership/conflict, JSON, snapshots, idempotence, rollback and rollback failure, lock contention, retention, dry-run, receipts and package integrity. CI labels its Debian container check as a platform boundary only. The v1.0.0 release was also validated on a booted Debian 13.7 systemd host with controller-side SSH continuity and unchanged second-apply hashes; see the release notes and execution record for exact evidence.

## Attribution

The design draws on [DannyRuizB/debian-hardening](https://github.com/DannyRuizB/debian-hardening), [Nuver-Labs/vps-audit](https://github.com/Nuver-Labs/vps-audit), and [dev-sec/ansible-collection-hardening](https://github.com/dev-sec/ansible-collection-hardening). The implementation is independent and intentionally excludes broad CIS settings.

MIT licensed. See [LICENSE](LICENSE).
