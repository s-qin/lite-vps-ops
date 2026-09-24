# Lite VPS Ops

[English](README.md) | [简体中文](README.zh-CN.md)

[![CI](https://github.com/s-qin/lite-vps-ops/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/s-qin/lite-vps-ops/actions/workflows/ci.yml) [![Debian 13](https://img.shields.io/badge/Debian_13-Trixie-A81D33?style=flat&logo=debian&logoColor=white)](https://www.debian.org/releases/trixie/) [![Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/) [![Release](https://img.shields.io/github/v/release/s-qin/lite-vps-ops?display_name=tag&style=flat&logo=github)](https://github.com/s-qin/lite-vps-ops/releases/tag/v1.1.0) [![License](https://img.shields.io/github/license/s-qin/lite-vps-ops?style=flat&logo=opensourceinitiative&logoColor=white)](LICENSE)

Lite VPS Ops 是面向轻量 Debian VPS 的主机基线初始化、韧性保护、安全加固与健康验收工具。**v1.1.0** 通过简单的 PowerShell Deploy/Check 体验调用具备事务保护的 Bash 引擎。

## 能力

- 审计 Debian 主机，计算可解释的 Resource Envelope，并在单个事务中收敛完整基线。
- 配置无人值守软件包维护、时间同步、仅密钥 SSH、有界 journald/coredump、保守 sysctl、Emergency Swap、tmpfiles 策略与轻量健康检查。
- 通过现有连接、独立第二连接 Gate 和提交后连续性检查保护 SSH 变更。
- 使用 ownership guard、snapshot、SHA-256 metadata、原子写、维护锁、原生验证器、回滚、drift repair 和 JSON/Markdown Receipt。
- 将带 checksum 的 Release 资产拉取到临时 staging，并在执行后清除程序载荷。

## 支持平台

- Debian 13 (Trixie)
- systemd + apt
- amd64 / arm64
- 具有 PowerShell 与 OpenSSH 的控制端，以及配置了免密 `sudo` 的 SSH Host alias

以上是当前已经测试的正式支持边界。

## 快速开始

在控制端克隆正式版本：

```powershell
git clone --branch v1.1.0 https://github.com/s-qin/lite-vps-ops.git
cd lite-vps-ops
```

部署完整基线：

```powershell
.\lite-vps-ops.ps1 -Host my-vps
```

检查已提交基线与当前健康状态：

```powershell
.\lite-vps-ops.ps1 -Host my-vps -Check
```

Deploy 会下载 v1.1.0 Release、校验 SHA-256、执行预审计与计划、应用事务、证明 SSH 连续性、验证结果、运行健康检查、写入 Receipt，并清理临时 staging。成功执行以 `NODE_BASELINE_READY=true` 结束。

每日 Health Timer 默认开启。如需保留手工健康检查但明确关闭定时运行：

```powershell
.\lite-vps-ops.ps1 -Host my-vps -HealthTimer off
```

后续 repair 会遵守持久化的 `on` 或 `off` 策略。

## 架构

Controller 从指定 GitHub Release 下载 `bootstrap.sh`。Bootstrap 创建临时 staging，下载匹配的 archive 与 checksum，验证归档、拒绝不安全路径、解压并调用 Bash 引擎。源码和 staging 在退出时清除。

引擎执行 Phase 0–6 审计与单条事务化 apply 路径。Managed Config、State、Swap（由工具创建时）、Health helper/service/timer、Transaction、Backup 与 Receipt 会保留在主机上，用于验证、repair、rollback 与后续升级。

## Resource Envelope

`auto` 根据以下输入计算确定性预算：

- 总内存与可用内存；
- 低于主机内存时可信的 cgroup memory limit；
- Root filesystem 的总量、剩余量与使用率；
- inode 使用率；
- 已启用 Swap 的大小与类型。

算法计算有界的 Swap、Journal、Coredump、Disk Reserve 与 Transaction Retention 预算。输入与输出写入 dry-run、JSON 输出、State 和 Receipt。计算在 2 GiB 边界保持连续，不会因 2048/2049 MiB 切换整套策略。

## Profiles

- `auto` — 依据资源计算预算，推荐使用。
- `tiny` — 明确的低资源上限。
- `standard` — 明确的较大资源上限。

Profile 只定义策略边界。已经启用的 Swap（包括 swapfile 或 partition）会被保留，不会被重建。

## Health 与 Timer 策略

Health service 是短时运行的 systemd oneshot。它检查 Disk、inode、可用内存、Swap、OOM、PSI、时间同步、失败 unit、待更新软件包、reboot-required 与 Journal 用量。

Memory 与 I/O PSI 使用多个内核窗口，区分 `INFO`、`WARN_TRANSIENT`、`WARN_SUSTAINED` 与 `FAIL`。健康告警不会修改参数、重启服务或重启主机。Timer 策略为 `off` 时，手工 `health` 仍然可用。

## Advanced / Troubleshooting CLI

v1.0 Controller 接口保持兼容：

```powershell
.\controller\lite-vps-ops.ps1 -HostAlias my-vps -Command apply -Version v1.1.0
.\controller\lite-vps-ops.ps1 -HostAlias my-vps -Command repair -Version v1.1.0
```

Release 中的 Bash 引擎提供：

```text
lite-vps-ops deploy
lite-vps-ops check
lite-vps-ops audit [--json]
lite-vps-ops apply [--dry-run]
lite-vps-ops validate [--json]
lite-vps-ops repair
lite-vps-ops health [--json]
```

通用选项包括 `--profile auto|tiny|standard` 与 `--health-timer on|off`。会修改 SSH 的操作需要由 Controller 生成 `--ssh-blackbox-token`。

## 持久对象

受管系统对象包括：

- `/etc/apt/apt.conf.d/52lite-vps-ops-periodic`
- `/etc/apt/apt.conf.d/53lite-vps-ops-unattended`
- `/etc/ssh/sshd_config.d/60-lite-vps-ops.conf`
- `/etc/systemd/journald.conf.d/60-lite-vps-ops.conf`
- `/etc/systemd/coredump.conf.d/60-lite-vps-ops.conf`
- `/etc/sysctl.d/60-lite-vps-ops.conf`
- `/etc/tmpfiles.d/lite-vps-ops.conf`
- `/usr/local/libexec/lite-vps-ops-health`
- `/etc/systemd/system/lite-vps-ops-health.service`
- `/etc/systemd/system/lite-vps-ops-health.timer`
- Lite VPS Ops 创建时的 `/swapfile`
- `/var/lib/lite-vps-ops/` 下的 State、Transaction、Backup 与 Receipt

Transaction Retention 同时执行数量、年龄与总字节上限。清理仅限于具有直接 ownership 证据的 Lite VPS Ops Transaction 目录，绝不会删除当前事务或未知用户数据。

## 安全边界

- 只读 audit、validate、check、health 与 dry-run 不提交 State。
- 未受管的目标路径和未知 Swap 布局会报告冲突。
- 未通过 Controller SSH 连续性 Gate 时不会提交 SSH 变更。
- Apply/repair 在变更前 snapshot 文件、metadata、runtime sysctl 与 Timer 状态。
- Rollback 恢复配置和 Timer 之前的 enabled/active 状态，并记录结果。
- 工具不会自动重启主机，也不会替换现有防火墙策略。

## 从 v1.0.0 升级

可直接在已提交的 v1.0.0 基线上部署 v1.1.0。Schema-1 State、SSH proof、现有 Swap、Managed Object 与 Transaction history 都会保留。State 升级到 schema 2，并记录 Resource Envelope、迁移来源与 Health Timer 策略。无需卸载。

## 测试

仓库测试覆盖 Bash 语法、ShellCheck、PowerShell 解析、Unit、Integration、Fault Injection 与 Rollback、幂等、Schema Migration、Deploy/Check wiring、Resource Envelope 边界、Count/Age/Byte Retention、Timer on/off 持久化、Transient/Sustained Health 分类、Bootstrap cleanup、Package integrity、Secret Scan 与 Debian 13 Container Boundary。

Release 验收还要求在已启动 systemd 的真实 Debian 13 主机执行端到端测试，包括 v1.0.0 迁移、SSH 连续性、重复部署、Check、Timer on/off 持久化、Checksum 与从正式 v1.1.0 Release 进行 Remote Pull。

## 计划支持的平台

计划支持不等于当前支持。未来版本可能为 Debian 12 (Bookworm)、Ubuntu 24.04 LTS，以及其他兼容 systemd + apt 架构的 Debian/Ubuntu 系发行版增加经过独立测试的适配。

## 项目链接

- [Changelog](CHANGELOG.md)
- [v1.1.0 Release Notes](RELEASE_NOTES.md)
- [Releases](https://github.com/s-qin/lite-vps-ops/releases)
- [CI](https://github.com/s-qin/lite-vps-ops/actions/workflows/ci.yml)
- [MIT License](LICENSE)
