#!/bin/bash
# Linux systemd frps onekey install script
# ScriptVersion=2.2.6
# Install dir: /opt/frps
# Systemd service: /etc/systemd/system/frps.service
# Cmd: frps xxx

SCRIPT_VERSION="2.2.6"
SCRIPT_NAME="frps.sh"
INSTALL_DIR="/opt/frps"
FRPS_BIN="${INSTALL_DIR}/frps-bin"
FRPS_TOML="${INSTALL_DIR}/frps.toml"
CUSTOM_404="${INSTALL_DIR}/404.html"
SYSTEMD_UNIT="/etc/systemd/system/frps.service"
BIN_LINK="/usr/bin/frps"

check_and_install_deps() {
    echo "==> 检查系统依赖工具..."
    NEED=""
    if ! command -v tar &>/dev/null;then
        echo "⚠️ 缺失 tar"
        NEED="${NEED} tar"
    fi
    HAS_CURL=0; HAS_WGET=0
    command -v curl &>/dev/null && HAS_CURL=1
    command -v wget &>/dev/null && HAS_WGET=1
    if [[ ${HAS_CURL} -eq 0 && ${HAS_WGET} -eq 0 ]];then
        echo "⚠️ 缺失 curl/wget，至少需要其一"
        NEED="${NEED} curl"
    fi

    if [[ -n "${NEED}" ]];then
        echo ""
        echo "请手动安装依赖包："
        echo "Debian/Ubuntu: apt update && apt install ${NEED}"
        echo "RHEL/CentOS/Fedora: dnf install ${NEED}"
        echo "CentOS7: yum install ${NEED}"
        exit 1
    fi

    if ! command -v systemctl &>/dev/null;then
        echo "❌ 当前系统不支持 systemd，此脚本仅适用于systemd的Linux发行版"
        exit 1
    fi
}

check_script_update() {
    echo "==> 检查脚本版本更新..."
    GITHUB_RAW="https://raw.githubusercontent.com/KuwiNet/frp-onekey/master/frps.sh"
    PROXY_GH="https://mirror.ghproxy.com/${GITHUB_RAW}"
    REMOTE_RAW_URL=""
    REMOTE_VER=""

    if command -v curl &>/dev/null;then
        REMOTE_VER=$(curl -sL -m 8 "${PROXY_GH}" 2>/dev/null | grep 'SCRIPT_VERSION=' | head -n1 | cut -d'"' -f2)
    elif command -v wget &>/dev/null;then
        REMOTE_VER=$(wget -q -T 8 -O- "${PROXY_GH}" 2>/dev/null | grep 'SCRIPT_VERSION=' | head -n1 | cut -d'"' -f2)
    fi

    if [[ -n "${REMOTE_VER}" ]];then
        REMOTE_RAW_URL="${PROXY_GH}"
    else
        echo "⚠️ ghproxy代理访问失败，尝试直连GitHub源"
        if command -v curl &>/dev/null;then
            REMOTE_VER=$(curl -sL -m 8 "${GITHUB_RAW}" 2>/dev/null | grep 'SCRIPT_VERSION=' | head -n1 | cut -d'"' -f2)
        elif command -v wget &>/dev/null;then
            REMOTE_VER=$(wget -q -T 8 -O- "${GITHUB_RAW}" 2>/dev/null | grep 'SCRIPT_VERSION=' | head -n1 | cut -d'"' -f2)
        fi
        REMOTE_RAW_URL="${GITHUB_RAW}"
    fi

    if [[ -n "${REMOTE_VER}" ]];then
        if [[ "${REMOTE_VER}" != "${SCRIPT_VERSION}" ]];then
            echo "发现新版本脚本: ${REMOTE_VER} (当前:${SCRIPT_VERSION})"
            read -p "是否自动更新脚本? [Y/n] " ans
            ans=${ans:-Y}
            if [[ "${ans}" =~ ^[Yy]$ ]];then
                if command -v curl &>/dev/null;then
                    curl -sL "${REMOTE_RAW_URL}" -o ./${SCRIPT_NAME}
                else
                    wget -q "${REMOTE_RAW_URL}" -O ./${SCRIPT_NAME}
                fi
                chmod +x ./${SCRIPT_NAME}
                echo "脚本更新完成，请重新执行 ./${SCRIPT_NAME} $1"
                exit 0
            fi
        else
            echo "脚本已是最新版本"
        fi
    else
        echo "⚠️ ghproxy与GitHub均无法访问，跳过脚本版本检测"
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
    if [[ "${area}" == "1" ]];then
        API_RAW="https://mirror.ghproxy.com/${API_RAW}"
    fi

    echo "获取frp最新版本信息..."
    API_CONTENT=""
    if command -v curl &>/dev/null;then
        API_CONTENT=$(curl -sL ${API_RAW})
    else
        API_CONTENT=$(wget -qO- ${API_RAW})
    fi

    LATEST_FRPS_VER=$(echo "$API_CONTENT" | awk -F'"' '$2=="tag_name"{print $4;exit}' | sed 's/v//')
    DL_URL=$(echo "$API_CONTENT" | awk -F'"' -v plat="${PLATFORM}.tar.gz" '$2=="browser_download_url" && $4 ~ plat {print $4;exit}')

    if [[ -z "${DL_URL}" || -z "${LATEST_FRPS_VER}" ]];then
        echo "❌ 无法获取frp版本或下载链接！PLATFORM=${PLATFORM}"
        exit 1
    fi
    if [[ "${area}" == "1" ]];then
        DL_URL="https://mirror.ghproxy.com/${DL_URL}"
    fi
    echo "线上最新frp版本: v${LATEST_FRPS_VER}"
    echo "下载链接: ${DL_URL}"
}

download_frps() {
    mkdir -p ${INSTALL_DIR}
    TMP_FILE="/tmp/frp.tar.gz"
    echo "开始下载frp..."
    if [[ -z "${DL_URL}" ]];then
        echo "❌ 获取下载链接失败！"
        exit 1
    fi
    if command -v curl &>/dev/null;then
        curl -L ${DL_URL} -o ${TMP_FILE}
    else
        wget ${DL_URL} -O ${TMP_FILE}
    fi
    if [[ ! -f "${TMP_FILE}" ]];then
        echo "❌ 下载失败！"
        exit 1
    fi
    FILE_HEAD=$(head -c2 "${TMP_FILE}" | od -An -tx1 | tr -d ' \n')
    if [[ "${FILE_HEAD}" != "1f8b" ]];then
        echo "❌ 下载的不是有效的gzip压缩包，链接获取错误！"
        rm -f ${TMP_FILE}
        exit 1
    fi
    echo "解压..."
    tar -zxf ${TMP_FILE} -C /tmp
    FRPS_TMP=$(find /tmp -maxdepth 2 -name frps -type f | head -n1)
    if [[ -z "${FRPS_TMP}" ]];then
        echo "❌ 解压后找不到frps二进制文件"
        exit 1
    fi
    cp ${FRPS_TMP} ${FRPS_BIN}
    chmod +x ${FRPS_BIN}
    rm -rf /tmp/frp*
    echo "frps二进制提取完成: ${FRPS_BIN}"
}

download_404html() {
    mkdir -p ${INSTALL_DIR}
    RAW_404="https://raw.githubusercontent.com/KuwiNet/frp-onekey/master/404.html"
    RAW_404_PROXY="https://mirror.ghproxy.com/${RAW_404}"
    echo "==> 下载404.html自定义错误页面..."
    if command -v curl &>/dev/null; then
        curl -sL -m 10 ${RAW_404_PROXY} -o ${CUSTOM_404}
        if [ $? -ne 0 ]; then
            echo "⚠️ ghproxy代理下载失败，尝试直接github源"
            curl -sL -m 10 ${RAW_404} -o ${CUSTOM_404}
        fi
    else
        wget -q -T 10 ${RAW_404_PROXY} -O ${CUSTOM_404}
        if [ $? -ne 0 ]; then
            echo "⚠️ ghproxy代理下载失败，尝试直接github源"
            wget -q -T 10 ${RAW_404} -O ${CUSTOM_404}
        fi
    fi
    if [ -f "${CUSTOM_404}" ] && [ -s "${CUSTOM_404}" ]; then
        echo "✅ 404.html已保存: ${CUSTOM_404}"
    else
        echo "⚠️ 404.html下载失败，请手动放置文件到 ${CUSTOM_404}"
    fi
}

gen_config() {
    read -p "是否现在交互式填写frps.toml服务端配置? [Y/n] " fillcfg
    fillcfg=${fillcfg:-Y}
    if [[ ! "${fillcfg}" =~ ^[Yy]$ ]];then
        cat > ${FRPS_TOML} <<EOF
bindAddr = "0.0.0.0"
bindPort = 7000
kcpBindPort = 7000
vhostHTTPPort = 80
vhostHTTPSPort = 443
log.to = "./frps.log"
log.level = "info"
log.maxDays = 3
log.disablePrintColor = false
auth.method = "oidc"
auth.oidc.issuer = "https://www.afrp.net"
auth.oidc.audience = "afrp.net"
# auth.method = "token"
# auth.token = "afrp.net"
allowPorts = [
  { single = 80 },
  { single = 443 },
  { start = 10001, end = 60000 }
]
webServer.addr = "0.0.0.0"
webServer.port = 7500
webServer.user = "admin"
webServer.password = "admin"
webServer.pprofEnable = false
transport.heartbeatTimeout = 90
maxPortsPerClient = 10
subDomainHost = "example.com"
udpPacketSize = 1500
natholeAnalysisDataReserveHours = 168
transport.maxPoolCount = 5
custom404Page = "/opt/frps/404.html"
EOF
        echo "已写入默认frps.toml模板(默认OIDC认证)"
        echo "后续修改配置: vim ${FRPS_TOML}"
        return
    fi

    echo "===== 选择frps认证模式 ====="
    echo "1) OIDC 认证(默认)"
    echo "2) Token 认证"
    read -p "输入选项 [1/2] (默认1): " auth_mode
    auth_mode=${auth_mode:-1}

    cat > ${FRPS_TOML} <<EOF
bindAddr = "0.0.0.0"
bindPort = 7000
kcpBindPort = 7000
vhostHTTPPort = 80
vhostHTTPSPort = 443
log.to = "./frps.log"
log.level = "info"
log.maxDays = 3
log.disablePrintColor = false
EOF

    oidc_issuer=""
    oidc_audience=""
    auth_token=""
    subDomainHost=""

    if [[ "${auth_mode}" == "1" ]];then
        echo "----- OIDC认证参数配置 -----"
        read -p "auth.oidc.issuer (默认https://www.afrp.net): " oidc_issuer
        oidc_issuer=${oidc_issuer:-"https://www.afrp.net"}
        read -p "auth.oidc.audience (默认afrp.net): " oidc_audience
        oidc_audience=${oidc_audience:-"afrp.net"}
        read -p "subDomainHost (默认example.com): " subDomainHost
        subDomainHost=${subDomainHost:-"example.com"}

cat >> ${FRPS_TOML} <<AUTH
auth.method = "oidc"
auth.oidc.issuer = "${oidc_issuer}"
auth.oidc.audience = "${oidc_audience}"
# auth.method = "token"
# auth.token = "afrp.net"
AUTH
    else
        echo "----- Token认证参数配置 -----"
        read -p "auth.token (默认afrp.net): " auth_token
        auth_token=${auth_token:-"afrp.net"}
        read -p "subDomainHost (默认example.com): " subDomainHost
        subDomainHost=${subDomainHost:-"example.com"}

cat >> ${FRPS_TOML} <<AUTH
auth.method = "token"
auth.token = "${auth_token}"
# auth.method = "oidc"
# auth.oidc.issuer = "https://www.afrp.net"
# auth.oidc.audience = "afrp.net"
AUTH
    fi

    read -p "是否开启toml高级自定义选项? [Y/n] (默认N): " adv_opt
    adv_opt=${adv_opt:-N}

cat >> ${FRPS_TOML} <<BASE
allowPorts = [
  { single = 80 },
  { single = 443 },
  { start = 10001, end = 60000 }
]
webServer.addr = "0.0.0.0"
webServer.port = 7500
BASE

    webUser="admin"
    webPass="admin"
    maxPorts="10"
    maxPool="5"
    heartbeat="90"
    allowUsers=""
    additionalTokens=""

    if [[ "${adv_opt}" =~ ^[Yy]$ ]];then
        echo ""
        echo "========== 高级自定义配置 =========="
        echo "提示：直接回车使用括号内默认值"
        read -p "webServer.user (默认admin): " webUser
        webUser=${webUser:-"admin"}
        read -p "webServer.password (默认admin): " webPass
        webPass=${webPass:-"admin"}
        read -p "maxPortsPerClient (默认10): " maxPorts
        maxPorts=${maxPorts:-"10"}
        read -p "transport.maxPoolCount (默认5): " maxPool
        maxPool=${maxPool:-"5"}
        read -p "transport.heartbeatTimeout (默认90): " heartbeat
        heartbeat=${heartbeat:-"90"}

        if [[ "${auth_mode}" == "1" ]];then
            echo "--- OIDC模式高级参数 ---"
            read -p "allowUsers 允许用户名，多个逗号分隔(留空不设置): " allowUsers
        else
            echo "--- Token模式高级参数 ---"
            read -p "allowUsers 允许用户名，多个逗号分隔(留空不设置): " allowUsers
            read -p "additionalTokens 附加token，多个逗号分隔(留空不设置): " additionalTokens
        fi
    fi

cat >> ${FRPS_TOML} <<WEB
webServer.user = "${webUser}"
webServer.password = "${webPass}"
webServer.pprofEnable = false
transport.heartbeatTimeout = ${heartbeat}
maxPortsPerClient = ${maxPorts}
subDomainHost = "${subDomainHost}"
udpPacketSize = 1500
natholeAnalysisDataReserveHours = 168
transport.maxPoolCount = ${maxPool}
custom404Page = "/opt/frps/404.html"
WEB

    if [[ -n "${allowUsers}" ]];then
cat >> ${FRPS_TOML} <<AU
allowUsers = [$(echo "\"${allowUsers}\"" | sed 's/,/","/g')]
AU
    fi
    if [[ "${auth_mode}" == "2" && -n "${additionalTokens}" ]];then
cat >> ${FRPS_TOML} <<AT
additionalTokens = [$(echo "\"${additionalTokens}\"" | sed 's/,/","/g')]
AT
    fi

    echo "✅ frps.toml配置写入完成: ${FRPS_TOML}"
}

install_service() {
cat > ${SYSTEMD_UNIT} <<EOF
[Unit]
Description=frps server service
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/frps
ExecStart=${FRPS_BIN} -c ${FRPS_TOML}
Restart=on-failure
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

cat > ${BIN_LINK} <<'SHELL'
#!/bin/bash
FRPS_BIN="/opt/frps/frps-bin"
FRPS_TOML="/opt/frps/frps.toml"

get_frps_pid() {
    PID=$(ps -ef | grep -v grep | grep "${FRPS_BIN}" | awk '{print $2}')
    echo "${PID}"
}

case "$1" in
start)
    systemctl start frps
    RET=$?
    sleep 0.8
    PID=$(get_frps_pid)
    if [ ${RET} -eq 0 ] && [ -n "${PID}" ];then
        echo "✅ frps 已运行 (pid ${PID})"
    else
        echo "❌ frps 启动失败"
    fi
    ;;
stop)
    echo "⏹ frps 正在停止..."
    systemctl stop frps
    RET=$?
    sleep 0.6
    PID=$(get_frps_pid)
    if [ ${RET} -eq 0 ] && [ -z "${PID}" ];then
        echo "✅ frps 已停止"
    else
        echo "❌ frps 停止失败"
    fi
    ;;
restart)
    echo "⏹ frps 正在停止..."
    systemctl stop frps
    sleep 0.8
    systemctl start frps
    RET=$?
    sleep 0.8
    PID=$(get_frps_pid)
    if [ ${RET} -eq 0 ] && [ -n "${PID}" ];then
        echo "✅ frps 已运行 (pid ${PID})"
    else
        echo "❌ frps 重启失败"
    fi
    ;;
status)
    systemctl status frps --no-pager -l
    PID=$(get_frps_pid)
    echo "----------------------------------------"
    if [ -n "${PID}" ];then
        echo "🔎 frps 实际进程PID: ${PID}"
    else
        echo "🔎 frps 当前没有运行进程"
    fi
    ;;
enable)
    systemctl enable frps
    echo "✅ frps 已设置开机自启"
    ;;
disable)
    systemctl disable frps
    echo "✅ frps 已关闭开机自启"
    ;;
version)
    ${FRPS_BIN} --version
    ;;
config)
    vim ${FRPS_TOML}
    ;;
log)
    echo "===== frps实时日志（Ctrl+C退出） ====="
    journalctl -fu frps
    ;;
*)
    echo "frps 命令帮助："
    echo "  start      启动服务，打印真实PID"
    echo "  stop       停止服务"
    echo "  restart    重启服务，打印新PID"
    echo "  status     查看systemd状态 + 实际进程PID"
    echo "  enable     开启开机自启"
    echo "  disable    关闭开机自启"
    echo "  version    查看frps版本"
    echo "  config     编辑frps.toml"
    echo "  log        实时查看日志"
    ;;
esac
SHELL
    chmod +x ${BIN_LINK}
    systemctl daemon-reload
    systemctl enable frps
    echo "✅ systemd frps服务安装完成，已设置开机自启，命令 frps xxx 就绪"
}

action_install() {
    get_arch
    get_frp_info

    if [[ -f "${FRPS_BIN}" ]];then
        echo "✅ 检测到已存在frps二进制文件"
        VER_OUT=$(${FRPS_BIN} --version 2>/dev/null)
        CURRENT_FRPS_VER=$(echo "$VER_OUT" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+$')
        if [[ -z "${CURRENT_FRPS_VER}" ]];then
            CURRENT_FRPS_VER="unknown"
            echo "本地frps版本: unknown（无法解析版本号）"
        else
            echo "本地frps版本: v${CURRENT_FRPS_VER}"
        fi
        echo "线上最新frp版本: v${LATEST_FRPS_VER}"

        if [[ "${CURRENT_FRPS_VER}" != "unknown" && "${CURRENT_FRPS_VER}" == "${LATEST_FRPS_VER}" ]];then
            echo "✅ 当前frps已经是最新版本，跳过二进制下载"
        else
            [[ "${CURRENT_FRPS_VER}" == "unknown" ]] && echo "⚠️ 本地版本无法识别，对比失效，将询问是否升级"
            read -p "发现新版本frps，是否升级frps二进制？[Y/n] " upgrade_ans
            upgrade_ans=${upgrade_ans:-Y}
            if [[ "${upgrade_ans}" =~ ^[Yy]$ ]];then
                echo "停止frps服务准备升级..."
                systemctl stop frps 2>/dev/null
                download_frps
                echo "升级完成"
            else
                echo "跳过frps二进制升级"
            fi
        fi
    else
        echo "未检测到frps二进制，开始全新下载安装"
        download_frps
    fi

    if [[ ! -f "${FRPS_TOML}" ]];then
        echo "📄 frps.toml不存在，进入配置生成流程"
        gen_config
    else
        echo "✅ 已存在frps.toml，保留原有配置，跳过配置填写"
    fi

    download_404html

    install_service
    echo "=============================================="
    echo "🎉 frps 操作完成！目录：${INSTALL_DIR}"
    echo "📋 常用命令："
    echo "   frps start      启动frps，输出真实pid"
    echo "   frps stop       停止frps"
    echo "   frps restart    重启frps，输出新pid"
    echo "   frps status     查看运行状态+实际进程PID"
    echo "   frps enable     开启开机自启"
    echo "   frps disable    关闭开机自启"
    echo "   frps version    查看frps版本"
    echo "   frps config     编辑frps.toml"
    echo "   frps log        实时查看frps日志"
    echo "📄 配置文件：${FRPS_TOML}"
    echo "📄 404错误页：${CUSTOM_404}"
    echo "💡 systemd原生命令示例：systemctl start frps"
    echo "💡 二进制本体调用：${FRPS_BIN} --version"
    echo "=============================================="
}

action_update() {
    echo "===== 更新frps ====="
    check_script_update
    check_and_install_deps
    get_arch
    get_frp_info
    echo "停止frps..."
    systemctl stop frps 2>/dev/null
    download_frps
    download_404html
    systemctl daemon-reload
    systemctl start frps
    echo "✅ frps更新完成"
    ${FRPS_BIN} --version
}

action_uninstall() {
    echo "===== 卸载frps ====="
    read -p "确认卸载frps？停止服务、删除${INSTALL_DIR}、systemd单元与frps命令 [Y/n] " ans
    ans=${ans:-Y}
    if [[ ! "${ans}" =~ ^[Yy]$ ]];then
        echo "取消卸载"
        exit 0
    fi
    systemctl stop frps 2>/dev/null
    systemctl disable frps 2>/dev/null
    rm -f ${SYSTEMD_UNIT}
    rm -f ${BIN_LINK}
    rm -rf ${INSTALL_DIR}
    systemctl daemon-reload
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
            echo "用法: sudo bash ${SCRIPT_NAME} [install|update|uninstall]"
            echo "  install    全新安装frps，已安装则检测版本更新；已有toml保留原有配置"
            echo "  update     强制更新脚本和frps二进制+404.html，不改动toml配置"
            echo "  uninstall  卸载frps，清理全部文件与systemd单元"
            exit 0
    esac
}

if [[ $EUID -ne 0 ]];then
    echo "❌ 必须使用root/sudo执行本脚本！"
    exit 0
fi

main "$@"
