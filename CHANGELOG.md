# Changelog

## v1.1.0 — 2026-09-24

- Add root-level PowerShell Deploy and Check workflows while preserving the v1.0 controller interface and advanced Bash commands.
- Replace the 2 GiB auto-profile split with a deterministic Resource Envelope covering memory, cgroup limits, disk capacity/free space, inode utilization, and existing swap.
- Add a persisted Health Timer `on|off` policy; default to `on`, retain manual health, and preserve explicit `off` during repair.
- Add aggregate byte limits to count/age transaction retention with strict ownership checks.
- Classify PSI as informational, transient, or sustained to reduce single-sample health noise.
- Upgrade state and receipts to schema 2 with migration, timer, retention, and resource-budget evidence.
- Add migration, boundary, timer-policy, retention-budget, package, rollback, and Deploy/Check tests.

## v1.0.0 — 2026-09-23

- Initial production release for Debian 13 on amd64 and arm64.
- Transactional host baseline, SSH continuity gate, emergency swap, bounded logs/coredumps, conservative sysctl policy, health timer, drift repair, rollback, and structured receipts.
