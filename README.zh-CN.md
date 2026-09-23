# Lite VPS Ops

简体中文 · [English](README.md)

Lite VPS Ops 是面向 **Debian 13 (Trixie)**、systemd、apt、amd64/arm64 轻量 VPS 的保守型主机基线工具。它审计资源压力和少量系统设置，并可写入有边界的 journald、coredump、sysctl 配置。它不是 CIS 全量加固工具。

## 状态与范围

v0.1.0 是初始版本。当前 Windows 开发环境能够执行语法检查、ShellCheck 和纯 Bash 单元测试。systemd 与内核运行行为仍需在启动完整的 Debian 13 虚拟机中做端到端验证。在该证据形成前，应将 apply 视为**实验性**，先在可丢弃主机上试用。

本版**不自动修改** SSH 认证、防火墙、Swap、apt 更新或重启。尤其 SSH 修改必须先准备独立的第二条真实连接验证。项目不包含任何业务或代理部署逻辑。

## 安装和运行

在 Debian 13 主机上先安装 `systemd-coredump` 软件包，再下载固定版本的 Release bootstrap 文件并检查内容。工具在写入受管配置前检查该依赖。不要将网络响应直接通过管道交给 shell。

```bash
curl -fL --proto '=https' --tlsv1.2 \
  -o bootstrap.sh https://github.com/s-qin/lite-vps-ops/releases/download/v0.1.0/bootstrap.sh
less bootstrap.sh
bash bootstrap.sh audit
bash bootstrap.sh apply --profile tiny --dry-run
sudo bash bootstrap.sh apply --profile tiny
bash bootstrap.sh validate --profile tiny
```

bootstrap 下载 `lite-vps-ops-v0.1.0.tar.gz` 和对应 `.sha256`，校验后在临时目录运行，并在结束时清理。SHA-256 用于检测下载不匹配，**不能独立证明发布者身份**；请固定版本并审查 Release 来源。也可在源码目录运行 `./lite-vps-ops audit`。

## 命令

| 命令 | 行为 |
| --- | --- |
| `audit`（默认） | 只读审计主机资源与期望配置；`--json` 输出精简资源摘要。 |
| `apply` | 必须显式调用、以 root 执行，写入三个受管 drop-in。 |
| `validate` | 只读比较受管文件与指定 Profile；漂移时非零退出。 |
| `repair` | 只修复已由本工具拥有的文件；缺失受管对象时拒绝创建。 |
| `health` | 只读资源报告；根分区或 inode 使用率 80% 警告、90% 失败。可用内存低、开机以来出现 OOM kill 或存在失败单元也触发警告。 |

`--profile auto|tiny|standard` 选择预算。auto 在 RAM 不超过 2 GiB 时选 tiny，否则选 standard。journald 上限：tiny 为根盘 2%、最多 64 MiB；standard 为 3%、最多 256 MiB；下限 16 MiB。tiny 不保存 coredump，standard 限制占用。本版不创建 Swap。sysctl 仅设置 `fs.protected_hardlinks`、`fs.protected_symlinks`、`net.ipv4.tcp_syncookies`。

## 事务和回滚

写入前，工具拒绝非本工具拥有的目标路径，取得维护锁，备份受管文件并记录 SHA-256，记录相关 sysctl 当前值。随后原子写文件，验证有效 systemd 配置或应用 sysctl，并检查 journald 重启命令。失败时恢复文件和 sysctl 值，重新验证并写失败收据。收据与备份保存在权限受限的 `/var/lib/lite-vps-ops/transactions/<run-id>/`。`managed_baseline_ready` 只表示本版有限受管范围通过；更完整的架构尚未实现，因此 `node_baseline_ready` 保持 false。成功事务若需人工回退，请先查看收据与 manifest。本工具不会自动重启。

工具仅拥有 `/etc/systemd/journald.conf.d/`、`/etc/systemd/coredump.conf.d/`、`/etc/sysctl.d/` 下带有自身标记的指定文件。同一路径已有无标记文件会被视为冲突。其他位置的外部配置仍可能影响有效值，应在操作前检查 dry-run 与主机状态。

## 测试

```bash
bash tests/run.sh
shellcheck -S warning lite-vps-ops bootstrap.sh lib/*.sh tests/*.sh
```

CI 执行上述检查及 Debian 13 容器的平台边界检查。容器没有启动完整 systemd，因此 apply/validate 端到端测试明确为 SKIP。未来需用可丢弃 Debian 13 虚拟机验证两次 apply 文件 hash 不变，以及引入 SSH 写入前的真实第二连接黑盒验证。

## 上游参考

架构和安全思路参考 [DannyRuizB/debian-hardening](https://github.com/DannyRuizB/debian-hardening)、[Nuver-Labs/vps-audit](https://github.com/Nuver-Labs/vps-audit) 与 [dev-sec/ansible-collection-hardening](https://github.com/dev-sec/ansible-collection-hardening)。未复制上游代码。幂等、优先验证与回滚思想根据本项目的轻量范围重新实现，未引入广泛 CIS 配置。

许可证：MIT，见 [LICENSE](LICENSE)。
