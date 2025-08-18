#!/bin/bash

SERVICE_NAME="headphone-monitor.service"

# 仅对支持 systemd 的用户执行
if [ -n "$XDG_RUNTIME_DIR" ] && command -v systemctl &>/dev/null; then
    # 检查服务文件是否存在
    if [ -f "$HOME/.config/systemd/user/$SERVICE_NAME" ] || [ -f "/etc/systemd/user/$SERVICE_NAME" ]; then
        # 如果服务尚未启用，则启用一次
        systemctl --user is-enabled "$SERVICE_NAME" &>/dev/null || {
            echo "[INFO] Enabling user service: $SERVICE_NAME"
            systemctl --user enable "$SERVICE_NAME"
            systemctl --user start "$SERVICE_NAME"
        }
    fi
fi