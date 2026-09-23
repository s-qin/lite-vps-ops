# Lite VPS Ops v1.0.0

Lite VPS Ops v1.0.0 delivers a complete, transactional node baseline for small Debian 13 VPS hosts.

## Highlights

- Read-only host audit, baseline validation, drift repair, and operational health commands.
- Fresh Debian package setup, apt metadata refresh, unattended-upgrade policy, and time synchronization validation.
- SSH key-only hardening with syntax validation, reload, independent controller connection proof, and rollback on failure.
- Resource-aware emergency swap with persistent configuration and conservative swappiness.
- Bounded journald, coredump, tmpfiles, apt cache, transaction, backup, and receipt storage.
- Conservative network and kernel sysctl protections.
- Daily systemd health service and timer covering disk, inodes, memory, swap, PSI, OOM, journal usage, time, failed units, updates, and reboot-required state.
- Transaction snapshots, SHA-256 metadata, atomic writes, ownership guards, maintenance locking, native validation, rollback, revalidation, versioned state, and JSON/Markdown receipts.

## Supported systems

- Debian 13 (Trixie) with booted systemd and apt
- amd64 and arm64
- Root or passwordless sudo for managed operations
- SSH public-key access for controller-proved SSH changes

## Verification

The release passed lint, unit, integration, fault-injection, idempotence, dry-run, receipt, retention, lock-contention, bootstrap-cleanup, package-integrity, and secret-scan checks.

End-to-end validation was completed on a booted Debian 13.7 amd64 systemd host, including release download and checksum verification, dependency installation, SSH black-box continuity, apply, repeated idempotent apply, validate, repair, health, systemd timer activation, and receipt generation.

## Release assets

- `bootstrap.sh`
- `checksums.txt`
- `lite-vps-ops-v1.0.0.tar.gz`
- `lite-vps-ops-v1.0.0.tar.gz.sha256`

The bootstrap downloads the versioned archive over HTTPS, verifies its SHA-256 checksum, executes it from temporary staging, and removes staging afterward.
