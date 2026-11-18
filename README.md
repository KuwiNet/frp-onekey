# 一键部署 frpc / frps 脚本

> 适配 **systemd Linux 发行版（Ubuntu / Debian / CentOS / Rocky / AlmaLinux）**
>
> ⚠️ **OpenWrt 请使用 openwrt 分支脚本，master 分支脚本不兼容 OpenWrt**
>
> 上游官方项目：[fatedier/frp](https://github.com/fatedier/frp)
>
> 当前适配上游 frp 版本：**v0.72.0**（由 GitHub Actions 自动跟随上游更新）

## 🌐 下载入口与加速说明

脚本下载提供固定短链（301 跳转到 **https://oproxy.cc** 加速地址，国内外均可直达），另提供 Gitee 镜像作为国内备用源：

| 用途 | 地址 |
| --- | --- |
| frpc 脚本（短链） | https://frpc.afrp.net |
| frps 脚本（短链） | https://frps.afrp.net |
| Gitee 镜像仓库 | https://gitee.com/kuwinet/frp-onekey |

脚本内部所有 GitHub 资源（releases API、release 二进制、脚本自更新）统一按
**oproxy.cc → GitHub 官方 → Gitee 镜像** 顺序回退，无需手动切换：

```text
https://oproxy.cc/raw.githubusercontent.com/KuwiNet/frp-onekey/master/frpc.sh
https://oproxy.cc/api.github.com/repos/fatedier/frp/releases/latest
https://oproxy.cc/https://github.com/fatedier/frp/releases/download/v0.72.0/frp_0.72.0_linux_amd64.tar.gz
https://gitee.com/kuwinet/frp-onekey/raw/master/frpc.sh
```

> Gitee 仓库由 Gitee 的仓库镜像功能自动从 GitHub 同步，可能比 GitHub 略有延迟；frp 二进制本身仍从 GitHub Release 获取（Gitee 不托管 Release 资产）。

## 🧩 支持架构

上游 frp 从 0.6x 起调整了资产命名（取消 `linux_386`，ARM32 改为 `linux_arm` / `linux_arm_hf`），脚本已按新命名自动匹配：

| 系统架构（`uname -m`） | 使用的上游安装包 |
| --- | --- |
| `x86_64` / `amd64` | `linux_amd64` |
| `aarch64` / `arm64` | `linux_arm64` |
| `armv7l` / `armv8l` | `linux_arm_hf`（不存在时回退 `linux_arm`） |
| `armv6l` | `linux_arm`（不存在时回退 `linux_arm_hf`） |
| `loongarch64` / `loong64` | `linux_loong64` |
| `mips` / `mipsel` / `mips64` / `mips64el` | `linux_mips` / `linux_mipsle` / `linux_mips64` / `linux_mips64le` |
| `riscv64` | `linux_riscv64` |
| `i686` / `i386` | 上游已不再发布 32 位 x86 包，脚本会提示当前无可用的安装包 |

> 脚本会把「候选包全部不存在」当成硬错误处理，并打印上游当前可用的 Linux 包列表，避免下载到 404 页面。

## 📦 frpc 客户端

- 安装目录：`/opt/frpc`
- 二进制程序：`/opt/frpc/frpc-bin`
- 配置文件：`/opt/frpc/frpc.toml`
- Systemd 单元：`/etc/systemd/system/frpc.service`

**安装 frpc**

```bash
curl -L https://frpc.afrp.net -o frpc.sh && chmod +x frpc.sh && sudo bash frpc.sh install
```

> 国内网络访问不畅时，可改用 Gitee 镜像下载（与 GitHub 同源，内容一致）：
>
> ```bash
> curl -L https://gitee.com/kuwinet/frp-onekey/raw/master/frpc.sh -o frpc.sh && chmod +x frpc.sh && sudo bash frpc.sh install
> ```

## 📦 frps 服务端

- 安装目录：`/opt/frps`
- 二进制程序：`/opt/frps/frps-bin`
- 配置文件：`/opt/frps/frps.toml`
- Systemd 单元：`/etc/systemd/system/frps.service`

**安装 frps**

```bash
curl -L https://frps.afrp.net -o frps.sh && chmod +x frps.sh && sudo bash frps.sh install
```

> 国内备用（Gitee 镜像）：
>
> ```bash
> curl -L https://gitee.com/kuwinet/frp-onekey/raw/master/frps.sh -o frps.sh && chmod +x frps.sh && sudo bash frps.sh install
> ```

> 也可以直接使用 Release 资产：`https://github.com/KuwiNet/frp-onekey/releases/latest`

## ⚡ 全局快捷命令（安装完成后直接使用，frps 用法完全一致）

```bash
frpc start     # 启动服务，输出中文状态反馈
frpc stop      # 停止服务
frpc restart   # 重启服务
frpc status    # 查看 systemd 运行状态 + 实际进程 PID
frpc enable    # 开启开机自启
frpc disable   # 关闭开机自启
frpc version   # 查看 frp 二进制版本
frpc config    # vim 直接打开编辑配置文件
frpc log       # 实时查看运行日志，Ctrl+C 退出
```

> 直接输入不带参数 `frpc`，打印完整帮助信息。

## 🛠 脚本子命令（需要进入脚本所在目录，sudo 执行）

```bash
# 安装 / 检测版本升级；已存在 toml 配置文件不会覆盖原有配置
sudo bash frpc.sh install

# 强制更新 frp 二进制程序，完全保留原有 toml 配置
sudo bash frpc.sh update

# 完整卸载：停止服务、删除 systemd 单元、删除程序目录、删除全局命令
sudo bash frpc.sh uninstall
```

## 📎 Systemd 原生备用命令

```bash
sudo systemctl start frpc
sudo systemctl stop frpc
sudo systemctl restart frpc
sudo systemctl status frpc
sudo systemctl enable frpc
sudo systemctl disable frpc

# 原生实时日志
journalctl -fu frpc
```

## ✨ 脚本特性

- ✅ 加速源统一为 **oproxy.cc**，raw / api / release 三类地址全部走加速，失败自动回退 GitHub 官方直连，再退 **Gitee 镜像**
- ✅ 脚本自更新：下载到临时文件后原子替换并自动重新执行，不会覆盖正在运行的脚本导致执行中断
- ✅ `install`：检测到 toml 已存在，直接跳过配置向导，**不会覆盖用户配置**
- ✅ `update`：仅更新二进制程序（frps 同时刷新 404.html），不改动任何 toml 配置
- ✅ 下载校验：gzip 文件头 + `tar -tzf` 完整性双重校验，拦截错误页与损坏包；下载失败自动回滚并恢复原服务
- ✅ 临时文件全部落在独立 `mktemp` 目录，只清理自己产生的文件，不再 `/tmp/frp*` 一次全删
- ✅ 二进制升级前自动判断服务状态，升级成功后自动重启，失败则保留旧二进制并拉起原服务
- ✅ 支持非交互执行（`curl ... | sudo bash -s install`、CI 批量部署），无终端时自动采用默认值
- ✅ 快捷命令提供中文成功/失败执行反馈，PID 使用 `pgrep` 精确匹配
- ✅ systemd 配置：进程崩溃自动重启，`LimitNOFILE=65535`
- ✅ 完整依赖检查（tar / gzip / grep / sed / awk / curl|wget），提示缺失软件包的安装命令

## 🤖 上游版本自动同步

`.github/workflows/sync-upstream-release.yml` 每天定时（并支持手动触发）执行：

1. 读取 `fatedier/frp` 最新 release 版本号；
2. 校验该版本是否仍提供脚本支持的全部平台资产（`linux_amd64 / arm64 / arm / arm_hf / loong64 / mips* / riscv64`），命名规则变化会直接报错提醒；
3. 若上游版本与仓库已发布版本不同：更新脚本头部的 `# Upstream-FRP-Version` 与本 README 的适配版本行并提交；
4. 自动创建与官方一致的 tag（如 `v0.72.0`），并以该 tag 发布 Release，附 `frpc.sh`、`frps.sh`、`frpc-openwrt.sh`、`404.html` 与 `checksums.txt`。

> 脚本本身运行时始终拉取上游最新版本，因此多数情况下无需改动脚本逻辑，工作流只同步版本标记与发布产物。

### Gitee 镜像发布

同一个 Release 会同步发布到 Gitee（`https://gitee.com/kuwinet/frp-onekey`）：

- 代码与 tag 由 **Gitee 仓库镜像功能**自动同步，工作流**不推代码**，因此不会与镜像同步冲突；
- 工作流的独立 job `gitee-release` 只负责创建/更新 Gitee Release 并同步附件（`scripts/gitee_release.py`）；
- 该 job 标记 `continue-on-error`，且未配置令牌时自动跳过 —— **Gitee 侧任何异常都不会影响 GitHub 的发布**；
- 每天都会跑一次做自愈：上次因 tag 未同步而跳过时，下次自动补发；内容无变化时只读不写。

启用方式（只需配置一次）：

1. Gitee → 设置 → 私人令牌，生成令牌并勾选 `projects` 权限；
2. GitHub 仓库 → Settings → Secrets and variables → Actions → 新建 Secret `GITEE_TOKEN`；
3. 如需发布到别的 Gitee 仓库，再加仓库变量 `GITEE_REPO`（默认 `kuwinet/frp-onekey`）。

本地手动补发：

```bash
GITEE_TOKEN=xxx python3 scripts/gitee_release.py \
  --repo kuwinet/frp-onekey --tag v0.72.0 \
  --notes-file release-notes.md --assets-dir ./assets
```

## ❓ 常见问题

### 1. command not found: frpc

> 全局包装脚本丢失，重新执行 install，**不会覆盖已存在的 toml 配置**

```bash
sudo bash frpc.sh install
```

### 2. frpc start 返回 ❌ frpc 启动失败

优先查看日志定位配置语法、网络等错误

```bash
frpc log
```

### 3. 报错缺失 hexdump

```bash
# Debian / Ubuntu
apt update && apt install bsdmainutils

# RHEL / CentOS / Rocky / AlmaLinux
dnf install bsdmainutils
```

### 4. OpenWrt 路由器设备

> ⚠️ 当前 master 分支脚本仅支持 systemd Linux 系统。OpenWrt 设备请切换至 `openwrt` 分支下载 procd 版本脚本。

### 5. install 执行会覆盖我的配置吗？

**不会**，脚本判断 `frpc.toml` 存在时直接跳过配置生成逻辑，仅全新安装（文件不存在）才会生成配置模板或者进入交互式向导。

### 6. 加速域名打不开怎么办？

脚本已内置自动回退：oproxy.cc 失败会自动改走 GitHub 官方直连，仍失败再退 Gitee 镜像；交互安装时也可以在选择下载区域时选 `2) 国外(GitHub 官方)`。
完全没有 GitHub 访问能力时，可直接从 Gitee 镜像下载脚本：`https://gitee.com/kuwinet/frp-onekey/raw/master/frpc.sh`（frp 二进制需要能访问 GitHub Release 或其加速地址）。
