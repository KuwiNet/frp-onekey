#!/bin/bash
# Linux systemd frps onekey install script
# ScriptVersion=2.1.1
# Install dir: /opt/frps
# Systemd service: /etc/systemd/system/frps.service
# Cmd: frps xxx

SCRIPT_VERSION="2.1.1"
SCRIPT_NAME="frps.sh"
INSTALL_DIR="/opt/frps"
FRPS_BIN="${INSTALL_DIR}/frps-bin"
FRPS_TOML="${INSTALL_DIR}/frps.toml"
SYSTEMD_UNIT="/etc/systemd/system/frps.service"
BIN_LINK="/usr/local/bin/frps"

# 依赖检查，输出对应发行版安装提示
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
    if ! command -v hexdump &>/dev/null;then
        echo "⚠️ 缺失 hexdump"
        NEED="${NEED} bsdmainutils"
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

# 脚本自身版本检测更新：优先github raw，失败自动降级gitee国内镜像
check_script_update() {
    echo "==> 检查脚本版本更新..."
    GITHUB_RAW="https://raw.githubusercontent.com/KuwiNet/frp-onekey/master/frps.sh"
    GITEE_RAW="https://shturl.cc/TBZFMWpdM0D-onekey/raw/master/frps.sh"
    REMOTE_RAW_URL=""
    REMOTE_VER=""

    # 先尝试github源
    if command -v curl &>/dev/null;then
        REMOTE_VER=$(curl -sL -m 8 ${GITHUB_RAW} 2>/dev/null | grep 'SCRIPT_VERSION=' | head -n1 | cut -d'"' -f2)
    elif command -v wget &>/dev/null;then
        REMOTE_VER=$(wget -q -T 8 -O- ${GITHUB_RAW} 2>/dev/null | grep 'SCRIPT_VERSION=' | head -n1 | cut -d'"' -f2)
    fi

    if [[ -n "${REMOTE_VER}" ]];then
        REMOTE_RAW_URL="${GITHUB_RAW}"
    else
        echo "⚠️ GitHub raw访问失败，尝试切换Gitee国内镜像源"
        # 降级gitee
        if command -v curl &>/dev/null;then
            REMOTE_VER=$(curl -sL -m 8 ${GITEE_RAW} 2>/dev/null | grep 'SCRIPT_VERSION=' | head -n1 | cut -d'"' -f2)
        elif command -v wget &>/dev/null;then
            REMOTE_VER=$(wget -q -T 8 -O- ${GITEE_RAW} 2>/dev/null | grep 'SCRIPT_VERSION=' | head -n1 | cut -d'"' -f2)
        fi
        REMOTE_RAW_URL="${GITEE_RAW}"
    fi

    if [[ -n "${REMOTE_VER}" ]];then
        if [[ "${REMOTE_VER}" != "${SCRIPT_VERSION}" ]];then
            echo "发现新版本脚本: ${REMOTE_VER} (当前:${SCRIPT_VERSION})"
            read -p "是否自动更新脚本? [Y/n] " ans
            ans=${ans:-Y}
            if [[ "${ans}" =~ ^[Yy]$ ]];then
                if command -v curl &>/dev/null;then
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

# 获取系统架构
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

# 获取线上frp最新版本与frps下载链接，默认选项2官方源
get_frp_info() {
    echo "----------------------------------------"
    echo "请选择下载区域："
    echo "1) 国内(github proxy镜像)"
    echo "2) 国外(github官方，默认)"
    read -p "输入选项 [1/2] (默认2): " area
    area=${area:-2}

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

# 下载解压frps二进制，gzip头校验
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
    FILE_HEAD=$(head -c2 ${TMP_FILE} | hexdump -ve '1/1 "%02x"')
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

# 交互式生成frps.toml，增加认证模式选择 OIDC / Token，修复token缺少auth.method="token"
gen_config() {
    read -p "是否现在交互式填写frps.toml服务端配置? [Y/n] " fillcfg
    fillcfg=${fillcfg:-Y}
    if [[ ! "${fillcfg}" =~ ^[Yy]$ ]];then
        # 直接输出完整注释模板
        cat > ${FRPS_TOML} <<EOF
# IPv6 的文字地址或主机名必须括在方括号中，例如“[::1]:80”、“[ipv6-host]:http”或“[ipv6-host%zone]:80”
# 对于单个“bindAddr”字段，不需要方括号，例如“bindAddr = "::"”。
bindAddr = "0.0.0.0"
bindPort = 7000
# 用于 kcp 协议的 udp 端口​​，可以与 'bindPort' 相同。
# 如果未设置，则在 frps 中禁用 kcp。
kcpBindPort = 7000

# 如果要支持虚拟主机，必须设置监听的http端口（可选）
# 注意：http端口和https端口可以与bindPort相同
vhostHTTPPort = 80
vhostHTTPSPort = 443

# 在仪表板监听器中启用 golang pprof 处理程序。
# 必须先设置仪表板端口
webServer.pprofEnable = true

# enablePrometheus 将在 /metrics api 中的 webServer 上导出 prometheus 指标。
enablePrometheus = true

# 控制台或真实日志文件路径，如 ./frps.log
log.to = "./frps.log"
# 跟踪、调试、信息、警告、错误（trace, debug, info, warn, error）
log.level = "info"
log.maxDays = 3
# 当 log.to 是控制台时禁用日志颜色，默认为 false
log.disablePrintColor = false

# --------认证二选一，请取消对应注释-----------
# OIDC认证
# auth.method = "oidc"
# auth.oidc.issuer = "https://oidc.afrp.net"
# auth.oidc.audience = "afrp.net"

# Token认证
# auth.method = "token"
# auth.token = "your-token-here"

# 配置 Web 服务器以启用 frps 的仪表板。
# 仅当设置了 webServer.port 时，仪表板才可用。
webServer.addr = "0.0.0.0"
webServer.port = 7500
webServer.user = "admin"
webServer.password = "admin"
# webServer.tls.certFile = "server.crt"
# webServer.tls.keyFile = "server.key"
# dashboard assets directory(only for debug mode)
# webServer.assetsDir = "./static"

# 每个客户端可使用的最大端口数，默认值为 0，表示无限制
maxPortsPerClient = 0

# 如果 subDomainHost 不为空，可以在 frpc 的配置文件中设置 type 为 http 或 https 时的 subdomain
# 当 subdomain 为 test 时，路由使用的 host 为 test.frps.com
# subDomainHost = "zwrt.de"

# HTTP 请求的自定义 404 页面
# custom404Page = "/home/index_self.html"
EOF
        echo "已写入完整注释frps.toml模板，请手动选择认证方式取消注释"
        echo "后续修改配置: vim ${FRPS_TOML}"
        return
    fi

    echo "===== 选择认证模式 ====="
    echo "1) OIDC 认证"
    echo "2) Token 认证"
    read -p "输入选项 [1/2]: " auth_mode

    echo "===== 填写frps基础参数 ====="
    read -p "bindAddr(监听地址，默认0.0.0.0): " bindAddr
    bindAddr=${bindAddr:-"0.0.0.0"}

    while true; do
        read -p "bindPort(客户端连接端口，必填，默认7000): " bindPort
        bindPort=${bindPort:-7000}
        [[ -n "${bindPort}" ]] && break
        echo "❌ bindPort不能为空，请重新输入！"
    done

    read -p "kcpBindPort(KCP端口，回车同bindPort): " kcpBindPort
    kcpBindPort=${kcpBindPort:-${bindPort}}

    read -p "vhostHTTPPort(http虚拟主机端口，默认80): " vhostHTTPPort
    vhostHTTPPort=${vhostHTTPPort:-80}

    read -p "vhostHTTPSPort(https虚拟主机端口，默认443): " vhostHTTPSPort
    vhostHTTPSPort=${vhostHTTPSPort:-443}

    read -p "是否开启prometheus指标导出? [Y/n] " prom_enable
    prom_enable=${prom_enable:-Y}

    read -p "是否开启pprof性能调试? [Y/n] " pprof_enable
    pprof_enable=${pprof_enable:-Y}

    read -p "subDomainHost子域名后缀(可不填，回车跳过): " subDomainHost
    read -p "custom404Page自定义404页面路径(可不填，回车跳过): " custom404Page
    read -p "maxPortsPerClient单客户端最大端口数，0无限制(默认0): " maxPortsPerClient
    maxPortsPerClient=${maxPortsPerClient:-0}

    # 认证参数采集
    oidc_issuer=""
    oidc_audience=""
    auth_token=""
    if [[ "${auth_mode}" == "1" ]];then
        echo "----- OIDC认证参数 -----"
        read -p "auth.oidc.issuer(例如 https://oidc.afrp.net): " oidc_issuer
        read -p "auth.oidc.audience(例如 afrp.net): " oidc_audience
    else
        echo "----- Token认证参数 -----"
        read -p "auth.token: " auth_token
    fi

    echo "----- 日志配置 -----"
    read -p "log.to日志输出路径(默认./frps.log): " log_to
    log_to=${log_to:-"./frps.log"}
    read -p "log.level日志级别[trace/debug/info/warn/error]，默认info: " log_level
    log_level=${log_level:-"info"}
    read -p "log.maxDays日志保留天数，默认3: " log_maxDays
    log_maxDays=${log_maxDays:-3}
    read -p "log.disablePrintColor关闭控制台日志颜色? [Y/n] " log_discolor
    log_discolor=${log_discolor:-n}

    echo "----- Web面板配置 -----"
    read -p "webServer.addr(面板监听地址，默认0.0.0.0): " web_addr
    web_addr=${web_addr:-"0.0.0.0"}
    read -p "webServer.port(面板端口，默认7500): " web_port
    web_port=${web_port:-7500}
    read -p "webServer.user(面板账号，默认admin): " web_user
    web_user=${web_user:-"admin"}
    read -p "webServer.password(面板密码，默认admin): " web_pass
    web_pass=${web_pass:-"admin"}

    # 写入toml基础部分
    cat > ${FRPS_TOML} <<EOF
bindAddr = "${bindAddr}"
bindPort = ${bindPort}
kcpBindPort = ${kcpBindPort}

vhostHTTPPort = ${vhostHTTPPort}
vhostHTTPSPort = ${vhostHTTPSPort}

webServer.pprofEnable = ${pprof_enable^^}
enablePrometheus = ${prom_enable^^}

log.to = "${log_to}"
log.level = "${log_level}"
log.maxDays = ${log_maxDays}
log.disablePrintColor = ${log_discolor^^}
EOF

    # 根据选择写入认证：选中的取消注释生效，另一种全部注释
    if [[ "${auth_mode}" == "1" ]];then
        # OIDC启用，token注释
cat >> ${FRPS_TOML} <<AUTH
auth.method = "oidc"
auth.oidc.issuer = "${oidc_issuer}"
auth.oidc.audience = "${oidc_audience}"

# auth.method = "token"
# auth.token = "your-token-here"
AUTH
    else
        # Token启用，oidc注释；修复：增加 auth.method = "token"
cat >> ${FRPS_TOML} <<AUTH
auth.method = "token"
auth.token = "${auth_token}"

# auth.method = "oidc"
# auth.oidc.issuer = "https://oidc.afrp.net"
# auth.oidc.audience = "afrp.net"
AUTH
    fi

    if [[ -n "${subDomainHost}" ]];then
        echo "subDomainHost = \"${subDomainHost}\"" >> ${FRPS_TOML}
    fi
    if [[ -n "${custom404Page}" ]];then
        echo "custom404Page = \"${custom404Page}\"" >> ${FRPS_TOML}
    fi

cat >> ${FRPS_TOML} <<WEB
maxPortsPerClient = ${maxPortsPerClient}

webServer.addr = "${web_addr}"
webServer.port = ${web_port}
webServer.user = "${web_user}"
webServer.password = "${web_pass}"
WEB

    echo "✅ 配置写入完成: ${FRPS_TOML}"
}

# 生成systemd service单元 + frps包装脚本（增加PID真实进程打印）
install_service() {
cat > ${SYSTEMD_UNIT} <<EOF
[Unit]
Description=frps server service
After=network.target

[Service]
Type=simple
ExecStart=${FRPS_BIN} -c ${FRPS_TOML}
Restart=on-failure
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# 包装脚本 /usr/local/bin/frps，增加获取真实PID
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
            read -p "发现新版本frp，是否升级frps二进制？[Y/n] " upgrade_ans
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

    # toml存在直接跳过配置向导
    if [[ ! -f "${FRPS_TOML}" ]];then
        echo "📄 frps.toml不存在，进入配置生成流程"
        gen_config
    else
        echo "✅ 已存在frps.toml，保留原有配置，跳过配置填写"
    fi

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
            echo "  update     强制更新脚本和frps二进制，不改动toml配置"
            echo "  uninstall  卸载frps，清理全部文件与systemd单元"
            exit 0
    esac
}

# 需要root权限
if [[ $EUID -ne 0 ]];then
    echo "❌ 必须使用root/sudo执行本脚本！"
    exit 1
fi

main "$@"
