# Changelog

## v1.0.0

- Complete Architecture Spec core Phase 0–7 baseline for Debian 13.
- Add Fresh Debian dependency/apt/unattended-update/time setup.
- Add controller-proved SSH hardening with automatic rollback.
- Add resource-aware emergency swap and pressure/OOM validation.
- Add bounded journald, coredump, tmpfiles, apt cache and tool transaction retention.
- Expand the conservative sysctl baseline without performance/routing tuning.
- Add daily systemd health service/timer.
- Replace the v0.1 transaction core with versioned state, structured receipts, drift repair, lock contention and rollback-failure handling.
- Add layered CI and local unit/integration/fault/idempotence/dry-run/receipt/package tests.
- Preserve and migrate the exact v0.1.0 owned drop-ins; keep the historical tag/release unchanged.

## v0.1.0

Initial bounded Debian 13 audit and journald/coredump/sysctl experiment with Release bootstrap. This historical release did not implement the full node baseline.
