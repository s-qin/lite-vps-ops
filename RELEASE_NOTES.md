# Lite VPS Ops v1.0.0

v1.0.0 is the first complete Debian 13 node-baseline release. It replaces the deliberately narrow v0.1.0 scope with all core Architecture Spec phases: full read-only audit, Fresh Debian dependency and unattended-update setup, controller-proved SSH hardening, resource-aware emergency swap, bounded journald/coredump/tool state, conservative sysctl, a daily systemd health timer, versioned state, repair, rollback and structured receipts.

Highlights:

- Default command remains read-only `audit`.
- SSH changes require an independent controller connection; failure rolls the transaction back.
- Tiny hosts receive a disk-aware emergency swap buffer, not a fixed “second RAM”.
- Transaction/backup/receipt retention is bounded.
- `health` and `lite-vps-ops-health.timer` cover disk, inode, memory, swap, PSI, OOM, time, failed units, security updates, reboot-required and journal usage.
- The conservative sysctl set deliberately avoids BBR, MTU/TCP buffer tuning, strict rp_filter, `ip_forward`, `accept_ra`, and disabling SSH forwarding.
- v0.1.0 owned files migrate in place; its tag and release remain unchanged.

Verified on a booted Debian 13.7 amd64 systemd host with real controller-side SSH black-box continuity, apply/validate, second-apply hash idempotence, health, repair and release bootstrap checks. The CI Debian container job remains explicitly a platform-boundary test, not a claimed systemd E2E.

Host firewall enforcement and Fail2Ban/sshguard remain conservative/optional: the tool audits existing host firewall state and does not invent an allow-list that could break future service ports. Cloud firewall policy remains an external boundary.
