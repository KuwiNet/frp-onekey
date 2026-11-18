#!/bin/bash
# Linux systemd frps onekey install script
# ScriptVersion=2.4.0
# Upstream-FRP-Version: v0.72.0
# Install dir: /opt/frps
# Systemd service: /etc/systemd/system/frps.service
# Cmd: frps xxx
#
# GitHub 文件加速：https://oproxy.cc （raw / api / release 资源均可加速）

SCRIPT_VERSION="2.4.0"
SCRIPT_NAME="frps.sh"
INSTALL_DIR="/opt/frps"
FRPS_BIN="${INSTALL_DIR}/frps-bin"
FRPS_TOML="${INSTALL_DIR}/frps.toml"
CUSTOM_404="${INSTALL_DIR}/404.html"
SYSTEMD_UNIT="/etc/systemd/system/frps.service"
BIN_LINK="/usr/bin/frps"

GH_REPO="KuwiNet/frp-onekey"
GH_BRANCH="master"
GH_RAW_BASE="https://raw.githubusercontent.com/${GH_REPO}/${GH_BRANCH}"
PROXY_HOST="https://oproxy.cc"

HAS_CURL=0
HAS_WGET=0

usage() {
cat <<EOF
用法: sudo bash ${SCRIPT_NAME} <install|update|uninstall>

  install    全新安装frps，已安装则检测版本更新；已有toml保留原有配置
  update     强制更新脚本、frps二进制与404.html，不改动toml配置
  uninstall  卸载frps，清理全部文件与systemd单元
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
    if [[ "${HAS_CURL}" -eq 1 ]]; then
        curl -fsSL --connect-timeout 8 -m "${2:-15}" --retry 2 --retry-delay 1 "$1" 2>/dev/null
    elif [[ "${HAS_WGET}" -eq 1 ]]; then
        wget -q -T "${2:-15}" -t 2 -O- "$1" 2>/dev/null
    else
        return 1
    fi
}

# 下载文件到指定路径，失败返回非0（curl -f 保证 4xx/5xx 不会写成文件）
http_download() {
    if [[ "${HAS_CURL}" -eq 1 ]]; then
        curl -fSL --connect-timeout 10 --retry 3 --retry-delay 2 -m 900 "$1" -o "$2" 2>/dev/null
    elif [[ "${HAS_WGET}" -eq 1 ]]; then
        wget -q -T 120 -t 3 -O "$2" "$1" 2>/dev/null
    else
        return 1
    fi
}

# 按顺序尝试多个地址，返回第一个非空结果
fetch_first() {
    for _u in "$@"; do
        _out=$(http_get "${_u}")
        if [[ -n "${_out}" ]]; then
            printf '%s' "${_out}"
            return 0
        fi
    done
    return 1
}

# 交互式询问；非交互环境（curl|bash、CI）直接采用默认值
ask() {
    _prompt="$1"
    _def="${2:-}"
    if [[ ! -t 0 ]]; then
        printf '%s%s\n' "${_prompt}" "${_def}" >&2
        printf '%s' "${_def}"
        return 0
    fi
    printf '%s' "${_prompt}" >&2
    IFS= read -r _ans || _ans=""
    printf '%s' "${_ans:-${_def}}"
}

check_and_install_deps() {
    echo "==> 检查系统依赖工具..."
    NEED=""
    for cmd in tar gzip grep sed awk; do
        if ! command -v "${cmd}" &>/dev/null;then
            echo "⚠️ 缺失 ${cmd}"
            NEED="${NEED} ${cmd}"
        fi
    done
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

# 判断 $1 是否比 $2 更新（避免本地版本更高时被“更新”成旧版本）
ver_is_newer() {
    _max=$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)
    [[ "${_max}" == "$1" && "$1" != "$2" ]]
}

check_script_update() {
    echo "==> 检查脚本版本更新..."
    RAW_SELF="${GH_RAW_BASE}/${SCRIPT_NAME}"
    PROXY_SELF=$(proxy_url "${RAW_SELF}")

    REMOTE_VER=$(fetch_first "${PROXY_SELF}" "${RAW_SELF}" | grep 'SCRIPT_VERSION=' | head -n1 | cut -d'"' -f2)

    if [[ -z "${REMOTE_VER}" ]];then
        echo "⚠️ oproxy.cc 与 GitHub 均无法访问，跳过脚本版本检测"
        return 0
    fi
    if [[ "${REMOTE_VER}" == "${SCRIPT_VERSION}" ]];then
        echo "脚本已是最新版本 (${SCRIPT_VERSION})"
        return 0
    fi
    if ! ver_is_newer "${REMOTE_VER}" "${SCRIPT_VERSION}";then
        echo "本地脚本(${SCRIPT_VERSION})高于远端(${REMOTE_VER})，跳过自动更新"
        return 0
    fi

    echo "发现新版本脚本: ${REMOTE_VER} (当前:${SCRIPT_VERSION})"
    ans=$(ask "是否自动更新脚本? [Y/n] " "Y")
    if [[ ! "${ans}" =~ ^[Yy]$ ]];then
        echo "跳过脚本更新"
        return 0
    fi

    SELF_PATH="$0"
    if [[ ! -f "${SELF_PATH}" || ! -w "${SELF_PATH}" ]];then
        echo "⚠️ 当前脚本文件不可写（${SELF_PATH}），请手动下载最新脚本后重新执行"
        return 0
    fi

    # 先下载到临时文件再原子替换，避免覆盖正在被 bash 读取的脚本
    TMP_SELF=$(mktemp) || { echo "❌ 创建临时文件失败，跳过脚本更新"; return 0; }
    UPDATED=0
    for url in "${PROXY_SELF}" "${RAW_SELF}";do
        if http_download "${url}" "${TMP_SELF}" && grep -q 'SCRIPT_VERSION=' "${TMP_SELF}";then
            UPDATED=1
            break
        fi
    done
    if [[ ${UPDATED} -ne 1 ]];then
        echo "❌ 脚本下载失败，保留当前版本"
        rm -f "${TMP_SELF}"
        return 0
    fi
    # 防止 CDN 返回被截断的文件：语法校验通过才替换
    if ! bash -n "${TMP_SELF}" 2>/dev/null;then
        echo "❌ 下载的脚本不完整（语法校验未通过），保留当前版本"
        rm -f "${TMP_SELF}"
        return 0
    fi

    chmod +x "${TMP_SELF}"
    mv -f "${TMP_SELF}" "${SELF_PATH}" || { echo "❌ 脚本替换失败，保留当前版本"; rm -f "${TMP_SELF}"; return 0; }
    echo "✅ 脚本已更新至 ${REMOTE_VER}，自动重新执行"
    exec bash "${SELF_PATH}" "$@"
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
    echo "1) 国内(oproxy.cc 镜像加速)"
    echo "2) 国外(GitHub 官方，默认)"
    area=$(ask "输入选项 [1/2] (默认2): " "2")
    [[ "${area}" == "1" ]] || area=2

    API_RAW="https://api.github.com/repos/fatedier/frp/releases/latest"
    API_PROXY=$(proxy_url "${API_RAW}")

    echo "获取frp最新版本信息..."
    if [[ "${area}" == "1" ]];then
        API_CONTENT=$(fetch_first "${API_PROXY}" "${API_RAW}")
    else
        API_CONTENT=$(fetch_first "${API_RAW}" "${API_PROXY}")
    fi

    if [[ -z "${API_CONTENT}" ]];then
        echo "❌ 无法获取frp版本信息，请检查网络（可尝试切换下载区域）"
        exit 1
    fi

    LATEST_FRPS_VER=$(printf '%s' "${API_CONTENT}" | grep -o '"tag_name":[[:space:]]*"[^"]*"' | head -n1 | cut -d'"' -f4 | sed 's/^v//')
    DL_URL_RAW=""
    for plat in ${PLAT_CANDIDATES};do
        DL_URL_RAW=$(printf '%s' "${API_CONTENT}" | tr ',' '\n' | grep -o "https://[^\"]*${plat}\.tar\.gz" | head -n1)
        [[ -n "${DL_URL_RAW}" ]] && break
    done

    if [[ -z "${DL_URL_RAW}" || -z "${LATEST_FRPS_VER}" ]];then
        echo "❌ 上游 v${LATEST_FRPS_VER:-unknown} 未提供当前架构(${ARCH})的安装包（候选: ${PLAT_CANDIDATES}）"
        echo "上游现有 Linux 包："
        printf '%s' "${API_CONTENT}" | tr ',' '\n' | grep -o 'frp_[0-9.]*_linux_[a-z0-9_]*\.tar\.gz' | sort -u | sed 's/^/  /'
        exit 1
    fi

    DL_URL="${DL_URL_RAW}"
    if [[ "${area}" == "1" ]];then
        DL_URL=$(proxy_url "${DL_URL_RAW}")
    fi
    echo "线上最新frp版本: v${LATEST_FRPS_VER}"
    echo "下载链接: ${DL_URL}"
}

download_frps() {
    mkdir -p "${INSTALL_DIR}"
    if [[ -z "${DL_URL}" ]];then
        echo "❌ 获取下载链接失败！"
        return 1
    fi

    TMP_DIR=$(mktemp -d) || { echo "❌ 创建临时目录失败"; return 1; }
    trap 'rm -rf "${TMP_DIR}"' RETURN
    TMP_FILE="${TMP_DIR}/frp.tar.gz"

    echo "开始下载frp..."
    if ! http_download "${DL_URL}" "${TMP_FILE}";then
        if [[ "${DL_URL}" == "${PROXY_HOST}"* ]];then
            echo "⚠️ oproxy.cc 加速下载失败，回退 GitHub 官方直连重试"
            http_download "${DL_URL_RAW}" "${TMP_FILE}" || true
        fi
    fi

    if [[ ! -s "${TMP_FILE}" ]];then
        echo "❌ 下载失败！请检查网络或切换下载区域"
        return 1
    fi

    FILE_HEAD=$(head -c2 "${TMP_FILE}" 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')
    if [[ -n "${FILE_HEAD}" && "${FILE_HEAD}" != "1f8b" ]];then
        echo "❌ 下载的不是有效的gzip压缩包，链接获取错误！"
        return 1
    fi
    if ! tar -tzf "${TMP_FILE}" >/dev/null 2>&1;then
        echo "❌ 压缩包校验失败（文件不完整或已损坏），请重试"
        return 1
    fi

    echo "解压..."
    tar -zxf "${TMP_FILE}" -C "${TMP_DIR}"
    FRPS_TMP=$(find "${TMP_DIR}" -maxdepth 2 -type f -name frps | head -n1)
    if [[ -z "${FRPS_TMP}" ]];then
        echo "❌ 解压后找不到frps二进制文件"
        return 1
    fi

    rm -f "${FRPS_BIN}"
    cp "${FRPS_TMP}" "${FRPS_BIN}"
    chmod +x "${FRPS_BIN}"
    echo "frps二进制提取完成: ${FRPS_BIN} ($("${FRPS_BIN}" --version 2>/dev/null))"
}

download_404html() {
    mkdir -p "${INSTALL_DIR}"
    RAW_404="${GH_RAW_BASE}/404.html"
    PROXY_404=$(proxy_url "${RAW_404}")
    echo "==> 下载404.html自定义错误页面..."
    CONTENT=$(fetch_first "${PROXY_404}" "${RAW_404}")
    if [[ -z "${CONTENT}" ]];then
        echo "⚠️ 404.html下载失败，保留现有文件（如有）：${CUSTOM_404}"
        return 0
    fi
    printf '%s\n' "${CONTENT}" > "${CUSTOM_404}"
    if grep -qi '<html' "${CUSTOM_404}";then
        echo "✅ 404.html已保存: ${CUSTOM_404}"
    else
        echo "⚠️ 404.html内容异常，请手动放置文件到 ${CUSTOM_404}"
        return 0
    fi
}

gen_config() {
    if [[ ! -t 0 ]];then
        echo "⚠️ 非交互模式，写入默认frps.toml模板(默认OIDC认证)"
        fillcfg="N"
    else
        fillcfg=$(ask "是否现在交互式填写frps.toml服务端配置? [Y/n] " "Y")
    fi

    if [[ ! "${fillcfg}" =~ ^[Yy]$ ]];then
        cat > "${FRPS_TOML}" <<EOF
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
    auth_mode=$(ask "输入选项 [1/2] (默认1): " "1")
    [[ "${auth_mode}" == "1" ]] || auth_mode=2

    cat > "${FRPS_TOML}" <<EOF
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
        oidc_issuer=$(ask "auth.oidc.issuer (默认https://www.afrp.net): " "https://www.afrp.net")
        oidc_audience=$(ask "auth.oidc.audience (默认afrp.net): " "afrp.net")
        subDomainHost=$(ask "subDomainHost (默认example.com): " "example.com")

cat >> "${FRPS_TOML}" <<AUTH
auth.method = "oidc"
auth.oidc.issuer = "${oidc_issuer}"
auth.oidc.audience = "${oidc_audience}"
# auth.method = "token"
# auth.token = "afrp.net"
AUTH
    else
        echo "----- Token认证参数配置 -----"
        auth_token=$(ask "auth.token (默认afrp.net): " "afrp.net")
        subDomainHost=$(ask "subDomainHost (默认example.com): " "example.com")

cat >> "${FRPS_TOML}" <<AUTH
auth.method = "token"
auth.token = "${auth_token}"
# auth.method = "oidc"
# auth.oidc.issuer = "https://www.afrp.net"
# auth.oidc.audience = "afrp.net"
AUTH
    fi

    adv_opt=$(ask "是否开启toml高级自定义选项? [Y/n] (默认N): " "N")

cat >> "${FRPS_TOML}" <<BASE
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
        webUser=$(ask "webServer.user (默认admin): " "admin")
        webPass=$(ask "webServer.password (默认admin): " "admin")
        maxPorts=$(ask "maxPortsPerClient (默认10): " "10")
        maxPool=$(ask "transport.maxPoolCount (默认5): " "5")
        heartbeat=$(ask "transport.heartbeatTimeout (默认90): " "90")

        if [[ "${auth_mode}" == "1" ]];then
            echo "--- OIDC模式高级参数 ---"
            allowUsers=$(ask "allowUsers 允许用户名，多个逗号分隔(留空不设置): " "")
        else
            echo "--- Token模式高级参数 ---"
            allowUsers=$(ask "allowUsers 允许用户名，多个逗号分隔(留空不设置): " "")
            additionalTokens=$(ask "additionalTokens 附加token，多个逗号分隔(留空不设置): " "")
        fi
    fi

cat >> "${FRPS_TOML}" <<WEB
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
cat >> "${FRPS_TOML}" <<AU
allowUsers = [$(printf '"%s"' "${allowUsers}" | sed 's/,/","/g')]
AU
    fi
    if [[ "${auth_mode}" == "2" && -n "${additionalTokens}" ]];then
cat >> "${FRPS_TOML}" <<AT
additionalTokens = [$(printf '"%s"' "${additionalTokens}" | sed 's/,/","/g')]
AT
    fi

    echo "✅ frps.toml配置写入完成: ${FRPS_TOML}"
}

install_service() {
cat > "${SYSTEMD_UNIT}" <<EOF
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

cat > "${BIN_LINK}" <<'SHELL'
#!/bin/bash
FRPS_BIN="/opt/frps/frps-bin"
FRPS_TOML="/opt/frps/frps.toml"

get_frps_pid() {
    if command -v pgrep >/dev/null 2>&1; then
        pgrep -f "${FRPS_BIN} -c" | head -n1
    else
        ps -ef | grep -v grep | grep "${FRPS_BIN}" | awk '{print $2}' | head -n1
    fi
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
    chmod +x "${BIN_LINK}"
    systemctl daemon-reload
    systemctl enable frps >/dev/null 2>&1
    echo "✅ systemd frps服务安装完成，已设置开机自启，命令 frps xxx 就绪"
}

action_install() {
    get_arch
    get_frp_info

    SERVICE_WAS_RUNNING=0
    if systemctl is-active --quiet frps 2>/dev/null;then
        SERVICE_WAS_RUNNING=1
    fi

    UPGRADED=0
    if [[ -f "${FRPS_BIN}" ]];then
        echo "✅ 检测到已存在frps二进制文件"
        VER_OUT=$(${FRPS_BIN} --version 2>/dev/null)
        CURRENT_FRPS_VER=$(printf '%s' "${VER_OUT}" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')
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
            upgrade_ans=$(ask "发现新版本frps，是否升级frps二进制？[Y/n] " "Y")
            if [[ "${upgrade_ans}" =~ ^[Yy]$ ]];then
                echo "停止frps服务准备升级..."
                [[ ${SERVICE_WAS_RUNNING} -eq 1 ]] && systemctl stop frps 2>/dev/null
                if download_frps;then
                    UPGRADED=1
                    echo "升级完成"
                else
                    echo "❌ 升级失败，保留原二进制与配置"
                    [[ ${SERVICE_WAS_RUNNING} -eq 1 ]] && systemctl start frps 2>/dev/null
                    exit 1
                fi
            else
                echo "跳过frps二进制升级"
            fi
        fi
    else
        echo "未检测到frps二进制，开始全新下载安装"
        if ! download_frps;then
            echo "❌ 安装失败，请检查网络后重试"
            exit 1
        fi
    fi

    if [[ ! -f "${FRPS_TOML}" ]];then
        echo "📄 frps.toml不存在，进入配置生成流程"
        gen_config
    else
        echo "✅ 已存在frps.toml，保留原有配置，跳过配置填写"
    fi

    download_404html
    install_service

    if [[ ${UPGRADED} -eq 1 && ${SERVICE_WAS_RUNNING} -eq 1 ]];then
        systemctl restart frps 2>/dev/null
        echo "✅ 升级后已重启frps服务"
    fi

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
    get_arch
    get_frp_info
    echo "停止frps..."
    systemctl stop frps 2>/dev/null
    if ! download_frps;then
        echo "❌ 更新失败，尝试恢复原服务"
        systemctl start frps 2>/dev/null
        exit 1
    fi
    download_404html
    systemctl daemon-reload
    systemctl start frps 2>/dev/null
    echo "✅ frps更新完成"
    ${FRPS_BIN} --version
}

action_uninstall() {
    echo "===== 卸载frps ====="
    ans=$(ask "确认卸载frps？停止服务、删除${INSTALL_DIR}、systemd单元与frps命令 [Y/n] " "Y")
    if [[ ! "${ans}" =~ ^[Yy]$ ]];then
        echo "取消卸载"
        exit 0
    fi
    systemctl stop frps 2>/dev/null
    systemctl disable frps 2>/dev/null
    rm -f "${SYSTEMD_UNIT}"
    rm -f "${BIN_LINK}"
    rm -rf "${INSTALL_DIR}"
    systemctl daemon-reload
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

if [[ ${EUID} -ne 0 ]];then
    echo "❌ 必须使用root/sudo执行本脚本！"
    exit 1
fi

main "$@"
