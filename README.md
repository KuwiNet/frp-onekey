## OpenWrt frpc 一键脚本

Frp 是一个高性能的反向代理应用，可以帮助您轻松地进行内网穿透，对外网提供服务，支持 tcp, http, https 等协议类型，并且 web 服务支持根据域名进行路由转发。

仓库分支：openwrt
自动安装 frpc，支持 OIDC 认证配置向导，procd 托管，开机自启
* 详情：fatedier (https://github.com/fatedier/frp)
* 当前适配上游 frp 版本：**v0.72.0**（由 GitHub Actions 自动跟随上游更新）

### 操作方法

#### 一、安装

国内用户（Gitee 镜像，国内直连最快）：

```shell
wget https://gitee.com/kuwinet/frp-onekey/raw/openwrt/frpc.sh -O frpc.sh && chmod +x frpc.sh
./frpc.sh install
```

国内用户（oproxy.cc 加速，失败自动回退 GitHub 官方）：

```shell
wget https://oproxy.cc/raw.githubusercontent.com/KuwiNet/frp-onekey/openwrt/frpc.sh -O frpc.sh && chmod +x frpc.sh
./frpc.sh install
```

国际用户（GitHub 官方直连）：

```shell
wget https://raw.githubusercontent.com/KuwiNet/frp-onekey/openwrt/frpc.sh -O frpc.sh && chmod +x frpc.sh
./frpc.sh install
```

> 脚本内所有 GitHub 资源（raw 脚本、releases API、release 二进制）均已统一走 oproxy.cc 加速，
> 任一地址失败会自动切换下一个源（oproxy.cc → GitHub 官方 → Gitee 镜像），无需手动改链接。
> Gitee 镜像由 Gitee 的仓库镜像功能自动从 GitHub 同步，Frp 二进制本身仍来自 GitHub Release。

#### 二、修改 frpc 配置

先修改 frpc.toml 文件，确保格式及配置正确无误！文件位置：`/root/frp/frpc.toml`

~~~bash
vi /root/frp/frpc.toml
~~~

#### 三、安装 Frpc、更新、卸载

~~~bash
./frpc.sh install       # 全新安装（已安装则检测版本升级，已有 toml 不会被覆盖）
~~~
~~~bash
./frpc.sh update        # 自动检测更新脚本与二进制，保留原有配置
~~~
~~~bash
./frpc.sh uninstall     # 卸载
~~~

#### 四、快捷命令

~~~bash
frpc start     # 启动服务
~~~
~~~bash
frpc restart   # 重启服务
~~~
~~~bash
frpc stop      # 停止服务
~~~
~~~bash
frpc status    # 查看状态
~~~
~~~bash
frpc version   # 查看版本
~~~
~~~bash
frpc config    # 编辑配置
~~~
~~~bash
frpc log       # 实时日志（logread -f | grep frpc）
~~~
~~~bash
/etc/init.d/frpc enable  # 启用开机自启（install 脚本已经自动执行过）
~~~
~~~bash
/etc/init.d/frpc disable  # 关闭开机自启
~~~
