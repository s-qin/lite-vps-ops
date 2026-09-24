# Changelog

## v1.1.1 — 2026-09-24

- Remove the mandatory second SSH connection, nonce confirmation, timed wait, rollback-guard units, and related CLI/Controller controls from the normal SSH-changing deploy path.
- Keep SSH changes inside the standard transaction with authorized-key and ownership preconditions, atomic write, `sshd -t`, reload/active validation, post-apply validation, and rollback/revalidation on failure.
- Keep schema 2 and migrate committed v1.1.0 state in place, removing obsolete reconnect-proof fields from persistent state while recording the current SSH apply status in each receipt.
- Preserve the v1.1 Resource Envelope, Health Timer policy, Count/Age/Byte retention, PSI classification, Remote Pull, and staging cleanup behavior.

## v1.1.0 — 2026-09-24

- Add a Shell-first `deploy` / `check` workflow with an instance-local timed SSH rollback guard and second-connection confirmation only when SSH changes; retain the PowerShell Controller as an optional compatibility and E2E harness.
- Replace the 2 GiB auto-profile split with a deterministic Resource Envelope covering memory, cgroup limits, disk capacity/free space, inode utilization, and existing swap.
- Add a persisted Health Timer `on|off` policy; default to `on`, retain manual health, and preserve explicit `off` during repair.
- Add aggregate byte limits to count/age transaction retention with strict ownership checks.
- Classify PSI as informational, transient, or sustained to reduce single-sample health noise.
- Upgrade state and receipts to schema 2 with migration, timer, retention, resource-budget, and SSH safety evidence.

## v1.0.0 — 2026-09-23

- Initial production release for Debian 13 on amd64 and arm64.
- Transactional host baseline, SSH continuity gate, emergency swap, bounded logs/coredumps, conservative sysctl policy, health timer, drift repair, rollback, and structured receipts.
