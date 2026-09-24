# Lite VPS Ops v1.1.0

Lite VPS Ops v1.1.0 is the Shell-first upgrade to the Debian 13 transactional host baseline.

> **Corrected and republished release:** the original v1.1.0 publication incorrectly presented a Windows/PowerShell Controller as the normal product entry. This corrected publication keeps the accepted v1.1.0 engineering work, restores the Debian instance Shell as the standard entry, and rebuilds the v1.1.0 tag and assets. Re-download v1.1.0 assets and verify the published SHA-256 files; digests from the withdrawn publication are superseded.

## Highlights

- **Shell Deploy / Check:** SSH into the VPS, download the fixed-version bootstrap, and run one deploy command. No repository clone, Windows host, PowerShell, SSH alias, or specific SSH client is required.
- **SSH rollback and reconnect gate:** when SSH changes, deploy snapshots the previous configuration, validates with `sshd -t`, arms a timed systemd rollback guard, reloads sshd, and waits for a nonce confirmation from a second real SSH connection. Timeout or failure restores the previous SSH configuration. Already-compliant SSH does not trigger the gate.
- **Resource Envelope:** `auto` continuously derives Swap, Journal, Coredump, Disk Reserve, and Transaction budgets from memory, MemAvailable, trusted cgroup limits, root disk facts, inode pressure, and existing swap/type.
- **Health Timer policy:** scheduled health defaults to `on` and can be explicitly set to `off`; manual health remains available and repair preserves the choice.
- **Byte Budget retention:** directly owned transactions are bounded by count, age, and aggregate bytes. Unknown directories and the active transaction are never deleted.
- **Health noise reduction:** memory and I/O PSI are classified across avg10/avg60/avg300 as `INFO`, `WARN_TRANSIENT`, or `WARN_SUSTAINED`; warnings do not trigger automatic tuning, service restarts, or reboot.
- **v1.0.0 upgrade compatibility:** schema-1 state, managed files, existing swap, transaction history, and SSH continuity evidence migrate in place to schema 2.

## Quick start

```bash
curl -fL --proto '=https' --tlsv1.2 \
  -o bootstrap.sh https://github.com/s-qin/lite-vps-ops/releases/download/v1.1.0/bootstrap.sh
sudo bash bootstrap.sh deploy
```

Check the committed baseline and current health:

```bash
sudo bash bootstrap.sh check
```

To disable scheduled health while retaining manual checks:

```bash
sudo bash bootstrap.sh deploy --health-timer off
```

## Compatibility and breaking changes

There are no configuration-breaking changes for a committed v1.0.0 baseline. Resource-derived managed values may change during migration; dry-run, state, and the receipt record the inputs and resulting budgets. The v1.0 Controller interface and advanced Bash lifecycle commands remain available, but the Controller is optional rather than part of the normal support boundary.

## Release validation

- Bash syntax and ShellCheck warning gate
- Unit, integration, fault injection, rollback, rollback-failure, and idempotence
- SSH guard external reconnect success and timeout/failure restoration
- v1.0.0 schema migration and Health Timer on/off persistence
- Resource Envelope boundary and constrained-resource combinations
- Count, age, and byte-budget pruning with foreign-data preservation
- Transient and sustained PSI classification
- Bootstrap staging cleanup, package integrity, SHA-256 checks, and secret scan
- Booted Debian 13 systemd Shell-first deploy/check and formal Release Remote Pull

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
