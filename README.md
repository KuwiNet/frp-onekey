## OpenWrt frpc 一键脚本
Frp 是一个高性能的反向代理应用，可以帮助您轻松地进行内网穿透，对外网提供服务，支持 tcp, http, https 等协议类型，并且 web 服务支持根据域名进行路由转发。
仓库分支：openwrt
自动安装frpc，支持OIDC认证配置向导，procd托管，开机自启
* 详情：fatedier (https://github.com/fatedier/frp)</br>

### 操作方法
#### 一、安装
```shell
wget https://raw.githubusercontent.com/KuwiNet/frp-onekey/openwrt/frpc.sh -O frpc.sh && chmod +x frpc.sh
./frpc.sh install
```
#### 二、修改Frpc配置
先修改 frpc.toml 文件，确保格式及配置正确无误！文件位置：/root/frp/frpc.toml
~~~bash
vi /usr/local/frpc/frpc.toml
~~~

#### 三、安装Frpc、更新、卸载
~~~bash
./frpc.sh install       # 全新安装
~~~
~~~bash
./frpc.sh update        # 自动检测更新
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
logread -f | grep frpc # 实时日志
~~~
~~~bash
/etc/init.d/frpc enable  # 启用开机自启（install脚本已经自动执行过）
~~~
~~~bash
/etc/init.d/frpc disable  # 关闭开机自启
~~~
