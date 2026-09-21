
# 一键部署 frpc / frps 脚本
> 适配 **systemd Linux 发行版（Ubuntu / Debian / CentOS / Rocky / AlmaLinux）**
> ⚠️ **OpenWrt 请使用 procd 分支脚本，master分支脚本不兼容OpenWrt**
> 上游官方项目：[fatedier/frp](https://github.com/fatedier/frp)

## 📦 frpc 客户端
- 安装目录：`/opt/frp`
- 二进制程序：`/opt/frp/frpc-bin`
- 配置文件：`/opt/frp/frpc.toml`
- Systemd单元：`/etc/systemd/system/frpc.service`

**国外 GitHub 源**
```bash
curl -LO https://raw.githubusercontent.com/KuwiNet/frp-onekey/master/frpc.sh && chmod +x frpc.sh && sudo bash frpc.sh install
```

**国内镜像源（国内服务器优先）**
```bash
curl -LO https://shturl.cc/TBZFMWpdM0D-onekey/raw/master/frpc.sh && chmod +x frpc.sh && sudo bash frpc.sh install
```

## 📦 frps 服务端
- 安装目录：`/opt/frps`
- 二进制程序：`/opt/frps/frps-bin`
- 配置文件：`/opt/frps/frps.toml`
- Systemd单元：`/etc/systemd/system/frps.service`

**国外 GitHub 源**
```bash
curl -LO https://raw.githubusercontent.com/KuwiNet/frp-onekey/master/frps.sh && chmod +x frps.sh && sudo bash frps.sh install
```

**国内镜像源**
```bash
curl -LO shturl.cc/YYafBwCF7UauEaHx9mcJ4bSw9WHQs17EjFQTyHmmfbD4s && chmod +x frps.sh && sudo bash frps.sh install
```

## ⚡ 全局快捷命令（安装完成后直接使用，frps用法完全一致）
```bash
frpc start     # 启动服务，输出中文状态反馈
frpc stop      # 停止服务
frpc restart   # 重启服务
frpc status    # 查看systemd运行状态
frpc enable    # 开启开机自启
frpc disable   # 关闭开机自启
frpc version   # 查看frp二进制版本
frpc config    # vim直接打开编辑配置文件
frpc log       # 实时查看运行日志，Ctrl+C退出
```
> 直接输入不带参数 `frpc`，打印完整帮助信息。

## 🛠 脚本子命令（需要进入脚本所在目录，sudo执行）
```bash
# 安装 / 检测版本升级；已存在toml配置文件不会覆盖原有配置
sudo bash frpc.sh install

# 强制更新frp二进制程序，**完全保留原有toml配置**
sudo bash frpc.sh update

# 完整卸载：停止服务、删除systemd单元、删除程序目录、删除全局命令
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
- ✅ 脚本自更新：优先GitHub raw，网络超时自动降级切换国内镜像源
- ✅ `install`：检测到toml已存在，直接跳过配置向导，**不会覆盖用户配置**
- ✅ `update`：仅更新二进制程序，不改动任何toml配置
- ✅ 下载校验gzip文件头，拦截损坏压缩包
- ✅ 快捷命令提供中文成功/失败执行反馈
- ✅ systemd配置：进程崩溃自动重启，等待网络就绪后启动服务
- ✅ 完整依赖检查，提示缺失软件包的安装命令

## ❓ 常见问题
### 1. command not found: frpc
> 全局包装脚本丢失，重新执行install，**不会覆盖已存在的toml配置**
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

### 4. OpenWrt路由器设备
> ⚠️ 当前master分支脚本仅支持systemd Linux系统。OpenWrt设备请切换至`openwrt`分支下载procd版本脚本。

### 5. install执行会覆盖我的配置吗？
**不会**，脚本判断`frpc.toml`存在时直接跳过配置生成逻辑，仅全新安装（文件不存在）才会生成配置模板或者进入交互式向导。
