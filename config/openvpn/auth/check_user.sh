#!/bin/bash
#
# OpenVPN 用户验证脚本

USERNAME_FILE="$1"
PASSWORD_FILE="$2"

# 读取用户名和密码
USERNAME=$(cat "$USERNAME_FILE")
PASSWORD=$(cat "$PASSWORD_FILE")

# 调用WebUI的验证API
RESPONSE=$(curl -s -f -X POST \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}" \
  http://127.0.0.1:5000/api/v1/auth/verify)

if [ $? -eq 0 ] && [ "$RESPONSE" = "success" ]; then
    exit 0
else
    echo "Authentication failed for user: $USERNAME"
    exit 1
fi