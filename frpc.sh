#!/bin/sh
# OpenWrt procd frpc onekey install script
# ScriptVersion=2.2.0
# Upstream-FRP-Version: v0.72.0
# Install dir: /root/frp
# Procd init: /etc/init.d/frpc
# Real wrapper file: /usr/sbin/frpc-wrapper
# Symlink: /usr/sbin/frpc  --> frpc-wrapper
#
# GitHub 文件加速：https://oproxy.cc （raw / api / release 资源均可加速）
# Gitee 镜像：https://gitee.com/kuwinet/frp-onekey （国内备用源）

SCRIPT_VERSION="2.2.1"
SCRIPT_NAME="frpc.sh"
INSTALL_DIR="/root/frp"
FRPC_BIN="${INSTALL_DIR}/frpc-bin"
FRPC_TOML="${INSTALL_DIR}/frpc.toml"
INIT_FILE="/etc/init.d/frpc"
WRAPPER_BIN="/usr/sbin/frpc-wrapper"
SYMLINK_BIN="/usr/sbin/frpc"

GH_REPO="KuwiNet/frp-onekey"
GH_BRANCH="openwrt"
GH_RAW_BASE="https://raw.githubusercontent.com/${GH_REPO}/${GH_BRANCH}"
GITEE_RAW="https://gitee.com/kuwinet/frp-onekey/raw/${GH_BRANCH}/frpc.sh"
PROXY_HOST="https://oproxy.cc"

HAS_CURL=0
HAS_WGET=0

usage() {
cat <<EOF
用法: sh ${SCRIPT_NAME} <install|update|uninstall>

  install    全新安装frpc，已安装则检测版本更新；已有toml保留原有配置
  update     强制更新脚本和frpc二进制，不改动toml配置
  uninstall  卸载frpc，清理全部文件与procd脚本
EOF
}

# 把 GitHub 原始地址转换为 oproxy.cc 加速地址（oproxy 要求去掉协议头）
proxy_url() {
    _u="$1"
    _u="${_u#https://}"
    _u="${_u#http://}"
    printf '%s/%s' "${PROXY_HOST}" "${_u}"
}

# 抓取文本内容到 stdout，失败返回非0
http_get() {
    if [ "${HAS_CURL}" -eq 1 ]; then
        curl -fsSL --connect-timeout 6 -m "${2:-12}" --retry 2 --retry-delay 1 "$1" 2>/dev/null
    elif [ "${HAS_WGET}" -eq 1 ]; then
        wget -q -T "${2:-12}" -t 2 -O- "$1" 2>/dev/null
    else
        return 1
    fi
}

# 下载文件到指定路径，失败返回非0
http_download() {
    if [ "${HAS_CURL}" -eq 1 ]; then
        curl -fSL --connect-timeout 10 --retry 3 --retry-delay 2 -m 900 "$1" -o "$2" 2>/dev/null
    elif [ "${HAS_WGET}" -eq 1 ]; then
        wget -q -T 120 -t 3 -O "$2" "$1" 2>/dev/null
    else
        return 1
    fi
}

# 按顺序尝试多个地址，返回第一个非空结果
fetch_first() {
    for _u in "$@"; do
        _out=$(http_get "${_u}")
        if [ -n "${_out}" ]; then
            printf '%s' "${_out}"
            return 0
        fi
    done
    return 1
}

# 交互式询问；非交互环境直接采用默认值
ask() {
    _prompt="$1"
    _def="${2:-}"
    if [ ! -t 0 ]; then
        printf '%s%s\n' "${_prompt}" "${_def}" >&2
        printf '%s' "${_def}"
        return 0
    fi
    printf '%s' "${_prompt}" >&2
    read -r _ans || _ans=""
    printf '%s' "${_ans:-${_def}}"
}

check_and_install_deps() {
    echo "==> 检查OpenWrt依赖工具..."
    NEED=""
    if ! command -v tar >/dev/null; then
        echo "⚠️ 缺失 tar"
        NEED="${NEED} tar"
    fi
    if ! command -v hexdump >/dev/null; then
        echo "⚠️ 缺失 hexdump"
        NEED="${NEED} bsdmainutils"
    fi
    HAS_CURL=0; HAS_WGET=0
    command -v curl >/dev/null && HAS_CURL=1
    command -v wget >/dev/null && HAS_WGET=1
    if [ ${HAS_CURL} -eq 0 ] && [ ${HAS_WGET} -eq 0 ]; then
        echo "⚠️ 缺失 curl/wget，至少需要其一"
        NEED="${NEED} curl"
    fi

    if [ -n "${NEED}" ]; then
        echo "==> opkg 安装依赖：${NEED}"
        opkg update
        opkg install ${NEED}
        echo "✅ 依赖安装完成"
    fi
}

# 判断 $1 是否比 $2 更新（避免本地版本更高时被“更新”成旧版本）
ver_is_newer() {
    _max=$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)
    [ "${_max}" = "$1" ] && [ "$1" != "$2" ]
}

check_script_update() {
    echo "==> 检查脚本版本更新..."
    RAW_SELF="${GH_RAW_BASE}/${SCRIPT_NAME}"
    PROXY_SELF=$(proxy_url "${RAW_SELF}")

    REMOTE_VER=$(fetch_first "${PROXY_SELF}" "${RAW_SELF}" "${GITEE_RAW}" | grep 'SCRIPT_VERSION=' | head -n1 | cut -d'"' -f2)

    if [ -z "${REMOTE_VER}" ]; then
        echo "⚠️ oproxy.cc / GitHub / Gitee 均无法访问，跳过脚本版本检测"
        return 0
    fi
    if [ "${REMOTE_VER}" = "${SCRIPT_VERSION}" ]; then
        echo "脚本已是最新版本 (${SCRIPT_VERSION})"
        return 0
    fi
    if ! ver_is_newer "${REMOTE_VER}" "${SCRIPT_VERSION}"; then
        echo "本地脚本(${SCRIPT_VERSION})高于远端(${REMOTE_VER})，跳过自动更新"
        return 0
    fi

    echo "发现新版本脚本: ${REMOTE_VER} (当前:${SCRIPT_VERSION})"
    ans=$(ask "是否自动更新脚本? [Y/n] " "Y")
    if [ ! "${ans}" = "Y" ] && [ ! "${ans}" = "y" ]; then
        echo "跳过脚本更新"
        return 0
    fi

    SELF_PATH="$0"
    if [ ! -f "${SELF_PATH}" ] || [ ! -w "${SELF_PATH}" ]; then
        echo "⚠️ 当前脚本文件不可写（${SELF_PATH}），请手动下载最新脚本后重新执行"
        return 0
    fi

    # 先下载到临时文件再原子替换，避免覆盖正在被 sh 读取的脚本
    TMP_SELF="/tmp/${SCRIPT_NAME}.new.$$"
    UPDATED=0
    for url in "${PROXY_SELF}" "${RAW_SELF}" "${GITEE_RAW}"; do
        if http_download "${url}" "${TMP_SELF}" && grep -q 'SCRIPT_VERSION=' "${TMP_SELF}"; then
            UPDATED=1
            break
        fi
    done
    if [ ${UPDATED} -ne 1 ]; then
        echo "❌ 脚本下载失败，保留当前版本"
        rm -f "${TMP_SELF}"
        return 0
    fi
    # 防止 CDN 返回被截断的文件：语法校验通过才替换
    if ! sh -n "${TMP_SELF}" 2>/dev/null; then
        echo "❌ 下载的脚本不完整（语法校验未通过），保留当前版本"
        rm -f "${TMP_SELF}"
        return 0
    fi

    chmod +x "${TMP_SELF}"
    mv -f "${TMP_SELF}" "${SELF_PATH}" || { echo "❌ 脚本替换失败，保留当前版本"; rm -f "${TMP_SELF}"; return 0; }
    echo "✅ 脚本已更新至 ${REMOTE_VER}，自动重新执行"
    exec sh "${SELF_PATH}" "$@"
}

get_arch() {
    ARCH=$(uname -m)
    # 上游 0.6x 起调整了资产命名：linux_386 取消，ARM32 改为 linux_arm(软浮点)/linux_arm_hf(硬浮点)
    case $ARCH in
        x86_64|amd64) PLAT_CANDIDATES="linux_amd64" ;;
        aarch64|arm64) PLAT_CANDIDATES="linux_arm64" ;;
        armv7l|armv8l) PLAT_CANDIDATES="linux_arm_hf linux_arm" ;;
        armv6l) PLAT_CANDIDATES="linux_arm linux_arm_hf" ;;
        i686|i386) PLAT_CANDIDATES="linux_386" ;;
        loongarch64|loong64) PLAT_CANDIDATES="linux_loong64" ;;
        mips64el) PLAT_CANDIDATES="linux_mips64le" ;;
        mips64) PLAT_CANDIDATES="linux_mips64" ;;
        mipsel) PLAT_CANDIDATES="linux_mipsle" ;;
        mips) PLAT_CANDIDATES="linux_mips" ;;
        riscv64) PLAT_CANDIDATES="linux_riscv64" ;;
        *) echo "❌ 不支持架构: $ARCH"; exit 1 ;;
    esac
    echo "检测架构: ${ARCH} (候选安装包: ${PLAT_CANDIDATES})"
}

get_frp_info() {
    echo "----------------------------------------"
    echo "请选择下载区域："
    echo "1) 国内(oproxy.cc 镜像加速，默认)"
    echo "2) 国外(GitHub 官方)"
    area=$(ask "输入选项 [1/2] (默认1): " "1")
    [ "${area}" = "2" ] || area=1

    API_RAW="https://api.github.com/repos/fatedier/frp/releases/latest"
    API_PROXY=$(proxy_url "${API_RAW}")

    echo "获取frp最新版本信息..."
    if [ "${area}" = "1" ]; then
        API_CONTENT=$(fetch_first "${API_PROXY}" "${API_RAW}")
    else
        API_CONTENT=$(fetch_first "${API_RAW}" "${API_PROXY}")
    fi

    if [ -z "${API_CONTENT}" ]; then
        echo "❌ 无法获取frp版本信息，请检查网络（可尝试切换下载区域）"
        exit 1
    fi

    LATEST_FRPC_VER=$(printf '%s' "${API_CONTENT}" | grep -o '"tag_name":[[:space:]]*"[^"]*"' | head -n1 | cut -d'"' -f4 | sed 's/^v//')
    DL_URL_RAW=""
    for plat in ${PLAT_CANDIDATES}; do
        DL_URL_RAW=$(printf '%s' "${API_CONTENT}" | tr ',' '\n' | grep -o "https://[^\"]*${plat}\.tar\.gz" | head -n1)
        [ -n "${DL_URL_RAW}" ] && break
    done

    if [ -z "${DL_URL_RAW}" ] || [ -z "${LATEST_FRPC_VER}" ]; then
        echo "❌ 上游 v${LATEST_FRPC_VER:-unknown} 未提供当前架构(${ARCH})的安装包（候选: ${PLAT_CANDIDATES}）"
        echo "上游现有 Linux 包："
        printf '%s' "${API_CONTENT}" | tr ',' '\n' | grep -o 'frp_[0-9.]*_linux_[a-z0-9_]*\.tar\.gz' | sort -u | sed 's/^/  /'
        exit 1
    fi

    DL_URL="${DL_URL_RAW}"
    if [ "${area}" = "1" ]; then
        DL_URL=$(proxy_url "${DL_URL_RAW}")
    fi
    echo "线上最新frp版本: v${LATEST_FRPC_VER}"
    echo "下载链接: ${DL_URL}"
}

download_frpc() {
    mkdir -p "${INSTALL_DIR}"
    if [ -z "${DL_URL}" ]; then
        echo "❌ 获取下载链接失败！"
        return 1
    fi

    TMP_DIR=$(mktemp -d /tmp/frpc-onekey.XXXXXX) || { echo "❌ 创建临时目录失败"; return 1; }
    TMP_FILE="${TMP_DIR}/frp.tar.gz"

    echo "开始下载frp..."
    if ! http_download "${DL_URL}" "${TMP_FILE}"; then
        case "${DL_URL}" in
            "${PROXY_HOST}"*)
                echo "⚠️ oproxy.cc 加速下载失败，回退 GitHub 官方直连重试"
                http_download "${DL_URL_RAW}" "${TMP_FILE}"
                ;;
        esac
    fi
    if [ ! -s "${TMP_FILE}" ]; then
        echo "❌ 下载失败！请检查网络或切换下载区域"
        rm -rf "${TMP_DIR}"
        return 1
    fi

    FILE_HEAD=$(head -c2 "${TMP_FILE}" | hexdump -v -e '1/1 "%02x"' 2>/dev/null)
    if [ -n "${FILE_HEAD}" ] && [ "${FILE_HEAD}" != "1f8b" ]; then
        echo "❌ 下载的不是有效的gzip压缩包，链接获取错误！"
        rm -rf "${TMP_DIR}"
        return 1
    fi
    if ! tar -tzf "${TMP_FILE}" >/dev/null 2>&1; then
        echo "❌ 压缩包校验失败（文件不完整或已损坏），请重试"
        rm -rf "${TMP_DIR}"
        return 1
    fi

    echo "解压..."
    tar -zxf "${TMP_FILE}" -C "${TMP_DIR}"
    FRPC_TMP=$(find "${TMP_DIR}" -maxdepth 2 -type f -name frpc | head -n1)
    if [ -z "${FRPC_TMP}" ]; then
        echo "❌ 解压后找不到frpc二进制文件"
        rm -rf "${TMP_DIR}"
        return 1
    fi

    rm -f "${FRPC_BIN}"
    cp "${FRPC_TMP}" "${FRPC_BIN}"
    chmod +x "${FRPC_BIN}"
    rm -rf "${TMP_DIR}"
    echo "frpc二进制提取完成: ${FRPC_BIN}"
}

gen_config() {
    if [ ! -t 0 ]; then
        echo "⚠️ 非交互模式，写入完整注释模板，请手动选择认证方式"
        fillcfg="N"
    else
        fillcfg=$(ask "是否现在交互式填写frpc.toml客户端配置? [Y/n] " "Y")
    fi

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
# auth.oidc.tokenEndpointURL = "https://www.afrp.net/oidc/token.php"
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
    echo "1) OIDC 认证(默认)"
    echo "2) Token 认证"
    auth_mode=$(ask "输入选项 [1/2] (默认1): " "1")
    [ "${auth_mode}" = "1" ] || auth_mode=2

    echo "===== 填写frpc基础参数 ====="
    while true; do
        serverAddr=$(ask "serverAddr(服务端域名/IP，必填): " "")
        [ -n "${serverAddr}" ] && break
        echo "❌ serverAddr不能为空，请重新输入！"
    done
    while true; do
        serverPort=$(ask "serverPort(服务端端口，必填，默认7000): " "7000")
        case "${serverPort}" in
            ''|*[!0-9]*) echo "❌ serverPort必须为数字，请重新输入！" ;;
            *) break ;;
        esac
    done
    while true; do
        frp_user=$(ask "user(客户端用户名，必填): " "")
        [ -n "${frp_user}" ] && break
        echo "❌ user不能为空，请重新输入！"
    done

    oidc_clientID=""
    oidc_clientSecret=""
    oidc_issuer=""
    oidc_audience=""
    oidc_scope=""
    oidc_tokenEndpointURL=""
    auth_token=""
    if [ "${auth_mode}" = "1" ]; then
        echo "----- OIDC认证参数 -----"
        same_clientid=$(ask "OIDC clientID 是否和 user(${frp_user}) 相同？ [Y/n] " "Y")
        if [ "${same_clientid}" = "Y" ] || [ "${same_clientid}" = "y" ]; then
            oidc_clientID="${frp_user}"
        else
            oidc_clientID=$(ask "auth.oidc.clientID: " "")
        fi
        oidc_clientSecret=$(ask "auth.oidc.clientSecret: " "")
        oidc_issuer=$(ask "auth.oidc.issuer(例如 https://oidc.afrp.net): " "")
        oidc_tokenEndpointURL=$(ask "auth.oidc.tokenEndpointURL (默认https://www.afrp.net/oidc/token.php): " "https://www.afrp.net/oidc/token.php")
        oidc_audience=$(ask "auth.oidc.audience(例如 afrp.net): " "")
        oidc_scope=$(ask "auth.oidc.scope (默认afrp): " "afrp")
    else
        echo "----- Token认证参数 -----"
        auth_token=$(ask "auth.token: " "")
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
auth.oidc.tokenEndpointURL = "${oidc_tokenEndpointURL}"
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
# auth.oidc.tokenEndpointURL = "https://www.afrp.net/oidc/token.php"
# auth.oidc.audience = "afrp.net"
# auth.oidc.scope = "afrp"
AUTH
    fi

    add_tunnel=$(ask "是否添加隧道? [Y/n] " "Y")
    while [ "${add_tunnel}" = "y" ] || [ "${add_tunnel}" = "Y" ]; do
        echo ""
        echo "==== 添加隧道 ===="
        echo "隧道类型: 1=tcp  2=http  3=https  4=stcp  5=xtcp"
        ttype=$(ask "选择隧道类型 [1/2/3/4/5]: " "1")
        tname=$(ask "隧道名称(唯一): " "tunnel-$$")
        localIP=$(ask "本地IP(默认127.0.0.1): " "127.0.0.1")
        localPort=$(ask "本地端口localPort: " "")

        echo "[[proxies]]" >> ${FRPC_TOML}
        echo "name = \"${tname}\"" >> ${FRPC_TOML}
        case $ttype in
        2)
            echo "type = \"http\"" >> ${FRPC_TOML}
            subdomain=$(ask "subdomain子域名(可不填，直接回车跳过): " "")
            [ -n "${subdomain}" ] && echo "subdomain = \"${subdomain}\"" >> ${FRPC_TOML}
            domains=$(ask "customDomains 域名，逗号分隔(可不填): " "")
            echo "localIP = \"${localIP}\"" >> ${FRPC_TOML}
            echo "localPort = ${localPort}" >> ${FRPC_TOML}
            [ -n "${domains}" ] && echo "customDomains = [\"${domains}\"]" >> ${FRPC_TOML}
            ;;
        3)
            echo "type = \"https\"" >> ${FRPC_TOML}
            subdomain=$(ask "subdomain子域名(可不填，直接回车跳过): " "")
            [ -n "${subdomain}" ] && echo "subdomain = \"${subdomain}\"" >> ${FRPC_TOML}
            domains=$(ask "customDomains 域名，逗号分隔(可不填): " "")
            echo "localIP = \"${localIP}\"" >> ${FRPC_TOML}
            echo "localPort = ${localPort}" >> ${FRPC_TOML}
            [ -n "${domains}" ] && echo "customDomains = [\"${domains}\"]" >> ${FRPC_TOML}
            ;;
        4)
            echo "type = \"stcp\"" >> ${FRPC_TOML}
            sk=$(ask "secretKey: " "")
            echo "localIP = \"${localIP}\"" >> ${FRPC_TOML}
            echo "localPort = ${localPort}" >> ${FRPC_TOML}
            echo "secretKey = \"${sk}\"" >> ${FRPC_TOML}
            ;;
        5)
            echo "type = \"xtcp\"" >> ${FRPC_TOML}
            sk=$(ask "secretKey: " "")
            echo "localIP = \"${localIP}\"" >> ${FRPC_TOML}
            echo "localPort = ${localPort}" >> ${FRPC_TOML}
            echo "secretKey = \"${sk}\"" >> ${FRPC_TOML}
            ;;
        *)
            echo "type = \"tcp\"" >> ${FRPC_TOML}
            remotePort=$(ask "remotePort(远端端口): " "")
            echo "localIP = \"${localIP}\"" >> ${FRPC_TOML}
            echo "localPort = ${localPort}" >> ${FRPC_TOML}
            echo "remotePort = ${remotePort}" >> ${FRPC_TOML}
            ;;
        esac
        echo "" >> ${FRPC_TOML}
        add_tunnel=$(ask "继续添加隧道？[Y/n] " "Y")
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
    ps | grep -v grep | grep "${FRPC_BIN}" | awk '{print $1}' | head -n1
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

    SERVICE_WAS_RUNNING=0
    if /etc/init.d/frpc status >/dev/null 2>&1; then
        SERVICE_WAS_RUNNING=1
    fi

    UPGRADED=0
    if [ -f "${FRPC_BIN}" ]; then
        echo "✅ 检测到已存在frpc二进制文件"
        VER_OUT=$(${FRPC_BIN} --version 2>/dev/null)
        CURRENT_FRPC_VER=$(printf '%s' "${VER_OUT}" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')
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
            upgrade_ans=$(ask "发现新版本frpc，是否升级frpc二进制？[Y/n] " "Y")
            if [ "${upgrade_ans}" = "y" ] || [ "${upgrade_ans}" = "Y" ]; then
                echo "停止frpc服务准备升级..."
                [ ${SERVICE_WAS_RUNNING} -eq 1 ] && /etc/init.d/frpc stop 2>/dev/null
                if download_frpc; then
                    UPGRADED=1
                    echo "升级完成"
                else
                    echo "❌ 升级失败，保留原二进制与配置"
                    [ ${SERVICE_WAS_RUNNING} -eq 1 ] && /etc/init.d/frpc start 2>/dev/null
                    exit 1
                fi
            else
                echo "跳过frpc二进制升级"
            fi
        fi
    else
        echo "未检测到frpc二进制，开始全新下载安装"
        if ! download_frpc; then
            echo "❌ 安装失败，请检查网络后重试"
            exit 1
        fi
    fi

    if [ ! -f "${FRPC_TOML}" ]; then
        echo "📄 frpc.toml不存在，进入配置生成流程"
        gen_config
    else
        echo "✅ 已存在frpc.toml，保留原有配置，跳过配置填写"
    fi

    install_service

    if [ ${UPGRADED} -eq 1 ] && [ ${SERVICE_WAS_RUNNING} -eq 1 ]; then
        /etc/init.d/frpc restart >/dev/null 2>&1
        echo "✅ 升级后已重启frpc服务"
    fi

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
    get_arch
    get_frp_info
    echo "停止frpc..."
    /etc/init.d/frpc stop 2>/dev/null
    if ! download_frpc; then
        echo "❌ 更新失败，尝试恢复原服务"
        /etc/init.d/frpc start 2>/dev/null
        exit 1
    fi
    /etc/init.d/frpc start 2>/dev/null
    echo "✅ frpc更新完成"
    ${FRPC_BIN} --version
}

action_uninstall() {
    echo "===== 卸载frpc ====="
    ans=$(ask "确认卸载frpc？停止服务、删除${INSTALL_DIR}、init脚本与命令 [Y/n] " "Y")
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
    ACTION="$1"
    case "${ACTION}" in
        install|update|uninstall) ;;
        ""|-h|--help|help)
            usage
            exit 0
            ;;
        *)
            echo "❌ 未知参数: ${ACTION}"
            usage
            exit 1
            ;;
    esac

    check_and_install_deps
    check_script_update "$@"

    case "${ACTION}" in
        install)   action_install ;;
        update)    action_update ;;
        uninstall) action_uninstall ;;
    esac
}

main "$@"
