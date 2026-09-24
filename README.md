# Lite VPS Ops

[English](README.md) | [简体中文](README.zh-CN.md)

[![CI](https://github.com/s-qin/lite-vps-ops/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/s-qin/lite-vps-ops/actions/workflows/ci.yml) [![Debian 13](https://img.shields.io/badge/Debian_13-Trixie-A81D33?style=flat&logo=debian&logoColor=white)](https://www.debian.org/releases/trixie/) [![Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/) [![Release](https://img.shields.io/github/v/release/s-qin/lite-vps-ops?display_name=tag&style=flat&logo=github)](https://github.com/s-qin/lite-vps-ops/releases/tag/v1.1.0) [![License](https://img.shields.io/github/license/s-qin/lite-vps-ops?style=flat&logo=opensourceinitiative&logoColor=white)](LICENSE)

Lite VPS Ops is a lightweight tool for host baseline initialization, resilience, security hardening, and health validation on small Debian VPS hosts. Version **v1.1.0** provides a simple PowerShell Deploy/Check experience backed by a transactional Bash engine.

## Capabilities

- Audits a Debian host, computes an explainable resource envelope, and converges the complete baseline in one transaction.
- Configures unattended package maintenance, time synchronization, key-only SSH, bounded journald/coredump storage, conservative sysctl settings, emergency swap, tmpfiles policy, and lightweight health checks.
- Protects SSH changes with an existing connection, an independent second-connection gate, and a post-commit continuity check.
- Uses ownership guards, snapshots, SHA-256 metadata, atomic writes, a maintenance lock, native validators, rollback, drift repair, and JSON/Markdown receipts.
- Pulls checksum-protected release assets into temporary staging and removes the program payload after execution.

## Supported platform

- Debian 13 (Trixie)
- systemd + apt
- amd64 / arm64
- A controller with PowerShell and OpenSSH, plus an SSH host alias with passwordless `sudo`

This is the current tested support boundary.

## Quick start

Clone the release on the controller:

```powershell
git clone --branch v1.1.0 https://github.com/s-qin/lite-vps-ops.git
cd lite-vps-ops
```

Deploy the complete baseline:

```powershell
.\lite-vps-ops.ps1 -Host my-vps
```

Check the committed baseline and current health:

```powershell
.\lite-vps-ops.ps1 -Host my-vps -Check
```

Deploy downloads the v1.1.0 release, verifies SHA-256, performs pre-audit and planning, applies the transaction, proves SSH continuity, validates the result, runs health, writes a receipt, and removes temporary staging. A successful run ends with `NODE_BASELINE_READY=true`.

The daily health timer is enabled by default. To keep manual health while explicitly disabling scheduled runs:

```powershell
.\lite-vps-ops.ps1 -Host my-vps -HealthTimer off
```

The persisted `on` or `off` policy is honored by later repair operations.

## Architecture

The controller downloads `bootstrap.sh` from the selected GitHub Release. Bootstrap creates temporary staging, downloads the matching archive and checksum, verifies the archive, rejects unsafe paths, extracts it, and invokes the Bash engine. Source files and staging are removed on exit.

The engine runs Phase 0–6 audits and one transactional apply path. Managed configuration, state, swap (when created), the health helper/service/timer, transactions, backups, and receipts remain on the host because they are required for validation, repair, rollback, and future upgrades.

## Resource Envelope

`auto` derives deterministic budgets from:

- total and available memory;
- a trusted cgroup memory limit, when lower than host memory;
- root filesystem total, free, and used percentage;
- inode utilization;
- active swap size and swap type.

It computes bounded swap, journal, coredump, disk reserve, and transaction-retention budgets. Inputs and outputs are included in dry-run, JSON output, state, and receipts. The calculation is continuous across the 2 GiB boundary; it does not switch an entire policy at 2048/2049 MiB.

## Profiles

- `auto` — resource-derived budgets; recommended.
- `tiny` — explicit low-resource ceilings.
- `standard` — explicit larger ceilings.

Profiles define policy boundaries. Existing active swap, including a swapfile or partition, is preserved rather than rebuilt.

## Health and timer policy

The health service is a short-lived systemd oneshot. It checks disk, inodes, available memory, swap, OOM events, PSI, time synchronization, failed units, pending updates, reboot-required state, and journal usage.

Memory and I/O PSI use multiple kernel windows and distinguish `INFO`, `WARN_TRANSIENT`, `WARN_SUSTAINED`, and `FAIL`. Health warnings do not change parameters, restart services, or reboot the host. Manual `health` remains available when the timer policy is `off`.

## Advanced and troubleshooting CLI

The v1.0 controller interface remains compatible:

```powershell
.\controller\lite-vps-ops.ps1 -HostAlias my-vps -Command apply -Version v1.1.0
.\controller\lite-vps-ops.ps1 -HostAlias my-vps -Command repair -Version v1.1.0
```

The release Bash engine exposes:

```text
lite-vps-ops deploy
lite-vps-ops check
lite-vps-ops audit [--json]
lite-vps-ops apply [--dry-run]
lite-vps-ops validate [--json]
lite-vps-ops repair
lite-vps-ops health [--json]
```

Common options are `--profile auto|tiny|standard` and `--health-timer on|off`. SSH-changing operations require the controller-generated `--ssh-blackbox-token`.

## Persistent objects

Managed system objects include:

- `/etc/apt/apt.conf.d/52lite-vps-ops-periodic`
- `/etc/apt/apt.conf.d/53lite-vps-ops-unattended`
- `/etc/ssh/sshd_config.d/60-lite-vps-ops.conf`
- `/etc/systemd/journald.conf.d/60-lite-vps-ops.conf`
- `/etc/systemd/coredump.conf.d/60-lite-vps-ops.conf`
- `/etc/sysctl.d/60-lite-vps-ops.conf`
- `/etc/tmpfiles.d/lite-vps-ops.conf`
- `/usr/local/libexec/lite-vps-ops-health`
- `/etc/systemd/system/lite-vps-ops-health.service`
- `/etc/systemd/system/lite-vps-ops-health.timer`
- `/swapfile` when created by Lite VPS Ops
- `/var/lib/lite-vps-ops/` state, transactions, backups, and receipts

Transaction retention enforces count, age, and aggregate byte limits. Cleanup is restricted to directly owned Lite VPS Ops transaction directories and never removes the active transaction or unknown user data.

## Safety boundaries

- Read-only audit, validation, check, health, and dry-run paths do not commit state.
- Unowned managed paths and unknown swap layouts are reported as conflicts.
- SSH is never committed without the controller continuity gate.
- Apply/repair snapshot files, metadata, runtime sysctl values, and timer state before mutation.
- Rollback restores configuration and the timer's previous enabled/active state, then records the outcome.
- The tool never automatically reboots the host and does not replace an existing firewall policy.

## Upgrade from v1.0.0

Deploy v1.1.0 directly over a committed v1.0.0 baseline. Schema-1 state, SSH proof, existing swap, managed objects, and transaction history are preserved. State is upgraded to schema 2 and records the resource envelope, migration source, and health timer policy. No uninstall step is required.

## Testing

The repository tests Bash syntax, ShellCheck, PowerShell parsing, unit behavior, integration, fault injection and rollback, idempotence, schema migration, Deploy/Check wiring, resource-envelope boundaries, count/age/byte retention, timer on/off persistence, transient/sustained health classification, bootstrap cleanup, package integrity, secret scanning, and the Debian 13 container boundary.

Release acceptance additionally requires an end-to-end run on a booted Debian 13 systemd host, including v1.0.0 migration, SSH continuity, repeated deployment, Check, timer on/off persistence, checksums, and Remote Pull from the published v1.1.0 Release.

## Planned platform support

Planned support is not current support. Future releases may add independently tested adaptations for Debian 12 (Bookworm), Ubuntu 24.04 LTS, and other Debian/Ubuntu-family systems compatible with the systemd + apt architecture.

## Project links

- [Changelog](CHANGELOG.md)
- [v1.1.0 Release Notes](RELEASE_NOTES.md)
- [Releases](https://github.com/s-qin/lite-vps-ops/releases)
- [CI](https://github.com/s-qin/lite-vps-ops/actions/workflows/ci.yml)
- [MIT License](LICENSE)
