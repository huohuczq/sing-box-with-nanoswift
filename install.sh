#!/usr/bin/env bash

set -e # 出错时立即退出

detect_target() {
    local arch os
    arch="$(uname -m)"
    os="$(uname -s)"

    case "$arch" in
        x86_64|amd64)
            [[ "$os" == "Darwin" ]] && echo "darwin-amd64" || echo "linux-amd64"
            ;;
        aarch64|arm64)
            [[ "$os" == "Darwin" ]] && echo "darwin-arm64" || echo "linux-arm64"
            ;;
        armv7l|armv7*) echo "linux-arm" ;;
        armv6l|armv6*) echo "linux-armv6" ;;
        mips)          echo "linux-mips" ;;
        mipsel|mipsle) echo "linux-mipsle" ;;
        riscv64)       echo "linux-riscv64" ;;
        *)             echo "unsupported"; return 1 ;;
    esac
}

# 智能环境兼容：如果当前是 root 用户，或者系统根本没有 sudo 命令，则让 sudo 关键字失效（变成直接执行）
if [ "$(id -u)" -eq 0 ] || ! command -v sudo &> /dev/null; then
    sudo() { "$@"; }
fi

# 配置安装目录与自启动服务
setup_service() {
    local binary_path="$1"
    
    while true; do
        read -p "📝 请输入 sing-box 的安装目录 (例如: /opt/sing-box): " INSTALL_DIR
        
        if [ -z "$INSTALL_DIR" ]; then
            INSTALL_DIR="/opt/sing-box"
            echo "💡 检测到输入为空，已自动为你创建默认目录: $INSTALL_DIR"
            break
        fi
        if [ -n "$INSTALL_DIR" ]; then
            break
        fi
    done

    INSTALL_DIR="${INSTALL_DIR%/}"

    echo "📂 正在创建必要的系统目录: $INSTALL_DIR/run ..."
    sudo mkdir -p "$INSTALL_DIR/run"

    echo "🚚 正在部署二进制文件到 $INSTALL_DIR/sing-box ..."
    sudo cp "$binary_path" "$INSTALL_DIR/sing-box"
    sudo chmod +x "$INSTALL_DIR/sing-box"

    echo "⚙️ 正在检测系统初始化管理器并配置自启动..."
    
    # === 例外处理：检测是否为 OpenWrt 环境 ===
    if [ -f /etc/openwrt_release ] || [ -d /etc/config ]; then
        echo "   检测到系统为 [OpenWrt / ImmortalWrt] 正在配置 UCI 服务..."
        cat <<EOF | sudo tee /etc/config/sing-box > /dev/null
config sing-box 'main'
    option enabled '1'
    option conffile '$INSTALL_DIR/run/config.json'
    option workdir '$INSTALL_DIR/'
    option log_stderr '1'
    option delay '2'
EOF

        cat <<EOF | sudo tee /etc/init.d/sing-box > /dev/null
#!/bin/sh /etc/rc.common

USE_PROCD=1
START=99
PROG="$INSTALL_DIR/sing-box"

start_service() {
    config_load "sing-box"

    local enabled config_file working_directory log_stderr delay
    config_get_bool enabled "main" "enabled" "0"
    [ "\$enabled" -eq "1" ] || return 0

    config_get config_file "main" "conffile" "$INSTALL_DIR/run/config.json"
    config_get working_directory "main" "workdir" "$INSTALL_DIR/"
    config_get_bool log_stderr "main" "log_stderr" "1"
    
    config_get delay "main" "delay" "0"
    if [ "\$delay" -gt 0 ]; then
        sleep "\$delay"
    fi

    procd_open_instance
    procd_set_param command "\$PROG" run -c "\$config_file" -D "\$working_directory"
    procd_set_param env HOME="\$working_directory"
    procd_set_param file "\$config_file"
    procd_set_param stderr "\$log_stderr"
    procd_set_param limits core="unlimited"
    procd_set_param limits nofile="1000000 1000000"
    procd_set_param respawn
    procd_close_instance
}

service_triggers() {
    procd_add_reload_trigger "sing-box"
}
EOF
        
        sudo chmod +x /etc/init.d/sing-box
        echo "🔄 正在注册并启动 OpenWrt procd 服务..."
        sudo /etc/init.d/sing-box enable
        sudo /etc/init.d/sing-box start
        echo "✅ OpenWrt UCI/Procd 自启动服务已成功激活！"

    # === 常规系统：检测 systemd (Ubuntu, Debian 等) ===
    elif [ -d /run/systemd/system ] || pidof systemd &>/dev/null; then
        echo "   检测到系统使用 [systemd] (Ubuntu/Debian)..."
        
        if [ ! -f "$INSTALL_DIR/config.json" ]; then
            echo '{}' | sudo tee "$INSTALL_DIR/config.json" > /dev/null
        fi

        cat <<EOF | sudo tee /etc/systemd/system/sing-box.service > /dev/null
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=$INSTALL_DIR/sing-box run -c $INSTALL_DIR/config.json
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

        sudo systemctl daemon-reload
        sudo systemctl enable sing-box
        sudo systemctl start sing-box
        echo "✅ systemd 自启动服务已成功创建并启动！"

    # === 常规系统：检测 OpenRC (Alpine Linux) ===
    elif [ -f /sbin/openrc-run ] || [ -d /etc/init.d ]; then
        echo "   检测到系统使用 [OpenRC] (Alpine)..."
        
        if [ ! -f "$INSTALL_DIR/config.json" ]; then
            echo '{}' | sudo tee "$INSTALL_DIR/config.json" > /dev/null
        fi

        cat <<EOF | sudo tee /etc/init.d/sing-box > /dev/null
#!/sbin/openrc-run

description="sing-box service"
command="$INSTALL_DIR/sing-box"
command_args="run -c $INSTALL_DIR/config.json"
pidfile="/run/\${RC_SVCNAME}.pid"
command_background="yes"

depend() {
    need net
    after firewall
}
EOF
        sudo chmod +x /etc/init.d/sing-box
        sudo rc-update add sing-box default 2>/dev/null || true
        sudo rc-service sing-box start
        echo "✅ OpenRC 自启动服务已成功创建并启动！"
    
    else
        echo "⚠️ 未能识别兼容的初始化系统，跳过自启动创建。"
    fi

    # 5. 提示控制面板访问 URL
    echo "--------------------------------------------------"
    echo "🎉 🎉 🎉 安装部署成功 🎉 🎉 🎉"
    echo "🔗 控制面板访问 URL: http://127.0.0.1:9090/ui"
    if [ -f /etc/openwrt_release ]; then
        echo "⚙️  OpenWrt 配置文件路径: $INSTALL_DIR/run/config.json"
        echo "🔧 你可以通过 uci 命令或修改 /etc/config/sing-box 管理服务"
    else
        echo "⚙️  配置文件路径: $INSTALL_DIR/config.json"
    fi
    echo "--------------------------------------------------"
}

# ==================== 主流程 ====================

platform=$(detect_target)
if [ "$platform" = "unsupported" ] || [ -z "$platform" ]; then
    echo "❌ 错误: 未知或不受支持的系统平台架构。"
    exit 1
fi
echo "   已检测到平台: $platform"

# 1. 交互选择加速节点（使用 Heredoc 结构规避一切字符冲突）
cat << 'EOF'
==================================================
🚀 欢迎使用 sing-box 自动化安装脚本
==================================================
⚡ 请选择适合你当前网络环境的 GitHub 加速代理:
1) 不使用代理 (直连官方 GitHub)
2) v4.gh-proxy.org (推荐 IPv4 环境使用)
3) v6.gh-proxy.org (纯 IPv6 / 校园网环境首选)
==================================================
EOF
read -p "请输入序号 [1-3] (默认选择 2): " PROXY_CHOICE
[ -z "$PROXY_CHOICE" ] && PROXY_CHOICE=2

case "$PROXY_CHOICE" in
    1) PROXY_PREFIX="" ;;
    2) PROXY_PREFIX="https://v4.gh-proxy.org/" ;;
    3) PROXY_PREFIX="https://v6.gh-proxy.org/" ;;
    *) PROXY_PREFIX="https://v4.gh-proxy.org/" ;;
esac

# 创建临时工作目录
WORK_DIR="dist/$(date +%Y-%m-%d)"
mkdir -p "$WORK_DIR"

# 2. 构建下载路径
RAW_BASE_URL="https://raw.githubusercontent.com/is928joe-jpg/sing-box-with-nanoswift/refs/heads/main/2026-06-18"
BINARY_NAME="sing-box-${platform}"
SHA_NAME="${BINARY_NAME}.sha256"

FINAL_BIN_URL="${PROXY_PREFIX}${RAW_BASE_URL}/${BINARY_NAME}"
FINAL_SHA_URL="${PROXY_PREFIX}${RAW_BASE_URL}/${SHA_NAME}"

# 3. 下载到正确的位置
echo "📥 正在从网络获取二进制文件到 ${WORK_DIR}/ ..."
if ! curl -L -o "${WORK_DIR}/${BINARY_NAME}" "$FINAL_BIN_URL"; then
    echo "❌ 错误: 下载二进制文件失败。"
    exit 1
fi

echo "📥 正在从网络获取哈希校验文件..."
if ! curl -L -o "${WORK_DIR}/${SHA_NAME}" "$FINAL_SHA_URL"; then
    echo "❌ 错误: 下载校验文件失败。"
    exit 1
fi

# 4. 进入工作目录进行校验
cd "$WORK_DIR"
echo "🔍 正在进行 SHA256 安全校验..."
if command -v sha256sum &> /dev/null; then
    sha256sum -c "$SHA_NAME"
elif command -v shasum &> /dev/null; then
    shasum -a 256 -c "$SHA_NAME"
else
    echo "❌ 错误: 找不到 sha256sum 或 shasum 命令。"
    exit 1
fi

# 5. 返回到脚本根目录进行安装
cd - > /dev/null
setup_service "${WORK_DIR}/${BINARY_NAME}"