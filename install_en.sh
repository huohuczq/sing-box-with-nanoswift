# Configure installation directory and startup service
setup_service() {
    local binary_path="$1"
    
    echo "--------------------------------------------------"
    # 1. Prompt for installation directory (with non-empty validation loop)
    while true; do
        read -p "📝 Enter the installation directory for sing-box (e.g. /opt/sing-box): " INSTALL_DIR
        
        # If user presses Enter directly, use default value and exit loop
        if [ -z "$INSTALL_DIR" ]; then
            INSTALL_DIR="/opt/sing-box"
            echo "💡 Empty input detected, using default directory: $INSTALL_DIR"
            break
        fi
        
        # If user entered a value, exit loop
        if [ -n "$INSTALL_DIR" ]; then
            break
        fi
    done

    # Remove trailing slash if present
    INSTALL_DIR="${INSTALL_DIR%/}"

    echo "📂 Creating installation and runtime directory: $INSTALL_DIR/run ..."
    sudo mkdir -p "$INSTALL_DIR/run"

    # 2. Copy downloaded binary to installation directory
    echo "🚚 Copying binary file to $INSTALL_DIR/sing-box ..."
    sudo cp "$binary_path" "$INSTALL_DIR/sing-box"
    
    # 3. Set executable permission
    sudo chmod +x "$INSTALL_DIR/sing-box"

    # 4. Detect init system and create startup service
    echo "⚙️ Detecting system init manager..."
    
    # === Special case: OpenWrt detection ===
    if [ -f /etc/openwrt_release ] || [ -d /etc/config ]; then
        echo "   Detected [OpenWrt / ImmortalWrt], configuring UCI service..."

        if [ ! -f "$INSTALL_DIR/run/config.json" ]; then
            echo "📝 Creating default empty configuration: $INSTALL_DIR/run/config.json ..."
            echo '{}' | sudo tee "$INSTALL_DIR/run/config.json" > /dev/null
        fi

        # Write /etc/config/sing-box
        cat <<EOF | sudo tee /etc/config/sing-box > /dev/null
config sing-box 'main'
    option enabled '1'
    option conffile '$INSTALL_DIR/run/config.json'
    option workdir '$INSTALL_DIR/'
    option log_stderr '1'
    option delay '2'
EOF

        # Write /etc/init.d/sing-box
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
    
    # 1. Read delay value from configuration
    config_get delay "main" "delay" "0"

    # 2. Wait for storage devices to mount during boot if delay is configured
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
        echo "🔄 Enabling and starting OpenWrt procd service..."
        sudo /etc/init.d/sing-box enable
        sudo /etc/init.d/sing-box start
        echo "✅ OpenWrt UCI/Procd startup service has been created and activated successfully!"

    # === Standard systems: systemd (Ubuntu, Debian, etc.) ===
    elif [ -d /run/systemd/system ] || pidof systemd &>/dev/null; then
        echo "   Detected [systemd] (Ubuntu/Debian)..."
        
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
        echo "✅ systemd startup service has been created and started successfully!"

    # === Standard systems: OpenRC (Alpine Linux) ===
    elif [ -f /sbin/openrc-run ] || [ -d /etc/init.d ]; then
        echo "   Detected [OpenRC] (Alpine Linux)..."
        
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
        echo "✅ OpenRC startup service has been created and started successfully!"
    
    else
        echo "⚠️ No supported init system detected. Skipping startup service creation."
    fi

    # 5. Display panel access URL
    echo "--------------------------------------------------"
    echo "🎉 🎉 🎉 Installation completed successfully 🎉 🎉 🎉"
    echo "🔗 Control Panel URL: http://127.0.0.1:9090"
    if [ -f /etc/openwrt_release ]; then
        echo "⚙️  OpenWrt configuration file: $INSTALL_DIR/run/config.json"
        echo "🔧 You can manage the service using UCI commands or by editing /etc/config/sing-box"
    else
        echo "⚙️  Configuration file: $INSTALL_DIR/config.json"
    fi
    echo "--------------------------------------------------"
}