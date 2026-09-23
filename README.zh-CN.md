# Lite VPS Ops

简体中文 · [English](README.md)

[![CI](https://github.com/s-qin/lite-vps-ops/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/s-qin/lite-vps-ops/actions/workflows/ci.yml) [![Debian 13](https://img.shields.io/badge/Debian_13-Trixie-A81D33?style=flat&logo=debian&logoColor=white)](https://www.debian.org/releases/trixie/) [![Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/) [![Release](https://img.shields.io/github/v/release/s-qin/lite-vps-ops?display_name=tag&style=flat&logo=github)](https://github.com/s-qin/lite-vps-ops/releases/tag/v1.0.0) [![License](https://img.shields.io/github/license/s-qin/lite-vps-ops?style=flat&logo=opensourceinitiative&logoColor=white)](LICENSE)

Lite VPS Ops 是面向小型、长期运行的 **Debian 13 (Trixie)** VPS 的轻量、幂等节点基线工具，提供系统审计、系统维护、SSH 加固、内存韧性、有界日志、保守内核配置、事务化变更和持续健康检查。

当前正式版本为 **v1.0.0**。默认命令是只读的 `audit`。

## 能力

- 审计操作系统、内核、架构、身份、sudo、启动状态、内存、Swap、负载、PSI、OOM、磁盘、inode、Journal、systemd 单元、更新、时间同步、SSH、防火墙状态、受管配置和事务状态。
- 安装所需 Debian 软件包、刷新 apt 元数据、配置禁止自动重启的无人值守更新，并验证时间同步。
- 通过受管 drop-in 应用 SSH 仅密钥认证，使用 `sshd -t` 验证、reload，并在提交 SSH 变更前要求控制端建立第二个独立连接。
- 在主机没有活动 Swap 时创建资源感知的应急 Swap 文件，并应用保守的 swappiness。
- 限制 journald、coredump、tmpfiles、apt cache、transaction、backup 和 receipt 的增长。
- 应用面向网络和内核保护的保守 sysctl 基线。
- 安装只读健康检查程序以及每日 systemd service 和 timer。
- 使用 ownership marker、snapshot、SHA-256 metadata、原子写、维护锁、原生验证器、回滚、重新验证、drift repair 和 JSON/Markdown Receipt。

## 架构

Release 交付流程：

```text
GitHub Release
  -> HTTPS 下载 bootstrap
  -> 下载版本化归档
  -> SHA-256 校验
  -> 临时 staging
  -> 执行
  -> 清理 staging
```

配置变更使用统一事务生命周期：

```text
AUDIT -> SNAPSHOT -> LOCK -> PLAN -> APPLY -> VALIDATE
      -> SSH BLACK-BOX VALIDATE（需要时）-> COMMIT -> RECEIPT
```

发生失败时，事务会回滚受管变更、恢复已捕获的运行时 sysctl 值、重新验证主机，并记录结果。

## 支持范围

- Debian 13 (Trixie)
- 已启动的 systemd 与 apt
- amd64 (`x86_64`) 或 arm64 (`aarch64`)
- `apply` 和 `repair` 需要 root 或免密 sudo
- 需要控制端证明的 SSH 变更使用 SSH 公钥访问
- 典型目标规格：512 MiB 至数 GiB RAM、20–80 GiB 磁盘

Windows 控制器需要 PowerShell 和 OpenSSH。Release 安装需要能够通过 HTTPS 访问 GitHub。

## Roadmap / 计划支持平台

当前正式支持范围仅限于上方列出的系统。计划中的平台适配包括：

- Debian 12 (Bookworm)
- Ubuntu 24.04 LTS
- 其他符合 systemd + apt 架构、并完成独立适配与测试的 Debian/Ubuntu 系发行版

计划中的平台尚未被当前版本正式支持或验证。

## 安装

固定 Release，并在运行前审查 bootstrap：

```bash
curl -fL --proto '=https' --tlsv1.2 \
  -o bootstrap.sh \
  https://github.com/s-qin/lite-vps-ops/releases/download/v1.0.0/bootstrap.sh
less bootstrap.sh
bash bootstrap.sh audit --profile auto
```

在不修改主机的情况下预览 Desired State：

```bash
sudo bash bootstrap.sh apply --profile auto --dry-run
```

会创建或修改 SSH drop-in 的操作必须从仓库检出目录通过控制器运行：

```powershell
.\controller\lite-vps-ops.ps1 `
  -HostAlias my-vps `
  -Profile tiny `
  -Command apply `
  -Version v1.0.0
```

控制器会保持原会话、等待远端 SSH Gate、建立第二个独立连接，并执行最终连续性检查。

## CLI

```text
lite-vps-ops audit      只读的完整主机与受管状态审计（默认）
lite-vps-ops apply      在单个事务中收敛完整基线
lite-vps-ops validate   只读节点基线验收
lite-vps-ops repair     修复已提交受管基线中的 drift
lite-vps-ops health     只读运维健康检查
```

选项：

```text
--profile auto|tiny|standard
--dry-run
--json
--receipt-dir PATH
--version
--help
```

`--ssh-blackbox-token` 仅供控制器使用。

## Profiles

`auto` 在 RAM 不超过 2 GiB 的主机上选择 `tiny`，在更大的主机上选择 `standard`。运行时预算由所选 Profile 与主机实际 RAM、磁盘共同计算。

| 设置 | tiny | standard |
|---|---:|---:|
| Journald 保留时间 | 14 天 | 30 天 |
| Journald 最大值 | 64 MiB | 256 MiB |
| Coredump 存储 | 禁用 | external，最大 128 MiB |
| Swap 范围 | 256–512 MiB | 512–2048 MiB |
| Swappiness | 10 | 10 |
| 保留事务数 | 20 | 30 |
| 事务最长保留时间 | 30 天 | 60 天 |

Swap 会根据检测到的内存和可用磁盘，在 Profile 范围内计算大小。

## 持久对象

Lite VPS Ops 管理以下带 marker 的对象：

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
- 创建 Swap 时使用的 `/swapfile` 和 `/etc/fstab` 中一个带 marker 的 block
- `/var/lib/lite-vps-ops/` 中的状态、锁、事务、备份和 Receipt

## 安全边界

- 默认命令以及所有 `audit`、`validate`、`health` 操作均为只读。
- 受管路径已有无 marker 内容时报告 `CONFLICT`。
- 工具不删除未知业务数据，也不自动重启主机。
- SSH 变更必须通过语法验证和独立连接证明。
- 已有 Host Firewall 规则只审计、不覆盖；Cloud Firewall 策略位于主机基线之外。
- 不修改路由、IPv6 行为、MTU、TCP Buffer 大小或拥塞控制算法。

## 测试

运行本地测试套件和打包检查：

```bash
bash tests/run.sh
shellcheck -S warning lite-vps-ops bootstrap.sh lib/*.sh tests/*.sh scripts/*.sh
bash scripts/package.sh
```

测试覆盖语法、Profile、Desired State、ownership conflict、结构化输出、snapshot、幂等、rollback、rollback failure 报告、dry-run、并发锁、retention、Receipt、bootstrap cleanup 和归档完整性。

GitHub Actions 运行 lint、unit、integration、package、secret-scan 和 Debian 13 container-boundary 作业。v1.0.0 还在已启动 systemd 的 Debian 13.7 主机完成端到端验证，包括控制端 SSH 连续性、重复 apply、validate、repair、health、Release 下载和 checksum 校验。

## 项目链接

- [v1.0.0 Release](https://github.com/s-qin/lite-vps-ops/releases/tag/v1.0.0)
- [Changelog](CHANGELOG.md)
- [Release Notes](RELEASE_NOTES.md)
- [MIT License](LICENSE)

设计参考了 [DannyRuizB/debian-hardening](https://github.com/DannyRuizB/debian-hardening)、[Nuver-Labs/vps-audit](https://github.com/Nuver-Labs/vps-audit) 和 [dev-sec/ansible-collection-hardening](https://github.com/dev-sec/ansible-collection-hardening) 的思路。项目代码为独立实现。
