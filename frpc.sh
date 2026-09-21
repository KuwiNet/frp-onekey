#!/bin/sh
# OpenWrt frpc onekey install script
# Repo: https://github.com/KuwiNet/frp-onekey/tree/openwrt
# ScriptVersion=1.6.9
# Frp install dir: /root/frp
# Service: /etc/init.d/frpc
# Cmd: frpc xxx

SCRIPT_VERSION="1.6.9"
SCRIPT_NAME="frpc.sh"
INSTALL_DIR="/root/frp"
FRPC_BIN="${INSTALL_DIR}/frpc-bin"
FRPC_TOML="${INSTALL_DIR}/frpc.toml"
INIT_FILE="/etc/init.d/frpc"
BIN_LINK="/usr/sbin/frpc"

# 前置依赖检查并自动安装（tar curl wget hexdump）
check_and_install_deps() {
    echo "==> 检查系统依赖工具..."
    NEED_INSTALL=""
    # 检测tar
    if ! command -v tar >/dev/null; then
        echo "⚠️ 未检测到 tar，需要安装"
        NEED_INSTALL="${NEED_INSTALL} tar"
    fi
    # 检测curl / wget，至少需要一个
    HAS_CURL=0
    HAS_WGET=0
    if command -v curl >/dev/null; then HAS_CURL=1; fi
    if command -v wget >/dev/null; then HAS_WGET=1; fi
    if [ ${HAS_CURL} -eq 0 ] && [ ${HAS_WGET} -eq 0 ]; then
        echo "⚠️ 未检测到 wget/curl，需要安装 wget"
        NEED_INSTALL="${NEED_INSTALL} wget"
    fi
    if ! command -v hexdump >/dev/null; then
        echo "⚠️ 未检测到 hexdump，需要安装"
        NEED_INSTALL="${NEED_INSTALL} hexdump"
    fi

    # 有需要安装的包，且opkg可用（OpenWrt）
    if [ -n "${NEED_INSTALL}" ] && command -v opkg >/dev/null; then
        echo "==> 开始更新软件源并安装依赖：${NEED_INSTALL}"
        opkg update
        opkg install ${NEED_INSTALL}
        echo "✅ 依赖安装完成"
    elif [ -n "${NEED_INSTALL}" ] && ! command -v opkg >/dev/null; then
        echo "❌ 缺少依赖: ${NEED_INSTALL}，当前环境不是OpenWrt，无法自动安装，请手动安装后重试"
        exit 1
    fi
}

# 脚本版本检测更新（KuwiNet openwrt分支 raw地址）
check_script_update() {
    echo "==> 检查脚本版本更新..."
    REMOTE_RAW_URL="https://raw.githubusercontent.com/KuwiNet/frp-onekey/openwrt/frpc.sh"
    # 优先选存在的下载工具
    if command -v curl >/dev/null; then
        REMOTE_VER=$(curl -sL ${REMOTE_RAW_URL} 2>/dev/null | grep 'SCRIPT_VERSION=' | head -n1 | cut -d'"' -f2)
    elif command -v wget >/dev/null; then
        REMOTE_VER=$(wget -qO- ${REMOTE_RAW_URL} 2>/dev/null | grep 'SCRIPT_VERSION=' | head -n1 | cut -d'"' -f2)
    fi
    if [ -n "${REMOTE_VER}" ]; then
        if [ "${REMOTE_VER}" != "${SCRIPT_VERSION}" ]; then
            echo "发现新版本脚本: ${REMOTE_VER} (当前:${SCRIPT_VERSION})"
            read -p "是否自动更新脚本? [Y/n] " ans
            ans=${ans:-Y}
            if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
                if command -v curl >/dev/null; then
                    curl -sL ${REMOTE_RAW_URL} -o ./${SCRIPT_NAME}
                else
                    wget -q ${REMOTE_RAW_URL} -O ./${SCRIPT_NAME}
                fi
                chmod +x ./${SCRIPT_NAME}
                echo "脚本更新完成，请重新运行 ./${SCRIPT_NAME} $1"
                exit 0
            fi
        else
            echo "脚本已是最新版本"
        fi
    else
        echo "⚠️ 无法访问github raw，跳过脚本版本检测"
    fi
}

# 获取系统架构
get_arch() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) PLATFORM="linux_amd64" ;;
        i686|i386) PLATFORM="linux_386" ;;
        armv7l) PLATFORM="linux_armv7" ;;
        armv6l) PLATFORM="linux_armv6" ;;
        aarch64) PLATFORM="linux_arm64" ;;
        *) echo "不支持架构: $ARCH"; exit 1 ;;
    esac
    echo "检测架构: ${PLATFORM}"
}

# 获取线上最新frp版本号 + 下载链接
get_frp_info() {
    echo "----------------------------------------"
    echo "请选择下载区域："
    echo "1) 国内(github proxy镜像，推荐)"
    echo "2) 国外(github官方)"
    read -p "输入选项 [1/2] " area

    API_RAW="https://api.github.com/repos/fatedier/frp/releases/latest"
    if [ "$area" = "1" ]; then
        API_RAW="https://mirror.ghproxy.com/${API_RAW}"
    fi

    echo "获取frp最新版本信息..."
    API_CONTENT=$(curl -sL ${API_RAW})
    LATEST_FRPC_VER=$(echo "$API_CONTENT" | awk -F'"' '$2=="tag_name"{print $4;exit}' | sed 's/v//')
    DL_URL=$(echo "$API_CONTENT" | awk -F'"' -v plat="${PLATFORM}.tar.gz" '$2=="browser_download_url" && $4 ~ plat {print $4;exit}')

    if [ -z "${DL_URL}" ] || [ -z "${LATEST_FRPC_VER}" ];then
        echo "❌ 无法获取frp版本或下载链接！PLATFORM=${PLATFORM}"
        exit 1
    fi

    if [ "$area" = "1" ]; then
        DL_URL="https://mirror.ghproxy.com/${DL_URL}"
    fi
    echo "线上最新frp版本: v${LATEST_FRPC_VER}"
    echo "下载链接: ${DL_URL}"
}

# 下载并解压frpc，重命名为frpc-bin，gzip文件头校验
download_frpc() {
    mkdir -p ${INSTALL_DIR}
    TMP_FILE="/tmp/frp.tar.gz"
    echo "开始下载frp..."
    if [ -z "${DL_URL}" ];then
        echo "❌ 获取下载链接失败！"
        exit 1
    fi
    curl -L ${DL_URL} -o ${TMP_FILE}
    if [ ! -f "${TMP_FILE}" ]; then
        echo "❌ 下载失败！"
        exit 1
    fi
    # 判断gzip文件头 1f 8b
    FILE_HEAD=$(head -c2 ${TMP_FILE} | hexdump -ve '1/1 "%02x"')
    if [ "$FILE_HEAD" != "1f8b" ];then
        echo "❌ 下载的不是有效的gzip压缩包，链接获取错误！"
        rm -f ${TMP_FILE}
        exit 1
    fi
    echo "解压..."
    tar -zxf ${TMP_FILE} -C /tmp
    # 提取frpc二进制
    FRPC_TMP=$(find /tmp -maxdepth 2 -name frpc -type f | head -n1)
    if [ -z "${FRPC_TMP}" ];then
        echo "❌ 解压后找不到frpc二进制文件"
        exit 1
    fi
    cp ${FRPC_TMP} ${FRPC_BIN}
    chmod +x ${FRPC_BIN}
    rm -rf /tmp/frp*
    echo "frpc二进制提取完成: ${FRPC_BIN}"
}

# 交互式生成frpc.toml
gen_config() {
    read -p "是否现在交互式填写frpc.toml配置(OIDC认证)? [Y/n] " fillcfg
    fillcfg=${fillcfg:-Y}
    if [ "$fillcfg" != "y" ] && [ "$fillcfg" != "Y" ]; then
        # 默认模板：保留注释ssh代理示例块，修正oidc字段
        cat > ${FRPC_TOML} <<EOF
# 提示：需要前往 https://www.afrp.net 注册获取
serverAddr = "xx.afrp.net"
serverPort = 7000
user = "注册用户名"
auth.method = "oidc"
auth.oidc.clientID = "注册用户名"
auth.oidc.clientSecret = "注册时保存的Client Secret"
auth.oidc.tokenEndpointURL = "https://www.afrp.net/oidc/token.php"
auth.oidc.audience = "afrp.net"
auth.oidc.scope = "afrp"

# [[proxies]]
# name = "ssh"
# type = "tcp"
# localIP = "127.0.0.1"
# localPort = 22
# remotePort = 6000
EOF
        echo "已写入默认frpc.toml（保留ssh示例注释）"
        echo "后续修改配置: vim ${FRPC_TOML}"
        return
    fi

    echo "===== 填写frpc基础必要参数 ====="
    # serverAddr 必填
    while true; do
        read -p "服务端serverAddr(公网IP/域名，必填): " serverAddr
        if [ -n "${serverAddr}" ]; then
            break
        fi
        echo "❌ serverAddr不能为空，请重新输入！"
    done

    # serverPort 必填
    while true; do
        read -p "服务端serverPort(必填): " serverPort
        if [ -n "${serverPort}" ]; then
            break
        fi
        echo "❌ serverPort不能为空，请重新输入！"
    done

    # user
    echo "提示：需要前往 https://www.afrp.net 注册获取"
    while true; do
        read -p "user(注册用户名，必填): " frp_user
        if [ -n "${frp_user}" ]; then
            break
        fi
        echo "❌ user不能为空，请重新输入！"
    done

    # OIDC clientID：默认和user相同，Y直接复用，N自定义输入
    read -p "OIDC clientID 是否和 user(${frp_user}) 相同？ [Y/n] " same_clientid
    same_clientid=${same_clientid:-Y}
    if [ "$same_clientid" = "y" ] || [ "$same_clientid" = "Y" ]; then
        oidc_clientID="${frp_user}"
        echo "✅ clientID复用user值：${oidc_clientID}"
    else
        while true; do
            read -p "OIDC clientID(自定义，必填): " oidc_clientID
            if [ -n "${oidc_clientID}" ]; then
                break
            fi
            echo "❌ clientID不能为空，请重新输入！"
        done
    fi

    # OIDC clientSecret
    while true; do
        read -p "OIDC clientSecret(注册时保存的Client Secret，必填): " oidc_clientSecret
        if [ -n "${oidc_clientSecret}" ]; then
            break
        fi
        echo "❌ clientSecret不能为空，请重新输入！"
    done

    # 交互式模式：基础配置
    cat > ${FRPC_TOML} <<EOF
# 提示：需要前往 https://www.afrp.net 注册获取
serverAddr = "${serverAddr}"
serverPort = ${serverPort}
user = "${frp_user}"
auth.method = "oidc"
auth.oidc.clientID = "${oidc_clientID}"
auth.oidc.clientSecret = "${oidc_clientSecret}"
auth.oidc.tokenEndpointURL = "https://www.afrp.net/oidc/token.php"
auth.oidc.audience = "afrp.net"
auth.oidc.scope = "afrp"
EOF

    # 隧道循环添加
    add_tunnel="y"
    while [ "$add_tunnel" = "y" ] || [ "$add_tunnel" = "Y" ]; do
        echo ""
        echo "==== 添加隧道 ===="
        echo "隧道类型: 1=tcp  2=http  3=https  4=stcp  5=xtcp"
        read -p "选择隧道类型 [1/2/3/4/5]: " ttype
        read -p "隧道名称(唯一): " tname
        read -p "本地IP(默认127.0.0.1): " localIP
        localIP=${localIP:-127.0.0.1}
        read -p "本地端口localPort: " localPort

        echo "[[proxies]]" >> ${FRPC_TOML}
        echo "name = \"${tname}\"" >> ${FRPC_TOML}
        case $ttype in
        1)
            echo "type = \"tcp\"" >> ${FRPC_TOML}
            read -p "remotePort(远端端口): " remotePort
            echo "localIP = \"${localIP}\"" >> ${FRPC_TOML}
            echo "localPort = ${localPort}" >> ${FRPC_TOML}
            echo "remotePort = ${remotePort}" >> ${FRPC_TOML}
            ;;
        2)
            echo "type = \"http\"" >> ${FRPC_TOML}
            read -p "subdomain子域名(可不填，直接回车跳过): " subdomain
            if [ -n "${subdomain}" ];then
                echo "subdomain = \"${subdomain}\"" >> ${FRPC_TOML}
            fi
            read -p "customDomains 域名，逗号分隔(可不填): " domains
            echo "localIP = \"${localIP}\"" >> ${FRPC_TOML}
            echo "localPort = ${localPort}" >> ${FRPC_TOML}
            if [ -n "${domains}" ];then
                echo "customDomains = [\"${domains}\"]" >> ${FRPC_TOML}
            fi
            ;;
        3)
            echo "type = \"https\"" >> ${FRPC_TOML}
            read -p "subdomain子域名(可不填，直接回车跳过): " subdomain
            if [ -n "${subdomain}" ];then
                echo "subdomain = \"${subdomain}\"" >> ${FRPC_TOML}
            fi
            read -p "customDomains 域名，逗号分隔(可不填): " domains
            echo "localIP = \"${localIP}\"" >> ${FRPC_TOML}
            echo "localPort = ${localPort}" >> ${FRPC_TOML}
            if [ -n "${domains}" ];then
                echo "customDomains = [\"${domains}\"]" >> ${FRPC_TOML}
            fi
            ;;
        4)
            echo "type = \"stcp\"" >> ${FRPC_TOML}
            read -p "secretKey: " sk
            echo "localIP = \"${localIP}\"" >> ${FRPC_TOML}
            echo "localPort = ${localPort}" >> ${FRPC_TOML}
            echo "secretKey = \"${sk}\"" >> ${FRPC_TOML}
            ;;
        5)
            echo "type = \"xtcp\"" >> ${FRPC_TOML}
            read -p "secretKey: " sk
            echo "localIP = \"${localIP}\"" >> ${FRPC_TOML}
            echo "localPort = ${localPort}" >> ${FRPC_TOML}
            echo "secretKey = \"${sk}\"" >> ${FRPC_TOML}
            ;;
        esac
        echo "" >> ${FRPC_TOML}
        read -p "继续添加隧道？[Y/n]" add_tunnel
        add_tunnel=${add_tunnel:-Y}
    done
    echo "✅ 配置写入完成: ${FRPC_TOML}"
}

# 写入OpenWrt procd init脚本，包含 log 子命令
install_service() {
cat > ${INIT_FILE} <<'EOF'
#!/bin/sh /etc/rc.common
USE_PROCD=1
START=95
STOP=05

NAME=frpc
BIN="/root/frp/frpc-bin"
CONFIG="/root/frp/frpc.toml"

start_service() {
    procd_open_instance
    procd_set_param command "$BIN" -c "$CONFIG"
    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}

EXTRA_COMMANDS="version config log"
EXTRA_HELP="    version    查看frpc版本
    config     编辑frpc配置文件
    log        实时查看frpc日志"

version() {
    "$BIN" --version
}

config() {
    vi "$CONFIG"
}

log() {
    echo "===== frpc 实时日志（Ctrl+C退出） ====="
    logread -f | grep frpc
}
EOF
    chmod +x ${INIT_FILE}
    ${INIT_FILE} enable
    # 创建软链接 /usr/sbin/frpc 指向init脚本，实现 frpc start
    ln -sf ${INIT_FILE} ${BIN_LINK}
    echo "✅ procd服务安装完成，开机自启已启用，命令 frpc xxx 就绪"
}

# install 主流程
action_install() {
    get_arch
    get_frp_info

    # 判断是否已经安装frpc二进制
    if [ -f "${FRPC_BIN}" ]; then
        echo "✅ 检测到已存在frpc二进制文件"
        CURRENT_FRPC_VER=$(${FRPC_BIN} --version | awk '/frpc/ {print $3}' | sed 's/v//')
        echo "本地frpc版本: v${CURRENT_FRPC_VER}"
        echo "线上最新frp版本: v${LATEST_FRPC_VER}"

        # 版本对比
        if [ "${CURRENT_FRPC_VER}" = "${LATEST_FRPC_VER}" ]; then
            echo "✅ 当前frpc已经是最新版本，跳过二进制下载"
        else
            read -p "发现新版本frpc，是否升级frpc二进制？[Y/n] " upgrade_ans
            upgrade_ans=${upgrade_ans:-Y}
            if [ "$upgrade_ans" = "y" ] || [ "$upgrade_ans" = "Y" ]; then
                echo "停止frpc服务准备升级..."
                ${INIT_FILE} stop 2>/dev/null
                download_frpc
                echo "升级完成"
            else
                echo "跳过frpc二进制升级"
            fi
        fi
    else
        echo "未检测到frpc二进制，开始全新下载安装"
        download_frpc
    fi

    gen_config
    install_service
    echo "=============================================="
    echo "🎉 frpc 安装完成！目录：${INSTALL_DIR}"
    echo "📋 常用命令："
    echo "   frpc start      启动frpc"
    echo "   frpc stop       停止frpc"
    echo "   frpc restart    重启frpc"
    echo "   frpc status     查看运行状态"
    echo "   frpc version    查看frpc版本"
    echo "   frpc config     编辑frpc.toml"
    echo "   frpc log        实时查看frpc日志"
    echo "📄 配置文件：${FRPC_TOML}"
    echo "💡 OpenWrt使用procd，不支持systemctl命令"
    echo "💡 如需直接调用frpc二进制本体：/root/frp/frpc-bin --version"
    echo "=============================================="
}

# update：更新脚本 + 更新frpc二进制
action_update() {
    echo "===== 更新frpc ====="
    check_script_update
    # 更新frpc前同样校验依赖
    check_and_install_deps
    get_arch
    get_frp_info
    echo "停止旧frpc..."
    ${INIT_FILE} stop 2>/dev/null
    download_frpc
    ${INIT_FILE} start
    echo "✅ frpc更新完成"
    ${FRPC_BIN} --version
}

# uninstall 卸载
action_uninstall() {
    echo "===== 卸载frpc ====="
    read -p "确认卸载frpc？会停止服务并删除/root/frp目录 [Y/n] " ans
    ans=${ans:-Y}
    if [ "$ans" != "y" ] && [ "$ans" != "Y" ]; then
        echo "取消卸载"
        exit 0
    fi
    ${INIT_FILE} stop 2>/dev/null
    ${INIT_FILE} disable 2>/dev/null
    rm -f ${INIT_FILE}
    rm -f ${BIN_LINK}
    rm -rf ${INSTALL_DIR}
    echo "✅ 卸载完成"
}

# 主入口
main() {
    # 第一步：依赖检查（每次运行脚本都执行，install/update都需要）
    check_and_install_deps
    check_script_update "$1"
    case "$1" in
        install)
            action_install
            ;;
        update)
            action_update
            ;;
        uninstall)
            action_uninstall
            ;;
        *)
            echo "用法: ./${SCRIPT_NAME} [install|update|uninstall]"
            echo "  install    全新安装frpc，已安装则检测版本更新"
            echo "  update     强制更新脚本和frpc二进制"
            echo "  uninstall  卸载frpc"
            exit 0
    esac
}

main "$@"
