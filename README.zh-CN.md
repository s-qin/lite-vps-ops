# Lite VPS Ops

简体中文 · [English](README.md)

[![CI](https://github.com/s-qin/lite-vps-ops/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/s-qin/lite-vps-ops/actions/workflows/ci.yml) [![Debian 13](https://img.shields.io/badge/Debian_13-Trixie-A81D33?style=flat&logo=debian&logoColor=white)](https://www.debian.org/releases/trixie/) [![Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/) [![Release](https://img.shields.io/github/v/release/s-qin/lite-vps-ops?display_name=tag&style=flat&logo=github)](https://github.com/s-qin/lite-vps-ops/releases/tag/v1.1.1) [![License](https://img.shields.io/github/license/s-qin/lite-vps-ops?style=flat&logo=opensourceinitiative&logoColor=white)](LICENSE)

Lite VPS Ops 是面向 **Debian 13 (Trixie)**、systemd、apt、amd64/arm64 轻量 VPS 的幂等主机初始化、韧性保护、安全基线与健康验收工具。典型目标为 512 MiB～数 GiB RAM、20～80 GiB 磁盘的长期运行节点；它不是 CIS 打分器，也不部署任何业务。

**v1.1.1** 通过 Shell-first Deploy/Check 工作流交付完整 Node Baseline；默认命令仍保持只读。

## 能力

- 完整审计：OS/Kernel/架构、用户/sudo、boot/uptime、RAM/MemAvailable、Swap、load、memory/IO PSI、OOM、根盘/inode、journal、logrotate/coredump、SSH effective config、时钟、无人值守更新、失败单元、待更新包、reboot-required、防火墙、drift、state 和 transaction。
- Fresh Debian 维护：`apt update`、最小依赖自动安装、unattended-upgrades、禁止自动 reboot、systemd-timesyncd 验收。
- SSH 防失联：authorized_keys access guard、owned drop-in、原子写、`sshd -t`、reload 与 active service 验证都在正常事务内完成；apply 失败时恢复并复验旧配置；保留 TCP forwarding。
- 小内存韧性：Resource Envelope 综合 RAM、MemAvailable、可信 cgroup limit、根盘总量/剩余空间、inode 压力和现有 Swap，确定性计算应急 Swap 与各项预算；保留冲突处理、幂等与回滚。
- 磁盘保护：有界 journald、coredump、logrotate、tmpfiles、apt autoclean，以及按 Count + Age + Total Bytes 限制的自有 transaction/backup/receipt retention。
- 保守 sysctl：SYN cookies、source route/redirect、protected links、kptr/dmesg、ptrace；明确不设置 BBR、MTU、TCP buffer、strict rp_filter、`ip_forward` 或 IPv6 RA。
- 长期 Ops：只读 `health` 与可选每日 systemd service/timer。PSI 结合多个时间窗口区分 transient/sustained pressure；WARN 不会自动改参数或重启服务。
- 统一事务：ownership guard、SHA-256 snapshot、原子写、维护锁、原生 validator、rollback/revalidate、repair、版本化 state、JSON/Markdown Receipt。

## 快速开始

SSH 登录 Debian 13 VPS，下载固定版本 bootstrap 并执行 deploy：

```bash
curl -fL --proto '=https' --tlsv1.2 \
  -o bootstrap.sh https://github.com/s-qin/lite-vps-ops/releases/download/v1.1.1/bootstrap.sh
sudo bash bootstrap.sh deploy
```

Deploy 在一次运行内完成 Audit → Plan → Apply → Validate → Health → Receipt。Bootstrap 使用 `mktemp` 下载匹配的 Release 归档、校验 SHA-256、执行并清理 staging；服务器无需 Git clone，也不会长期保留程序源码。

SSH 变更为非交互流程：deploy 检查 authorized-key access 与 ownership，原子写入受管 drop-in，执行 `sshd -t`，reload SSH 并确认服务状态，然后继续 post-apply validation；失败时走正常 transaction rollback 与 revalidation。

随时检查已提交基线与当前健康状态：

```bash
sudo bash bootstrap.sh check
```

## Advanced CLI

Release 归档保留用于排障与自动化的生命周期 API：

```text
lite-vps-ops deploy     # 完整 Audit → Plan → Apply → Validate → Health 闭环
lite-vps-ops check      # 验证基线并执行手工 health
lite-vps-ops audit      # 默认，只读
lite-vps-ops apply      # 事务式收敛
lite-vps-ops validate   # 只读完整验收
lite-vps-ops repair     # 修复已提交基线的 drift
lite-vps-ops health     # 只读运维健康检查
```

选项包括 `--profile auto|tiny|standard`、`--health-timer on|off`、`--dry-run`、`--json`、`--version`、`--help` 和 `--receipt-dir PATH`。PowerShell Controller 保留为可选兼容与测试 Harness。

`auto` 连续计算有界的 Swap、Journal、Coredump、Disk Reserve 与 Transaction 预算；`tiny` 和 `standard` 提供明确策略上限。已有 active Swap 会保留而非重建。Resource Envelope 的输入和预算写入 dry-run、state 与 Receipt。

每日 Health Timer 默认 `on`。`--health-timer off` 只关闭定时执行，手工 health 始终可用；该选择持久化，repair 会继续尊重它。

## 持久对象与安全边界

工具只拥有以下固定且带 marker 的对象：

- `/etc/apt/apt.conf.d/52lite-vps-ops-periodic`
- `/etc/apt/apt.conf.d/53lite-vps-ops-unattended`
- `/etc/ssh/sshd_config.d/60-lite-vps-ops.conf`
- `/etc/systemd/journald.conf.d/60-lite-vps-ops.conf`
- `/etc/systemd/coredump.conf.d/60-lite-vps-ops.conf`
- `/etc/sysctl.d/60-lite-vps-ops.conf`
- `/etc/tmpfiles.d/lite-vps-ops.conf`
- `/usr/local/libexec/lite-vps-ops-health`
- `/etc/systemd/system/lite-vps-ops-health.service` 与 `.timer`
- 仅在无现有 Swap 时创建的 `/swapfile` 和 `/etc/fstab` 中一个标记 block
- `/var/lib/lite-vps-ops/` 中的 state、Receipt 与有界 transaction

固定路径已有无 marker 内容时返回 `CONFLICT`；未知业务数据绝不删除。Retention 只删除 Lite VPS Ops 直接拥有的 transaction 目录，且绝不删除当前事务。软件包安装是可审计的加法操作，rollback 默认不自动卸载包。工具绝不自动重启。

## Firewall 与 Optional 能力

v1.1.1 审计 host firewall，但不会凭空生成 default-deny 端口清单，以免破坏服务、IPv6、云 Firewall 或管理路径；已有 nftables/UFW 不会被覆盖。Fail2Ban/sshguard、AIDE、完整 auditd/CIS、PAM/account 策略和业务健康检查属于 Optional/默认范围外。

## 从 v1.0.0 或 v1.1.0 迁移

在已提交的 v1.0.0 或 v1.1.0 基线上直接运行 v1.1.1 deploy。Schema-1 state 原地迁移到 schema 2；现有 schema-2 state、受管对象、Swap、transaction history、Resource Envelope 与 Health Timer policy 保持兼容。旧 v1.1.0 reconnect-proof metadata 会从持久 state 中移除，每份 Receipt 记录当前 SSH apply status。资源预算可能产生受管值变化，plan 与 Receipt 会记录结果。

## 测试与证据

```bash
bash tests/run.sh
shellcheck -S warning lite-vps-ops bootstrap.sh lib/*.sh tests/*.sh scripts/*.sh
bash scripts/package.sh
```

测试覆盖语法、Desired State、ownership/conflict、JSON、snapshot、幂等、rollback/rollback failure、非交互 SSH apply 与 syntax/reload/native failure recovery、并发锁、schema migration、Resource Envelope 边界、Count/Age/Byte retention、Timer policy、transient/sustained health、dry-run、Receipt、staging cleanup 与归档校验。CI 中 Debian container 明确只是 platform boundary；正式 Release 还必须在 booted Debian 13 systemd 主机完成 Shell-first E2E。

## 计划支持的平台

Planned support 不等于 current support。未来版本可考虑在独立测试与适配后支持 Debian 12 (Bookworm)、Ubuntu 24.04 LTS，以及其他兼容当前 systemd + apt 架构的 Debian/Ubuntu 系发行版。

## 上游参考

设计参考 [DannyRuizB/debian-hardening](https://github.com/DannyRuizB/debian-hardening)、[Nuver-Labs/vps-audit](https://github.com/Nuver-Labs/vps-audit) 与 [dev-sec/ansible-collection-hardening](https://github.com/dev-sec/ansible-collection-hardening)。本项目独立实现，未引入整套 CIS。

[Changelog](CHANGELOG.md) · [v1.1.1 Release Notes](RELEASE_NOTES.md) · [Releases](https://github.com/s-qin/lite-vps-ops/releases) · [CI](https://github.com/s-qin/lite-vps-ops/actions/workflows/ci.yml) · MIT License，见 [LICENSE](LICENSE)。
