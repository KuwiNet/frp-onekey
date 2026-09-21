#!/bin/bash
# Linux systemd frpc onekey install script
# ScriptVersion=2.0.2
# Install dir: /opt/frp
# Systemd service: /etc/systemd/system/frpc.service
# Cmd: frpc xxx

SCRIPT_VERSION="2.0.2"
SCRIPT_NAME="frpc.sh"
INSTALL_DIR="/opt/frp"
FRPC_BIN="${INSTALL_DIR}/frpc-bin"
FRPC_TOML="${INSTALL_DIR}/frpc.toml"
SYSTEMD_UNIT="/etc/systemd/system/frpc.service"
BIN_LINK="/usr/local/bin/frpc"

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
    GITHUB_RAW="https://raw.githubusercontent.com/KuwiNet/frp-onekey/master/frpc.sh"
    GITEE_RAW="https://shturl.cc/TBZFMWpdM0D-onekey/raw/master/frpc.sh"
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

# 获取线上frp最新版本与下载链接
get_frp_info() {
    echo "----------------------------------------"
    echo "请选择下载区域："
    echo "1) 国内(github proxy镜像，推荐)"
    echo "2) 国外(github官方)"
    read -p "输入选项 [1/2] " area

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

    LATEST_FRPC_VER=$(echo "$API_CONTENT" | awk -F'"' '$2=="tag_name"{print $4;exit}' | sed 's/v//')
    DL_URL=$(echo "$API_CONTENT" | awk -F'"' -v plat="${PLATFORM}.tar.gz" '$2=="browser_download_url" && $4 ~ plat {print $4;exit}')

    if [[ -z "${DL_URL}" || -z "${LATEST_FRPC_VER}" ]];then
        echo "❌ 无法获取frp版本或下载链接！PLATFORM=${PLATFORM}"
        exit 1
    fi
    if [[ "${area}" == "1" ]];then
        DL_URL="https://mirror.ghproxy.com/${DL_URL}"
    fi
    echo "线上最新frp版本: v${LATEST_FRPC_VER}"
    echo "下载链接: ${DL_URL}"
}

# 下载解压frpc二进制，gzip头校验
download_frpc() {
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
    FRPC_TMP=$(find /tmp -maxdepth 2 -name frpc -type f | head -n1)
    if [[ -z "${FRPC_TMP}" ]];then
        echo "❌ 解压后找不到frpc二进制文件"
        exit 1
    fi
    cp ${FRPC_TMP} ${FRPC_BIN}
    chmod +x ${FRPC_BIN}
    rm -rf /tmp/frp*
    echo "frpc二进制提取完成: ${FRPC_BIN}"
}

# 交互式生成frpc.toml（仅toml不存在调用）
gen_config() {
    read -p "是否现在交互式填写frpc.toml配置(OIDC认证)? [Y/n] " fillcfg
    fillcfg=${fillcfg:-Y}
    if [[ ! "${fillcfg}" =~ ^[Yy]$ ]];then
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
    while true; do
        read -p "服务端serverAddr(公网IP/域名，必填): " serverAddr
        [[ -n "${serverAddr}" ]] && break
        echo "❌ serverAddr不能为空，请重新输入！"
    done
    while true; do
        read -p "服务端serverPort(必填): " serverPort
        [[ -n "${serverPort}" ]] && break
        echo "❌ serverPort不能为空，请重新输入！"
    done
    echo "提示：需要前往 https://www.afrp.net 注册获取"
    while true; do
        read -p "user(注册用户名，必填): " frp_user
        [[ -n "${frp_user}" ]] && break
        echo "❌ user不能为空，请重新输入！"
    done

    read -p "OIDC clientID 是否和 user(${frp_user}) 相同？ [Y/n] " same_clientid
    same_clientid=${same_clientid:-Y}
    if [[ "${same_clientid}" =~ ^[Yy]$ ]];then
        oidc_clientID="${frp_user}"
        echo "✅ clientID复用user值：${oidc_clientID}"
    else
        while true; do
            read -p "OIDC clientID(自定义，必填): " oidc_clientID
            [[ -n "${oidc_clientID}" ]] && break
            echo "❌ clientID不能为空，请重新输入！"
        done
    fi

    while true; do
        read -p "OIDC clientSecret(注册时保存的Client Secret，必填): " oidc_clientSecret
        [[ -n "${oidc_clientSecret}" ]] && break
        echo "❌ clientSecret不能为空，请重新输入！"
    done

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

    add_tunnel="y"
    while [[ "${add_tunnel}" =~ ^[Yy]$ ]]; do
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
            [[ -n "${subdomain}" ]] && echo "subdomain = \"${subdomain}\"" >> ${FRPC_TOML}
            read -p "customDomains 域名，逗号分隔(可不填): " domains
            echo "localIP = \"${localIP}\"" >> ${FRPC_TOML}
            echo "localPort = ${localPort}" >> ${FRPC_TOML}
            [[ -n "${domains}" ]] && echo "customDomains = [\"${domains}\"]" >> ${FRPC_TOML}
            ;;
        3)
            echo "type = \"https\"" >> ${FRPC_TOML}
            read -p "subdomain子域名(可不填，直接回车跳过): " subdomain
            [[ -n "${subdomain}" ]] && echo "subdomain = \"${subdomain}\"" >> ${FRPC_TOML}
            read -p "customDomains 域名，逗号分隔(可不填): " domains
            echo "localIP = \"${localIP}\"" >> ${FRPC_TOML}
            echo "localPort = ${localPort}" >> ${FRPC_TOML}
            [[ -n "${domains}" ]] && echo "customDomains = [\"${domains}\"]" >> ${FRPC_TOML}
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

# 生成systemd service单元 + frpc包装脚本
install_service() {
cat > ${SYSTEMD_UNIT} <<EOF
[Unit]
Description=frpc client service
After=network.target

[Service]
Type=simple
ExecStart=${FRPC_BIN} -c ${FRPC_TOML}
Restart=on-failure
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# 包装脚本，放置 /usr/local/bin/frpc，模拟子命令
cat > ${BIN_LINK} <<'SHELL'
#!/bin/bash
FRPC_BIN="/opt/frp/frpc-bin"
FRPC_TOML="/opt/frp/frpc.toml"
case "$1" in
start)
    systemctl start frpc
    ;;
stop)
    systemctl stop frpc
    ;;
restart)
    systemctl restart frpc
    ;;
status)
    systemctl status frpc
    ;;
enable)
    systemctl enable frpc
    ;;
disable)
    systemctl disable frpc
    ;;
version)
    ${FRPC_BIN} --version
    ;;
config)
    vim ${FRPC_TOML}
    ;;
log)
    echo "===== frpc实时日志（Ctrl+C退出） ====="
    journalctl -fu frpc
    ;;
*)
    echo "frpc 命令帮助："
    echo "  start      启动服务"
    echo "  stop       停止服务"
    echo "  restart    重启服务"
    echo "  status     查看运行状态"
    echo "  enable     开启开机自启"
    echo "  disable    关闭开机自启"
    echo "  version    查看frpc版本"
    echo "  config     编辑frpc.toml"
    echo "  log        实时查看日志"
    ;;
esac
SHELL
    chmod +x ${BIN_LINK}
    systemctl daemon-reload
    systemctl enable frpc
    echo "✅ systemd frpc服务安装完成，已设置开机自启，命令 frpc xxx 就绪"
}

action_install() {
    get_arch
    get_frp_info

    if [[ -f "${FRPC_BIN}" ]];then
        echo "✅ 检测到已存在frpc二进制文件"
        VER_OUT=$(${FRPC_BIN} --version 2>/dev/null)
        CURRENT_FRPC_VER=$(echo "$VER_OUT" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+$')
        if [[ -z "${CURRENT_FRPC_VER}" ]];then
            CURRENT_FRPC_VER="unknown"
            echo "本地frpc版本: unknown（无法解析版本号）"
        else
            echo "本地frpc版本: v${CURRENT_FRPC_VER}"
        fi
        echo "线上最新frp版本: v${LATEST_FRPC_VER}"

        if [[ "${CURRENT_FRPC_VER}" != "unknown" && "${CURRENT_FRPC_VER}" == "${LATEST_FRPC_VER}" ]];then
            echo "✅ 当前frpc已经是最新版本，跳过二进制下载"
        else
            [[ "${CURRENT_FRPC_VER}" == "unknown" ]] && echo "⚠️ 本地版本无法识别，对比失效，将询问是否升级"
            read -p "发现新版本frpc，是否升级frpc二进制？[Y/n] " upgrade_ans
            upgrade_ans=${upgrade_ans:-Y}
            if [[ "${upgrade_ans}" =~ ^[Yy]$ ]];then
                echo "停止frpc服务准备升级..."
                systemctl stop frpc 2>/dev/null
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

    # toml存在直接跳过配置向导
    if [[ ! -f "${FRPC_TOML}" ]];then
        echo "📄 frpc.toml不存在，进入配置生成流程"
        gen_config
    else
        echo "✅ 已存在frpc.toml，保留原有配置，跳过配置填写"
    fi

    install_service
    echo "=============================================="
    echo "🎉 frpc 操作完成！目录：${INSTALL_DIR}"
    echo "📋 常用命令："
    echo "   frpc start      启动frpc"
    echo "   frpc stop       停止frpc"
    echo "   frpc restart    重启frpc"
    echo "   frpc status     查看运行状态"
    echo "   frpc enable     开启开机自启"
    echo "   frpc disable    关闭开机自启"
    echo "   frpc version    查看frpc版本"
    echo "   frpc config     编辑frpc.toml"
    echo "   frpc log        实时查看frpc日志"
    echo "📄 配置文件：${FRPC_TOML}"
    echo "💡 systemd原生命令示例：systemctl start frpc"
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
    systemctl stop frpc 2>/dev/null
    download_frpc
    systemctl daemon-reload
    systemctl start frpc
    echo "✅ frpc更新完成"
    ${FRPC_BIN} --version
}

action_uninstall() {
    echo "===== 卸载frpc ====="
    read -p "确认卸载frpc？停止服务、删除${INSTALL_DIR}、systemd单元与frpc命令 [Y/n] " ans
    ans=${ans:-Y}
    if [[ ! "${ans}" =~ ^[Yy]$ ]];then
        echo "取消卸载"
        exit 0
    fi
    systemctl stop frpc 2>/dev/null
    systemctl disable frpc 2>/dev/null
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
            echo "  install    全新安装frpc，已安装则检测版本更新；已有toml保留原有配置"
            echo "  update     强制更新脚本和frpc二进制，不改动toml配置"
            echo "  uninstall  卸载frpc，清理全部文件与systemd单元"
            exit 0
    esac
}

# 需要root权限
if [[ $EUID -ne 0 ]];then
    echo "❌ 必须使用root/sudo执行本脚本！"
    exit 1
fi

main "$@"
