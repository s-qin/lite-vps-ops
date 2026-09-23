# Lite VPS Ops

简体中文 · [English](README.md)

Lite VPS Ops 是面向 **Debian 13 (Trixie)**、systemd、apt、amd64/arm64 轻量 VPS 的幂等主机初始化、韧性保护、安全基线与健康验收工具。典型目标为 512 MiB～数 GiB RAM、20～80 GiB 磁盘的长期运行节点；它不是 CIS 打分器，也不部署任何业务。

**v1.0.0** 已实现完整核心 Node Baseline，默认命令保持只读。

## 能力

- 完整审计：OS/Kernel/架构、用户/sudo、boot/uptime、RAM/MemAvailable、Swap、load、memory/IO PSI、OOM、根盘/inode、journal、logrotate/coredump、SSH effective config、时钟、无人值守更新、失败单元、待更新包、reboot-required、防火墙、drift、state 和 transaction。
- Fresh Debian 维护：`apt update`、最小依赖自动安装、unattended-upgrades、禁止自动 reboot、systemd-timesyncd 验收。
- SSH 防失联：authorized_keys/sudo guard、owned drop-in、`sshd -t`、reload，以及提交前由控制端建立第二个真实 SSH 会话；保留 TCP forwarding。
- 小内存韧性：资源感知 emergency swap、fstab 持久化、保守 swappiness、PSI/OOM/Swap pressure、冲突处理、幂等与回滚。
- 磁盘保护：有界 journald、coredump、logrotate、tmpfiles、apt autoclean，以及 transaction/backup/receipt retention。
- 保守 sysctl：SYN cookies、source route/redirect、protected links、kptr/dmesg、ptrace；明确不设置 BBR、MTU、TCP buffer、strict rp_filter、`ip_forward` 或 IPv6 RA。
- 长期 Ops：只读 `health`，以及每日 systemd service/timer，覆盖磁盘、inode、内存、Swap、PSI、OOM、journal、时钟、失败单元、安全更新与重启标志。
- 统一事务：ownership guard、SHA-256 snapshot、原子写、维护锁、原生 validator、rollback/revalidate、repair、版本化 state、JSON/Markdown Receipt。

## CLI

```text
lite-vps-ops audit      # 默认，只读
lite-vps-ops apply      # 完整收敛；需要 root 与控制端 SSH 证明
lite-vps-ops validate   # 只读完整验收
lite-vps-ops repair     # 修复已提交 v1 基线的 drift
lite-vps-ops health     # 只读运维健康检查
```

选项：`--profile auto|tiny|standard`、`--dry-run`、`--json`、`--version`、`--help`、`--receipt-dir PATH`。`--ssh-blackbox-token` 仅供控制端 Launcher 使用。

`auto` 在不超过 2 GiB RAM 时选择 tiny。Journal、Swap 和 retention 都由 Profile 与真实 RAM/Disk 共同计算；Swap 只是应急缓冲，不是第二块 RAM。

## 安全安装

固定 Release、审查 bootstrap 后再执行。Bootstrap 在 apt 与 root/免密 sudo 可用时自动补齐下载依赖，使用 `mktemp` 下载版本归档、校验 SHA-256、执行并清理，不在服务器保留 Git clone。

```bash
curl -fL --proto '=https' --tlsv1.2 \
  -o bootstrap.sh https://github.com/s-qin/lite-vps-ops/releases/download/v1.0.0/bootstrap.sh
less bootstrap.sh
bash bootstrap.sh audit --profile auto
bash bootstrap.sh apply --profile tiny --dry-run
```

首次可能写入 SSH drop-in 的 apply 必须从 Windows 控制端启动：

```powershell
.\controller\lite-vps-ops.ps1 -HostAlias glm-edge-us -Profile tiny -Command apply -Version v1.0.0
```

控制端会在 reload 后建立第二个独立 SSH 会话。证明缺失或超时会使事务回滚，SSH 变更不会提交。v1 证明已记录且 SSH 无变化后，可直接使用 `sudo bash bootstrap.sh apply --profile tiny`。

## 持久对象与安全边界

工具只拥有固定且带 marker 的 apt、SSH、journald、coredump、sysctl、tmpfiles、health runner/service/timer 文件；在无现有 Swap 时拥有 `/swapfile` 与 `/etc/fstab` 中一个明确标记的 block；状态和有界事务位于 `/var/lib/lite-vps-ops/`。完整路径见英文 README。

固定路径已有无 marker 内容时返回 `CONFLICT`；未知业务数据绝不删除。软件包安装是可审计的加法操作，rollback 默认不自动卸载包。工具绝不自动重启。

## Firewall 与 Optional 能力

v1.0.0 审计 host firewall，但不会凭空生成 default-deny 端口清单，以免破坏未来服务、IPv6、云 Firewall 或管理路径；已有 nftables/UFW 不会被覆盖。Fail2Ban/sshguard、AIDE、完整 auditd/CIS、PAM/account 策略和业务健康检查属于 Optional/默认范围外。

## 从 v0.1.0 迁移

v0.1.0 Tag/Release 保持不变。v1 识别历史三个 drop-in 的精确旧 marker，先 Snapshot，再原位迁移，并补齐 Phase 1～7 缺口。旧版“managed baseline”不再等价于节点就绪；只有完整验证才会返回 `NODE_BASELINE_READY=true`。

## 测试与证据

```bash
bash tests/run.sh
shellcheck -S warning lite-vps-ops bootstrap.sh lib/*.sh tests/*.sh scripts/*.sh
bash scripts/package.sh
```

测试覆盖语法、Desired State、ownership/conflict、JSON、snapshot、幂等、rollback/rollback failure、并发锁、retention、dry-run、Receipt 与归档校验。CI 中 Debian container 明确只是 platform-boundary。v1.0.0 还在 booted Debian 13.7 systemd 主机完成控制端 SSH 黑盒连续性、apply/validate、第二次 apply 哈希不变、health 与 repair；精确证据见 Release notes 和执行记录。

## 上游参考

设计参考 [DannyRuizB/debian-hardening](https://github.com/DannyRuizB/debian-hardening)、[Nuver-Labs/vps-audit](https://github.com/Nuver-Labs/vps-audit) 与 [dev-sec/ansible-collection-hardening](https://github.com/dev-sec/ansible-collection-hardening)。本项目独立实现，未引入整套 CIS。

MIT License，见 [LICENSE](LICENSE)。
