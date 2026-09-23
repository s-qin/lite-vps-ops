# Lite VPS Ops

[简体中文](README.zh-CN.md) · English

[![CI](https://github.com/s-qin/lite-vps-ops/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/s-qin/lite-vps-ops/actions/workflows/ci.yml) [![Debian 13](https://img.shields.io/badge/Debian_13-Trixie-A81D33?style=flat&logo=debian&logoColor=white)](https://www.debian.org/releases/trixie/) [![Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/) [![Release](https://img.shields.io/github/v/release/s-qin/lite-vps-ops?display_name=tag&style=flat&logo=github)](https://github.com/s-qin/lite-vps-ops/releases/tag/v1.0.0) [![License](https://img.shields.io/github/license/s-qin/lite-vps-ops?style=flat&logo=opensourceinitiative&logoColor=white)](LICENSE)

Lite VPS Ops is a lightweight, idempotent node-baseline tool for small, long-lived **Debian 13 (Trixie)** VPS hosts. It provides system auditing, maintenance, SSH hardening, memory resilience, bounded logging, conservative kernel settings, transactional changes, and ongoing health checks.

The current release is **v1.0.0**. The default command is the read-only `audit` command.

## Capabilities

- Audits the operating system, kernel, architecture, identity, sudo access, boot state, memory, swap, load, PSI, OOM events, disk, inodes, journal usage, systemd units, updates, time synchronization, SSH, firewall state, managed configuration, and transaction state.
- Installs the required Debian packages, refreshes apt metadata, configures unattended upgrades without automatic reboot, and validates time synchronization.
- Applies SSH key-only authentication through an owned drop-in, validates it with `sshd -t`, reloads SSH, and requires an independent controller connection before committing an SSH change.
- Creates a resource-aware emergency swap file when the host has no active swap and applies conservative swappiness.
- Bounds journald, coredump, tmpfiles, apt cache, transaction, backup, and receipt growth.
- Applies a conservative sysctl baseline for network and kernel protections.
- Installs a read-only health runner with a daily systemd service and timer.
- Uses ownership markers, snapshots, SHA-256 metadata, atomic writes, a maintenance lock, native validators, rollback, revalidation, drift repair, and JSON/Markdown receipts.

## Architecture

Release delivery follows this flow:

```text
GitHub Release
  -> HTTPS bootstrap download
  -> versioned archive download
  -> SHA-256 verification
  -> temporary staging
  -> execution
  -> staging cleanup
```

Configuration changes follow a single transaction lifecycle:

```text
AUDIT -> SNAPSHOT -> LOCK -> PLAN -> APPLY -> VALIDATE
      -> SSH BLACK-BOX VALIDATE (when required) -> COMMIT -> RECEIPT
```

On failure, the transaction rolls back managed changes, restores captured runtime sysctl values, revalidates the host, and records the result.

## Supported systems

- Debian 13 (Trixie)
- Booted systemd and apt
- amd64 (`x86_64`) or arm64 (`aarch64`)
- Root or passwordless sudo for `apply` and `repair`
- SSH public-key access for controller-proved SSH changes
- Typical target size: 512 MiB to several GiB of RAM and 20–80 GiB of disk

The Windows controller requires PowerShell and OpenSSH. Release installation requires outbound HTTPS access to GitHub.

## Roadmap

Current production support is limited to the systems listed above. Planned platform work includes:

- Debian 12 (Bookworm)
- Ubuntu 24.04 LTS
- Additional Debian/Ubuntu-family distributions that fit the systemd + apt architecture, after dedicated adaptation and testing

Planned platforms are not supported or validated by the current release.

## Installation

Pin the release and inspect the bootstrap before running it:

```bash
curl -fL --proto '=https' --tlsv1.2 \
  -o bootstrap.sh \
  https://github.com/s-qin/lite-vps-ops/releases/download/v1.0.0/bootstrap.sh
less bootstrap.sh
bash bootstrap.sh audit --profile auto
```

Preview the desired state without changing the host:

```bash
sudo bash bootstrap.sh apply --profile auto --dry-run
```

An operation that creates or changes the SSH drop-in must run through the controller from a repository checkout:

```powershell
.\controller\lite-vps-ops.ps1 `
  -HostAlias my-vps `
  -Profile tiny `
  -Command apply `
  -Version v1.0.0
```

The controller keeps the original session open, waits for the remote SSH gate, establishes a second independent connection, and performs a final continuity check.

## CLI

```text
lite-vps-ops audit      Read-only full host and managed-state audit (default)
lite-vps-ops apply      Converge the complete baseline in one transaction
lite-vps-ops validate   Read-only node-baseline acceptance
lite-vps-ops repair     Repair drift in a committed managed baseline
lite-vps-ops health     Read-only operational health check
```

Options:

```text
--profile auto|tiny|standard
--dry-run
--json
--receipt-dir PATH
--version
--help
```

`--ssh-blackbox-token` is reserved for the controller.

## Profiles

`auto` selects `tiny` on hosts with up to 2 GiB of RAM and `standard` on larger hosts. Runtime budgets are derived from the selected profile and the host's actual RAM and disk.

| Setting | tiny | standard |
|---|---:|---:|
| Journald retention | 14 days | 30 days |
| Journald maximum | 64 MiB | 256 MiB |
| Coredump storage | disabled | external, 128 MiB maximum |
| Swap range | 256–512 MiB | 512–2048 MiB |
| Swappiness | 10 | 10 |
| Transactions retained | 20 | 30 |
| Transaction maximum age | 30 days | 60 days |

Swap is sized within the profile range using detected memory and available disk.

## Persistent objects

Lite VPS Ops manages these marked objects:

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
- `/swapfile` and one marked `/etc/fstab` block when swap is created
- `/var/lib/lite-vps-ops/` state, lock, transactions, backups, and receipts

## Safety boundaries

- The default command and all `audit`, `validate`, and `health` operations are read-only.
- Existing unmarked content at a managed path is reported as `CONFLICT`.
- The tool does not delete unknown application data or automatically reboot the host.
- SSH changes require syntax validation and independent connection proof.
- Existing host firewall rules are audited and left intact; cloud firewall policy remains external to the host baseline.
- Routing, IPv6 behavior, MTU, TCP buffer sizing, and congestion-control selection are not modified.

## Testing

Run the local test suite and package checks:

```bash
bash tests/run.sh
shellcheck -S warning lite-vps-ops bootstrap.sh lib/*.sh tests/*.sh scripts/*.sh
bash scripts/package.sh
```

The suite covers syntax, profiles, desired state, ownership conflicts, structured output, snapshots, idempotence, rollback, rollback-failure reporting, dry-run, lock contention, retention, receipts, bootstrap cleanup, and package integrity.

GitHub Actions runs lint, unit, integration, package, secret-scan, and Debian 13 container-boundary jobs. The v1.0.0 release was also validated end to end on a booted Debian 13.7 systemd host, including controller-side SSH continuity, repeated apply, validate, repair, health, release download, and checksum verification.

## Project links

- [v1.0.0 release](https://github.com/s-qin/lite-vps-ops/releases/tag/v1.0.0)
- [Changelog](CHANGELOG.md)
- [Release notes](RELEASE_NOTES.md)
- [MIT License](LICENSE)

The design draws on ideas from [DannyRuizB/debian-hardening](https://github.com/DannyRuizB/debian-hardening), [Nuver-Labs/vps-audit](https://github.com/Nuver-Labs/vps-audit), and [dev-sec/ansible-collection-hardening](https://github.com/dev-sec/ansible-collection-hardening). The implementation is independent.
