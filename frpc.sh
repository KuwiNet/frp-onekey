#!/bin/sh
# OpenWrt procd frpc onekey install script
# ScriptVersion=2.1.8
# Install dir: /root/frp
# Procd init: /etc/init.d/frpc
# Real wrapper file: /usr/sbin/frpc-wrapper
# Symlink: /usr/sbin/frpc  --> frpc-wrapper
SCRIPT_VERSION="2.1.8"
SCRIPT_NAME="frpc.sh"
INSTALL_DIR="/root/frp"
FRPC_BIN="${INSTALL_DIR}/frpc-bin"
FRPC_TOML="${INSTALL_DIR}/frpc.toml"
INIT_FILE="/etc/init.d/frpc"
WRAPPER_BIN="/usr/sbin/frpc-wrapper"
SYMLINK_BIN="/usr/sbin/frpc"

check_and_install_deps() {
    echo "==> 检查OpenWrt依赖工具..."
    NEED=""
    if ! command -v tar >/dev/null; then
        echo "⚠️ 缺失 tar"
        NEED="${NEED} tar"
    fi
    HAS_CURL=0; HAS_WGET=0
    command -v curl >/dev/null && HAS_CURL=1
    command -v wget >/dev/null && HAS_WGET=1
    if [ ${HAS_CURL} -eq 0 ] && [ ${HAS_WGET} -eq 0 ]; then
        echo "⚠️ 缺失 curl/wget，至少需要其一"
        NEED="${NEED} curl"
    fi
    if ! command -v hexdump >/dev/null; then
        echo "⚠️ 缺失 hexdump"
        NEED="${NEED} bsdmainutils"
    fi

    if [ -n "${NEED}" ]; then
        echo "==> opkg 安装依赖：${NEED}"
        opkg update
        opkg install ${NEED}
        echo "✅ 依赖安装完成"
    fi
}

check_script_update() {
    echo "==> 检查脚本版本更新..."
    GITHUB_RAW="https://raw.githubusercontent.com/KuwiNet/frp-onekey/openwrt/frpc.sh"
    GITEE_RAW="https://shturl.cc/TBZFMWpdM0D-onekey/raw/openwrt/frpc.sh"
    REMOTE_RAW_URL=""
    REMOTE_VER=""
    if command -v curl >/dev/null; then
        REMOTE_VER=$(curl -sL -m 8 ${GITHUB_RAW} 2>/dev/null | grep 'SCRIPT_VERSION=' | head -n1 | cut -d'"' -f2)
    elif command -v wget >/dev/null; then
        REMOTE_VER=$(wget -q -T 8 -O- ${GITHUB_RAW} 2>/dev/null | grep 'SCRIPT_VERSION=' | head -n1 | cut -d'"' -f2)
    fi
    if [ -n "${REMOTE_VER}" ]; then
        REMOTE_RAW_URL="${GITHUB_RAW}"
    else
        echo "⚠️ GitHub raw访问失败，尝试切换Gitee国内镜像源"
        if command -v curl >/dev/null; then
            REMOTE_VER=$(curl -sL -m 8 ${GITEE_RAW} 2>/dev/null | grep 'SCRIPT_VERSION=' | head -n1 | cut -d'"' -f2)
        elif command -v wget >/dev/null; then
            REMOTE_VER=$(wget -q -T 8 -O- ${GITEE_RAW} 2>/dev/null | grep 'SCRIPT_VERSION=' | head -n1 | cut -d'"' -f2)
        fi
        REMOTE_RAW_URL="${GITEE_RAW}"
    fi
    if [ -n "${REMOTE_VER}" ]; then
        if [ "${REMOTE_VER}" != "${SCRIPT_VERSION}" ]; then
            echo "发现新版本脚本: ${REMOTE_VER} (当前:${SCRIPT_VERSION})"
            read -p "是否自动更新脚本? [Y/n] " ans
            ans=${ans:-Y}
            if [ "${ans}" = "y" ] || [ "${ans}" = "Y" ]; then
                if command -v curl >/dev/null; then
                    curl -sL ${REMOTE_RAW_URL} -o ./${SCRIPT_NAME}
                else
                    wget -q ${REMOTE_RAW_URL} -O ./${SCRIPT_NAME}
                fi
                chmod +x ./${SCRIPT_NAME}
                echo "脚本更新完成，请重新执行 ./${SCRIPT_NAME} $1"
                exit 0
            fi
        else
            echo "脚本已是最新版本"
        fi
    else
        echo "⚠️ GitHub/Gitee均无法访问，跳过脚本版本检测"
    fi
}

get_arch() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) PLATFORM="linux_amd64" ;;
        i686|i386) PLATFORM="linux_386" ;;
        armv7l) PLATFORM="linux_armv7" ;;
        armv6l) PLATFORM="linux_armv6" ;;
        aarch64) PLATFORM="linux_arm64" ;;
        *) echo "❌ 不支持架构: $ARCH"; exit 1 ;;
    esac
    echo "检测架构: ${PLATFORM}"
}

get_frp_info() {
    echo "----------------------------------------"
    echo "请选择下载区域："
    echo "1) 国内(github proxy镜像，默认)"
    echo "2) 国外(github官方)"
    read -p "输入选项 [1/2] (默认1): " area
    area=${area:-1}
    API_RAW="https://api.github.com/repos/fatedier/frp/releases/latest"
    if [ "${area}" = "1" ]; then
        API_RAW="https://mirror.ghproxy.com/${API_RAW}"
    fi
    echo "获取frp最新版本信息..."
    if command -v curl >/dev/null; then
        API_CONTENT=$(curl -sL ${API_RAW})
    else
        API_CONTENT=$(wget -qO- ${API_RAW})
    fi
    LATEST_FRPC_VER=$(echo "$API_CONTENT" | awk -F'"' '$2=="tag_name"{print $4;exit}' | sed 's/v//')
    DL_URL=$(echo "$API_CONTENT" | awk -F'"' -v plat="${PLATFORM}.tar.gz" '$2=="browser_download_url" && $4 ~ plat {print $4;exit}')
    if [ -z "${DL_URL}" ] || [ -z "${LATEST_FRPC_VER}" ]; then
        echo "❌ 无法获取frp版本或下载链接！PLATFORM=${PLATFORM}"
        exit 1
    fi
    if [ "${area}" = "1" ]; then
        DL_URL="https://mirror.ghproxy.com/${DL_URL}"
    fi
    echo "线上最新frp版本: v${LATEST_FRPC_VER}"
    echo "下载链接: ${DL_URL}"
}

download_frpc() {
    mkdir -p ${INSTALL_DIR}
    TMP_FILE="/tmp/frp.tar.gz"
    echo "开始下载frp..."
    if [ -z "${DL_URL}" ]; then
        echo "❌ 获取下载链接失败！"
        exit 1
    fi
    if command -v curl >/dev/null; then
        curl -L ${DL_URL} -o ${TMP_FILE}
    else
        wget ${DL_URL} -O ${TMP_FILE}
    fi
    if [ ! -f "${TMP_FILE}" ]; then
        echo "❌ 下载失败！"
        exit 1
    fi
    FILE_HEAD=$(head -c2 ${TMP_FILE} | hexdump -ve '1/1 "%02x"')
    if [ "${FILE_HEAD}" != "1f8b" ]; then
        echo "❌ 下载的不是有效的gzip压缩包，链接获取错误！"
        rm -f ${TMP_FILE}
        exit 1
    fi
    echo "解压..."
    tar -zxf ${TMP_FILE} -C /tmp
    FRPC_TMP=$(find /tmp -maxdepth 2 -name frpc -type f | head -n1)
    if [ -z "${FRPC_TMP}" ]; then
        echo "❌ 解压后找不到frpc二进制文件"
        exit 1
    fi
    cp ${FRPC_TMP} ${FRPC_BIN}
    chmod +x ${FRPC_BIN}
    rm -rf /tmp/frp*
    echo "frpc二进制提取完成: ${FRPC_BIN}"
}

gen_config() {
    read -p "是否现在交互式填写frpc.toml客户端配置? [Y/n] " fillcfg
    fillcfg=${fillcfg:-Y}
    if [ ! "${fillcfg}" = "Y" ] && [ ! "${fillcfg}" = "y" ]; then
        cat > ${FRPC_TOML} <<EOF
# frpc 客户端模板
serverAddr = "xx.afrp.net"
serverPort = 7000
user = "username"

# --------认证二选一，请取消对应注释-----------
# OIDC认证
# auth.method = "oidc"
# auth.oidc.clientID = "username"
# auth.oidc.clientSecret = "secret"
# auth.oidc.issuer = "https://oidc.afrp.net"
# auth.oidc.audience = "afrp.net"
# auth.oidc.scope = "afrp"

# Token认证
# auth.method = "token"
# auth.token = "your-token-here"

# [[proxies]]
# name = "ssh"
# type = "tcp"
# localIP = "127.0.0.1"
# localPort = 22
# remotePort = 6000
EOF
        echo "已写入完整注释frpc.toml模板，请手动选择认证方式取消注释"
        echo "后续修改配置: vi ${FRPC_TOML}"
        return
    fi

    echo "===== 选择认证模式 ====="
    echo "1) OIDC 认证"
    echo "2) Token 认证"
    read -p "输入选项 [1/2]: " auth_mode

    echo "===== 填写frpc基础参数 ====="
    while true; do
        read -p "serverAddr(服务端域名/IP，必填): " serverAddr
        [ -n "${serverAddr}" ] && break
        echo "❌ serverAddr不能为空，请重新输入！"
    done
    while true; do
        read -p "serverPort(服务端端口，必填，默认7000): " serverPort
        serverPort=${serverPort:-7000}
        [ -n "${serverPort}" ] && break
        echo "❌ serverPort不能为空，请重新输入！"
    done
    while true; do
        read -p "user(客户端用户名，必填): " frp_user
        [ -n "${frp_user}" ] && break
        echo "❌ user不能为空，请重新输入！"
    done

    oidc_clientID=""
    oidc_clientSecret=""
    oidc_issuer=""
    oidc_audience=""
    oidc_scope=""
    auth_token=""
    if [ "${auth_mode}" = "1" ]; then
        echo "----- OIDC认证参数 -----"
        read -p "OIDC clientID 是否和 user(${frp_user}) 相同？ [Y/n] " same_clientid
        same_clientid=${same_clientid:-Y}
        if [ "${same_clientid}" = "Y" ] || [ "${same_clientid}" = "y" ]; then
            oidc_clientID="${frp_user}"
        else
            read -p "auth.oidc.clientID: " oidc_clientID
        fi
        read -p "auth.oidc.clientSecret: " oidc_clientSecret
        read -p "auth.oidc.issuer(例如 https://oidc.afrp.net): " oidc_issuer
        read -p "auth.oidc.audience(例如 afrp.net): " oidc_audience
        read -p "auth.oidc.scope (默认afrp): " oidc_scope
        oidc_scope=${oidc_scope:-"afrp"}
    else
        echo "----- Token认证参数 -----"
        read -p "auth.token: " auth_token
    fi

    cat > ${FRPC_TOML} <<EOF
serverAddr = "${serverAddr}"
serverPort = ${serverPort}
user = "${frp_user}"
EOF

    if [ "${auth_mode}" = "1" ]; then
cat >> ${FRPC_TOML} <<AUTH
auth.method = "oidc"
auth.oidc.clientID = "${oidc_clientID}"
auth.oidc.clientSecret = "${oidc_clientSecret}"
auth.oidc.issuer = "${oidc_issuer}"
auth.oidc.audience = "${oidc_audience}"
auth.oidc.scope = "${oidc_scope}"

# auth.method = "token"
# auth.token = "your-token-here"
AUTH
    else
cat >> ${FRPC_TOML} <<AUTH
auth.method = "token"
auth.token = "${auth_token}"

# auth.method = "oidc"
# auth.oidc.clientID = "${frp_user}"
# auth.oidc.clientSecret = "secret"
# auth.oidc.issuer = "https://oidc.afrp.net"
# auth.oidc.audience = "afrp.net"
# auth.oidc.scope = "afrp"
AUTH
    fi

    add_tunnel="y"
    while [ "${add_tunnel}" = "y" ] || [ "${add_tunnel}" = "Y" ]; do
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
            [ -n "${subdomain}" ] && echo "subdomain = \"${subdomain}\"" >> ${FRPC_TOML}
            read -p "customDomains 域名，逗号分隔(可不填): " domains
            echo "localIP = \"${localIP}\"" >> ${FRPC_TOML}
            echo "localPort = ${localPort}" >> ${FRPC_TOML}
            [ -n "${domains}" ] && echo "customDomains = [\"${domains}\"]" >> ${FRPC_TOML}
            ;;
        3)
            echo "type = \"https\"" >> ${FRPC_TOML}
            read -p "subdomain子域名(可不填，直接回车跳过): " subdomain
            [ -n "${subdomain}" ] && echo "subdomain = \"${subdomain}\"" >> ${FRPC_TOML}
            read -p "customDomains 域名，逗号分隔(可不填): " domains
            echo "localIP = \"${localIP}\"" >> ${FRPC_TOML}
            echo "localPort = ${localPort}" >> ${FRPC_TOML}
            [ -n "${domains}" ] && echo "customDomains = [\"${domains}\"]" >> ${FRPC_TOML}
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
    procd_set_param respawn 3 5 10
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}
EOF
    chmod +x ${INIT_FILE}
    ${INIT_FILE} enable

cat > ${WRAPPER_BIN} <<'SHELL'
#!/bin/sh
FRPC_BIN="/root/frp/frpc-bin"

get_frpc_pid() {
    PID=$(ps | grep -v grep | grep "${FRPC_BIN}" | awk '{print $1}')
    echo "${PID}"
}

case "$1" in
start)
    /etc/init.d/frpc start
    RET=$?
    sleep 1
    PID=$(get_frpc_pid)
    if [ ${RET} -eq 0 ] && [ -n "${PID}" ];then
        echo "✅ frpc 已运行 (pid ${PID})"
    else
        echo "❌ frpc 启动失败"
    fi
    ;;
stop)
    echo "⏹ frpc 正在停止..."
    /etc/init.d/frpc stop
    RET=$?
    sleep 1
    PID=$(get_frpc_pid)
    if [ ${RET} -eq 0 ] && [ -z "${PID}" ];then
        echo "✅ frpc 已停止"
    else
        echo "❌ frpc 停止失败"
    fi
    ;;
restart)
    echo "⏹ frpc 正在停止..."
    /etc/init.d/frpc stop
    sleep 1
    /etc/init.d/frpc start
    RET=$?
    sleep 1
    PID=$(get_frpc_pid)
    if [ ${RET} -eq 0 ] && [ -n "${PID}" ];then
        echo "✅ frpc 已运行 (pid ${PID})"
    else
        echo "❌ frpc 重启失败"
    fi
    ;;
status)
    /etc/init.d/frpc status
    PID=$(get_frpc_pid)
    echo "----------------------------------------"
    if [ -n "${PID}" ];then
        echo "🔎 frpc 实际进程PID: ${PID}"
    else
        echo "🔎 frpc 当前没有运行进程"
    fi
    ;;
enable)
    /etc/init.d/frpc enable
    echo "✅ frpc 已设置开机自启"
    ;;
disable)
    /etc/init.d/frpc disable
    echo "✅ frpc 已关闭开机自启"
    ;;
version)
    ${FRPC_BIN} --version
    ;;
config)
    vi /root/frp/frpc.toml
    ;;
log)
    echo "===== frpc 实时日志（Ctrl+C退出） ====="
    logread -f | grep frpc
    ;;
*)
    echo "frpc 命令帮助："
    echo "  start      启动服务，打印真实PID"
    echo "  stop       停止服务"
    echo "  restart    重启服务，打印新PID"
    echo "  status     查看procd状态 + 实际进程PID"
    echo "  enable     开启开机自启"
    echo "  disable    关闭开机自启"
    echo "  version    查看frpc版本"
    echo "  config     编辑frpc.toml"
    echo "  log        实时查看日志(logread)"
    echo ""
    echo "底层系统服务命令: /etc/init.d/frpc [start|stop|status]"
    ;;
esac
SHELL
    chmod +x ${WRAPPER_BIN}
    rm -f ${SYMLINK_BIN}
    ln -s ${WRAPPER_BIN} ${SYMLINK_BIN}

    echo "✅ OpenWrt procd frpc服务安装完成"
    echo "👉 用户操作命令：frpc xxx"
    echo "👉 底层原生命令：/etc/init.d/frpc xxx"
}

action_install() {
    get_arch
    get_frp_info
    if [ -f "${FRPC_BIN}" ]; then
        echo "✅ 检测到已存在frpc二进制文件"
        VER_OUT=$(${FRPC_BIN} --version 2>/dev/null)
        CURRENT_FRPC_VER=$(echo "$VER_OUT" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+$')
        if [ -z "${CURRENT_FRPC_VER}" ]; then
            CURRENT_FRPC_VER="unknown"
            echo "本地frpc版本: unknown（无法解析版本号）"
        else
            echo "本地frpc版本: v${CURRENT_FRPC_VER}"
        fi
        echo "线上最新frp版本: v${LATEST_FRPC_VER}"
        if [ "${CURRENT_FRPC_VER}" != "unknown" ] && [ "${CURRENT_FRPC_VER}" = "${LATEST_FRPC_VER}" ]; then
            echo "✅ 当前frpc已经是最新版本，跳过二进制下载"
        else
            [ "${CURRENT_FRPC_VER}" = "unknown" ] && echo "⚠️ 本地版本无法识别，对比失效，将询问是否升级"
            read -p "发现新版本frpc，是否升级frpc二进制？[Y/n] " upgrade_ans
            upgrade_ans=${upgrade_ans:-Y}
            if [ "${upgrade_ans}" = "y" ] || [ "${upgrade_ans}" = "Y" ]; then
                echo "停止frpc服务准备升级..."
                /etc/init.d/frpc stop 2>/dev/null
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

    if [ ! -f "${FRPC_TOML}" ]; then
        echo "📄 frpc.toml不存在，进入配置生成流程"
        gen_config
    else
        echo "✅ 已存在frpc.toml，保留原有配置，跳过配置填写"
    fi

    install_service
    echo "=============================================="
    echo "🎉 frpc 操作完成！目录：${INSTALL_DIR}"
    echo "📋 用户命令：frpc start|stop|restart|status|config|log|version"
    echo "📄 配置文件：${FRPC_TOML}"
    echo "💡 procd原生命令示例：/etc/init.d/frpc start"
    echo "💡 二进制本体调用：${FRPC_BIN} --version"
    echo "=============================================="
}

action_update() {
    echo "===== 更新frpc ====="
    check_script_update
    check_and_install_deps
    get_arch
    get_frp_info
    echo "停止frpc..."
    /etc/init.d/frpc stop 2>/dev/null
    download_frpc
    /etc/init.d/frpc start
    echo "✅ frpc更新完成"
    ${FRPC_BIN} --version
}

action_uninstall() {
    echo "===== 卸载frpc ====="
    read -p "确认卸载frpc？停止服务、删除${INSTALL_DIR}、init脚本与命令 [Y/n] " ans
    ans=${ans:-Y}
    if [ ! "${ans}" = "Y" ] && [ ! "${ans}" = "y" ]; then
        echo "取消卸载"
        exit 0
    fi
    /etc/init.d/frpc stop 2>/dev/null
    /etc/init.d/frpc disable 2>/dev/null
    rm -f ${INIT_FILE}
    rm -f ${WRAPPER_BIN}
    rm -f ${SYMLINK_BIN}
    rm -rf ${INSTALL_DIR}
    echo "✅ 卸载完成"
}

main() {
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
            echo "用法: sh ${SCRIPT_NAME} [install|update|uninstall]"
            echo "  install    全新安装frpc，已安装则检测版本更新；已有toml保留原有配置"
            echo "  update     强制更新脚本和frpc二进制，不改动toml配置"
            echo "  uninstall  卸载frpc，清理全部文件与procd脚本"
            exit 0
    esac
}

main "$@"
