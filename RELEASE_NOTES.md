# Lite VPS Ops v1.1.0

Lite VPS Ops v1.1.0 makes the established Debian 13 baseline easier to operate and more resource-aware while preserving its transactional safety model.

## Highlights

- **Deploy / Check:** normal operation now uses `lite-vps-ops.ps1 -Host <alias>` for deployment and `lite-vps-ops.ps1 -Host <alias> -Check` for validation plus health. The v1.0 controller interface and Bash lifecycle commands remain available for advanced use.
- **Resource Envelope:** `auto` continuously derives Swap, Journal, Coredump, Disk Reserve, and Transaction budgets from memory, MemAvailable, trusted cgroup limits, root disk facts, inode pressure, and existing swap/type. The former 2 GiB all-policy boundary is removed.
- **Health Timer policy:** scheduled health remains enabled by default and can be explicitly set to `off`; manual health remains available, the choice is persisted, and repair respects it.
- **Byte Budget retention:** owned transactions, including their backups and receipts, are bounded by count, age, and aggregate bytes. Unknown directories and the active transaction are not deleted.
- **Health noise reduction:** memory and I/O PSI are classified across avg10/avg60/avg300 as `INFO`, `WARN_TRANSIENT`, or `WARN_SUSTAINED`; warnings never trigger automatic tuning or restarts.
- **v1.0.0 upgrade compatibility:** schema-1 state, SSH proof, managed files, existing swap, and transaction history migrate in place to schema 2.

## Quick start

```powershell
git clone --branch v1.1.0 https://github.com/s-qin/lite-vps-ops.git
cd lite-vps-ops
.\lite-vps-ops.ps1 -Host my-vps
.\lite-vps-ops.ps1 -Host my-vps -Check
```

To disable scheduled health while retaining manual checks:

```powershell
.\lite-vps-ops.ps1 -Host my-vps -HealthTimer off
```

## Breaking changes

None. Existing v1.0.0 controller invocations and advanced Bash commands remain supported. Resource-derived managed values may change during upgrade; the plan, state, and receipt record the resulting budgets.

## Test evidence

- Bash syntax and ShellCheck warning gate
- PowerShell parser and Deploy/Check wiring
- Unit and integration suites
- Fault injection, rollback, rollback-failure reporting, and idempotence
- v1.0.0 schema migration and Health Timer on/off persistence
- Resource Envelope boundary and constrained-resource combinations
- Count, age, and byte-budget pruning with foreign-data preservation
- Transient and sustained PSI classification
- Bootstrap staging cleanup, package integrity, SHA-256 checks, and secret scan
- Debian 13 container boundary and booted Debian 13 systemd end-to-end acceptance

## Release assets

- `bootstrap.sh`
- `checksums.txt`
- `lite-vps-ops-v1.1.0.tar.gz`
- `lite-vps-ops-v1.1.0.tar.gz.sha256`

Verify downloaded assets with:

```bash
sha256sum -c lite-vps-ops-v1.1.0.tar.gz.sha256
sha256sum -c checksums.txt
```
