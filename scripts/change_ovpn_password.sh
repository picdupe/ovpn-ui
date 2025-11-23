#!/bin/bash
# 修改OpenVPN用户密码脚本

set -e

USERNAME=$1
CURRENT_PASSWORD=$2
NEW_PASSWORD=$3

INSTALL_DIR="/opt/ovpn-ui"
AUTH_FILE="$INSTALL_DIR/config/openvpn/auth/users"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# 检查参数
if [ -z "$USERNAME" ] || [ -z "$CURRENT_PASSWORD" ] || [ -z "$NEW_PASSWORD" ]; then
    echo "用法: $0 <用户名> <当前密码> <新密码>"
    exit 1
fi

# 检查认证文件是否存在
if [ ! -f "$AUTH_FILE" ]; then
    echo "错误: 认证文件不存在"
    exit 1
fi

log "修改用户 $USERNAME 的密码"

# 验证当前密码并更新
CURRENT_HASH=$(openssl passwd -1 "$CURRENT_PASSWORD")
NEW_HASH=$(openssl passwd -1 "$NEW_PASSWORD")

# 创建临时文件
TEMP_FILE=$(mktemp)

# 更新密码
UPDATED=false
while IFS= read -r line; do
    if [[ "$line" == "$USERNAME:"* ]]; then
        if [[ "$line" == *"$CURRENT_HASH" ]]; then
            echo "$USERNAME:$NEW_HASH" >> "$TEMP_FILE"
            UPDATED=true
            log "密码验证成功，更新密码"
        else
            echo "错误: 当前密码不正确" >&2
            rm -f "$TEMP_FILE"
            exit 1
        fi
    else
        echo "$line" >> "$TEMP_FILE"
    fi
done < "$AUTH_FILE"

if [ "$UPDATED" = true ]; then
    # 替换原文件
    mv "$TEMP_FILE" "$AUTH_FILE"
    chmod 600 "$AUTH_FILE"
    log "用户 $USERNAME 密码修改成功"
    echo "✅ 密码修改成功"
else
    rm -f "$TEMP_FILE"
    echo "错误: 用户 $USERNAME 不存在" >&2
    exit 1
fi