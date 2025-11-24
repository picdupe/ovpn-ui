#!/bin/bash
# 创建OpenVPN用户脚本

set -e

USERNAME=$1
PASSWORD=$2
MAX_DEVICES=${3:-2}

INSTALL_DIR="/usr/local/ovpn-ui"
CONFIG_DIR="/etc/ovpn-ui"
AUTH_FILE="$CONFIG_DIR/openvpn/auth/users"
CCD_DIR="$CONFIG_DIR/openvpn/ccd"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# 检查参数
if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
    echo "用法: $0 <用户名> <密码> [最大设备数]"
    exit 1
fi

# 确保目录存在
mkdir -p "$(dirname "$AUTH_FILE")"
mkdir -p "$CCD_DIR"

log "创建OpenVPN用户: $USERNAME"

# 创建用户认证文件
PASSWORD_HASH=$(openssl passwd -1 "$PASSWORD")
echo "$USERNAME:$PASSWORD_HASH" >> "$AUTH_FILE"

# 创建CCD配置文件
CCD_FILE="$CCD_DIR/$USERNAME"

# 获取下一个可用的IP
get_next_ip() {
    local used_ips=()
    
    if [ -d "$CCD_DIR" ]; then
        for file in "$CCD_DIR"/*; do
            if [ -f "$file" ]; then
                ip=$(grep "ifconfig-push" "$file" | awk '{print $2}' | cut -d. -f4)
                if [ -n "$ip" ]; then
                    used_ips+=($ip)
                fi
            fi
        done
    fi
    
    # 从50开始分配IP
    for ip in {50..254}; do
        if [[ ! " ${used_ips[@]} " =~ " ${ip} " ]]; then
            echo $ip
            return
        fi
    done
    
    echo 254
}

IP_END=$(get_next_ip)

cat > "$CCD_FILE" << EOF
ifconfig-push 10.8.0.$IP_END 255.255.255.0
push "max-routes $MAX_DEVICES"
EOF

log "用户 $USERNAME 创建成功"
log "分配的IP: 10.8.0.$IP_END"
log "最大设备数: $MAX_DEVICES"

# 设置权限
chmod 600 "$AUTH_FILE"
chmod 644 "$CCD_FILE"

echo "✅ OpenVPN用户 $USERNAME 创建成功"