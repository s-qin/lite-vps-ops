# Lite VPS Ops v1.1.1

Lite VPS Ops v1.1.1 is a narrow usability and safety-model patch over the corrected Shell-first v1.1.0 release.

## What changed

- **One-session deploy:** `sudo bash bootstrap.sh deploy` no longer asks for a second SSH connection, nonce command, external token, confirmation timeout, or manual approval when SSH changes.
- **Transactional SSH apply:** deploy verifies authorized-key access and managed-path ownership, snapshots the previous configuration, writes the owned drop-in atomically, runs `sshd -t`, reloads SSH, verifies the service remains active, and continues through native and full post-apply validation.
- **Failure recovery:** syntax, reload, service, native-validator, or post-apply failures use the existing transaction rollback and revalidation path; a bad candidate is not committed.
- **Smaller product surface:** the reconnect guard library, transient rollback units, ready/proof files, polling lifecycle, CLI flags, Controller token flow, and obsolete Receipt/state proof fields are removed.
- **State compatibility:** schema remains version 2. Existing committed v1.1.0 nodes upgrade in place; old reconnect metadata is removed from persistent state, while each receipt records `ssh.apply_status` for that run.

The v1.1 Resource Envelope, persisted Health Timer policy, Count/Age/Byte retention, transient/sustained PSI classification, no-auto-reboot boundary, ownership checks, Remote Pull with SHA-256, and staging cleanup remain unchanged.

## Quick start

```bash
curl -fL --proto '=https' --tlsv1.2 \
  -o bootstrap.sh https://github.com/s-qin/lite-vps-ops/releases/download/v1.1.1/bootstrap.sh
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

Managed host configuration and schema-2 state remain compatible with v1.1.0. The removed `--ssh-blackbox-token` and `--ssh-confirm-timeout` options were reconnect-gate controls and are no longer accepted. The optional PowerShell Controller remains available as a synchronous compatibility and E2E harness; it is not a normal deployment prerequisite.

## Release validation

- Bash syntax and ShellCheck warning gate
- Unit, integration, fault injection, rollback, rollback-failure, and idempotence
- Noninteractive SSH apply, authorized-key/conflict preconditions, syntax/reload/native failure recovery, and old-artifact absence
- v1.0.0 schema read, committed v1.1.0 schema-2 convergence, and Health Timer on/off persistence
- Resource Envelope boundary and constrained-resource combinations
- Count, age, and byte-budget pruning with foreign-data preservation
- Transient and sustained PSI classification
- Receipt/state validity, bootstrap staging cleanup, package integrity, SHA-256 checks, and secret scan
- Booted Debian 13 systemd Shell-first deploy/check and formal public Release Remote Pull

## Release assets

- `bootstrap.sh`
- `checksums.txt`
- `lite-vps-ops-v1.1.1.tar.gz`
- `lite-vps-ops-v1.1.1.tar.gz.sha256`

Verify downloaded assets with:

```bash
sha256sum -c lite-vps-ops-v1.1.1.tar.gz.sha256
sha256sum -c checksums.txt
```
