# Lite VPS Ops

[简体中文](README.zh-CN.md) · English

Lite VPS Ops is a small, conservative baseline tool for **Debian 13 (Trixie)** VPS hosts with systemd and apt on amd64 or arm64. It audits resource pressure and a few operating system settings, and can apply a bounded configuration for journald, coredump and three low risk sysctl keys. It is not a CIS compliance tool.

## Status and scope

Version 0.1.0 is an initial release. The local Windows development environment can run syntax, ShellCheck and pure Bash unit tests. A booted Debian 13 VM is required to validate systemd and kernel behavior end to end. Until that test is recorded, treat apply as **experimental** and use a disposable Debian 13 host first.

The tool does **not** configure SSH authentication, firewall rules, Swap files, apt updates or automatic reboots. These actions need host specific safeguards, especially a second independent SSH connection before SSH changes. It does not deploy any application or proxy service.

## Install and run

On a Debian 13 host, install the `systemd-coredump` package before apply, then download the pinned Release bootstrap file and inspect it before running. The package check runs before any managed configuration is written. Do not pipe a network response into a shell.

```bash
curl -fL --proto '=https' --tlsv1.2 \
  -o bootstrap.sh https://github.com/s-qin/lite-vps-ops/releases/download/v0.1.0/bootstrap.sh
less bootstrap.sh
bash bootstrap.sh audit
bash bootstrap.sh apply --profile tiny --dry-run
sudo bash bootstrap.sh apply --profile tiny
bash bootstrap.sh validate --profile tiny
```

The bootstrap downloads `lite-vps-ops-v0.1.0.tar.gz` and its `.sha256`, verifies the digest, runs from a temporary directory, and cleans it afterward. SHA-256 detects accidental or mismatched downloads; it does not provide independent publisher authentication. Pin and inspect the Release source. A run from a source checkout is also supported: `./lite-vps-ops audit`.

## Commands

| Command | Behavior |
| --- | --- |
| `audit` (default) | Read-only host and desired-state inspection. `--json` emits a small machine-readable resource summary. |
| `apply` | Explicit root-only write transaction for the three managed drop-ins. |
| `validate` | Read-only comparison of managed files with the selected profile. Nonzero on drift. |
| `repair` | Root-only convergence of previously owned files. Refuses to create a missing managed object. |
| `health` | Read-only resource report; root disk/inode WARN at 80%, FAIL at 90%. Low available RAM, OOM kills since boot or failed units also trigger WARN. |

`--profile auto|tiny|standard` selects the budget. `auto` chooses tiny at up to 2 GiB RAM, standard above that. Journald `SystemMaxUse` is 2% of root disk capped at 64 MiB for tiny, or 3% capped at 256 MiB for standard, with a 16 MiB floor. Tiny disables stored coredumps; standard caps their use. No Swap is created. The sysctl keys are `fs.protected_hardlinks`, `fs.protected_symlinks` and `net.ipv4.tcp_syncookies`.

## Transaction and rollback

Before writing, the tool rejects a path it does not own, takes a maintenance lock, snapshots existing managed files with SHA-256, and records current values of affected sysctl keys. It writes each file atomically, validates the effective systemd configuration or applies the sysctl file, and checks the journald restart command. On failure it restores files and sysctl values and revalidates, then writes a failure receipt. Receipts and backups are under `/var/lib/lite-vps-ops/transactions/<run-id>/` with restricted directory permissions. `managed_baseline_ready` reports success for this release's narrow managed scope; `node_baseline_ready` remains false until the wider architecture is implemented. Review the receipt and manifest before manually reverting a successful transaction. The tool does not perform an automatic reboot.

The tool only owns files with its marker under `/etc/systemd/journald.conf.d/`, `/etc/systemd/coredump.conf.d/` and `/etc/sysctl.d/`. Existing unmarked files at those paths are a conflict. A malicious or invalid external drop-in elsewhere can still affect effective configuration; inspect the dry-run and host state.

## Tests

```bash
bash tests/run.sh
shellcheck -S warning lite-vps-ops bootstrap.sh lib/*.sh tests/*.sh
```

CI runs those tests and a Debian 13 container platform boundary check. The container has no booted systemd, so apply/validate E2E is explicitly skipped. A future disposable Debian 13 VM job should run apply, validate, a second apply with unchanged hashes, and a real SSH black-box check before SSH changes are introduced.

## Attribution

Architecture and safety ideas were informed by [DannyRuizB/debian-hardening](https://github.com/DannyRuizB/debian-hardening), [Nuver-Labs/vps-audit](https://github.com/Nuver-Labs/vps-audit), and [dev-sec/ansible-collection-hardening](https://github.com/dev-sec/ansible-collection-hardening). No upstream code was copied. In particular, idempotence, validator-first writes and rollback are adapted to this tool's smaller scope; broad CIS settings are deliberately excluded.

MIT licensed. See [LICENSE](LICENSE).
