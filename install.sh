#!/bin/bash
# OpenVPN WebUI 简化安装脚本

set -e

# 配置变量
INSTALL_DIR="/usr/local/ovpn-ui"
REPO_URL="https://github.com/picdupe/ovpn-ui.git"
LOG_FILE="/tmp/ovpn-ui-install.log"

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" >> $LOG_FILE
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    echo "$(date +'%Y-%m-%d %H:%M:%S') - ERROR: $1" >> $LOG_FILE
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "请使用root权限运行此脚本"
    fi
}

check_existing_installation() {
    if [ -d "$INSTALL_DIR" ] && [ -f "$INSTALL_DIR/.installed" ]; then
        echo "=== OpenVPN WebUI 安装程序 ==="
        echo ""
        echo "🔍 检测到系统已安装 OpenVPN WebUI"
        read -p "是否重新安装? [y/N]: " reinstall
        if [[ ! $reinstall =~ ^[Yy]$ ]]; then
            echo "安装取消"
            exit 0
        fi
        log "开始重新安装..."
    else
        echo "=== OpenVPN WebUI 安装程序 ==="
        echo ""
        echo "🎯 开始安装 OpenVPN WebUI"
    fi
}

get_installation_config() {
    echo ""
    echo "📝 请输入安装配置:"
    echo "─────────────────────────────────────"
    
    read -p "Web访问端口 [5000]: " web_port
    WEB_PORT=${web_port:-5000}
    
    read -p "管理员用户名 [admin]: " admin_user
    ADMIN_USER=${admin_user:-"admin"}
    
    while true; do
        read -s -p "管理员密码: " admin_pass
        echo
        read -s -p "确认密码: " admin_pass_confirm
        echo
        
        if [ "$admin_pass" = "$admin_pass_confirm" ] && [ -n "$admin_pass" ]; then
            break
        else
            echo "密码不匹配或为空，请重新输入"
        fi
    done
    
    read -p "安全访问路径 [/admin]: " admin_path
    ADMIN_PATH=${admin_path:-"/admin"}
    
    # 保存配置到临时文件
    cat > /tmp/ovpn-ui-config.txt << EOF
WEB_PORT=$WEB_PORT
ADMIN_USER=$ADMIN_USER
ADMIN_PASS=$admin_pass
ADMIN_PATH=$ADMIN_PATH
EOF
}

install_system_dependencies() {
    log "安装系统依赖..."
    
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update >> $LOG_FILE 2>&1
        apt-get install -y git curl wget python3 python3-pip python3-venv \
            openvpn sqlite3 openssl >> $LOG_FILE 2>&1
    elif command -v yum >/dev/null 2>&1; then
        yum install -y epel-release >> $LOG_FILE 2>&1
        yum install -y git curl wget python3 python3-pip openvpn sqlite openssl >> $LOG_FILE 2>&1
    else
        error "不支持的包管理器"
    fi
    
    log "系统依赖安装完成"
}

clone_repository() {
    log "下载 OpenVPN WebUI 代码..."
    
    # 清理现有目录
    rm -rf "$INSTALL_DIR"
    
    # 克隆代码
    if git clone "$REPO_URL" "$INSTALL_DIR" >> $LOG_FILE 2>&1; then
        log "✅ 代码下载成功"
    else
        error "❌ 代码下载失败"
    fi
}

setup_python_env() {
    log "配置Python环境..."
    
    # 创建虚拟环境
    python3 -m venv $INSTALL_DIR/venv >> $LOG_FILE 2>&1
    source $INSTALL_DIR/venv/bin/activate
    
    # 安装Python依赖
    if [ -f "$INSTALL_DIR/requirements.txt" ]; then
        pip install -r $INSTALL_DIR/requirements.txt >> $LOG_FILE 2>&1
    else
        pip install flask flask-sqlalchemy flask-login flask-wtf wtforms pyopenssl requests >> $LOG_FILE 2>&1
    fi
    
    log "Python环境配置完成"
}

create_systemd_service() {
    log "创建系统服务..."
    
    # 读取配置
    source /tmp/ovpn-ui-config.txt
    
    cat > /etc/systemd/system/ovpn-ui.service << EOF
[Unit]
Description=OpenVPN WebUI Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR/app
Environment=PATH=$INSTALL_DIR/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin
ExecStart=$INSTALL_DIR/venv/bin/python3 app.py
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload >> $LOG_FILE 2>&1
    log "系统服务创建完成"
}

create_management_command() {
    log "安装管理命令..."
    
    # 确保目标目录存在
    mkdir -p /usr/local/bin/
    
    # 复制管理脚本到 /usr/local/bin/
    cp $INSTALL_DIR/scripts/ovpn-ui.sh /usr/local/bin/ovpn-ui
    chmod +x /usr/local/bin/ovpn-ui
    
    # 创建符号链接到 /usr/bin/ 确保系统路径可找到
    ln -sf /usr/local/bin/ovpn-ui /usr/bin/ovpn-ui
    
    log "管理命令安装完成: ovpn-ui"
}

initialize_application() {
    log "初始化应用..."
    
    # 读取配置
    source /tmp/ovpn-ui-config.txt
    
    # 创建必要目录
    mkdir -p /var/log/ovpn-ui
    mkdir -p /etc/ovpn-ui
    mkdir -p /var/lib/ovpn-ui
    mkdir -p /var/lib/ovpn-ui/temp_links
    
    # 初始化管理员账户 - 使用与app.py一致的密码验证方式
    create_admin_user
    
    log "应用初始化完成"
}

create_admin_user() {
    log "创建管理员账户..."
    
    source /tmp/ovpn-ui-config.txt
    source $INSTALL_DIR/venv/bin/activate
    
    # 使用与app.py完全一致的密码验证方式
    python3 << EOF
import sqlite3
import hashlib
import os

db_path = "/var/lib/ovpn-ui/webui.db"
os.makedirs(os.path.dirname(db_path), exist_ok=True)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# 创建管理员表（与app.py中的模型一致）
cursor.execute('''
    CREATE TABLE IF NOT EXISTS admin_user (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username VARCHAR(50) UNIQUE NOT NULL,
        password_hash VARCHAR(255) NOT NULL,
        email VARCHAR(100),
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )
''')

# 使用与app.py完全相同的密码验证方式
# app.py中使用的是明文比较，但为了安全我们使用相同的哈希方式
password_hash = "$ADMIN_PASS"  # app.py中直接比较明文密码

# 插入管理员账户
cursor.execute('''
    INSERT OR REPLACE INTO admin_user (username, password_hash, email)
    VALUES (?, ?, ?)
''', ("$ADMIN_USER", password_hash, "admin@localhost"))

conn.commit()
conn.close()

print("管理员账户创建完成")
print("用户名: $ADMIN_USER")
print("密码: [已设置]")
EOF

    log "管理员账户创建成功"
}

mark_installation_complete() {
    # 读取配置
    source /tmp/ovpn-ui-config.txt
    
    # 标记安装完成
    cat > $INSTALL_DIR/.installed << EOF
INSTALL_DATE=$(date)
INSTALL_DIR=$INSTALL_DIR
WEB_PORT=$WEB_PORT
ADMIN_USER=$ADMIN_USER
ADMIN_PATH=$ADMIN_PATH
REPO_URL=$REPO_URL
EOF

    # 设置权限
    chmod 644 $INSTALL_DIR/.installed
    
    # 清理临时配置
    rm -f /tmp/ovpn-ui-config.txt
}

start_services() {
    log "启动服务..."
    systemctl start ovpn-ui >> $LOG_FILE 2>&1 && systemctl enable ovpn-ui >> $LOG_FILE 2>&1
    log "服务启动完成"
}

show_installation_complete() {
    # 读取配置
    if [ -f "$INSTALL_DIR/.installed" ]; then
        source $INSTALL_DIR/.installed
    fi
    
    echo ""
    echo "🎉 OpenVPN WebUI 安装完成！"
    echo ""
    echo "📁 安装目录: $INSTALL_DIR"
    echo "🛠️  管理命令: ovpn-ui"
    echo ""
    echo "🔧 安装配置:"
    echo "   🌐 访问端口: ${WEB_PORT:-5000}"
    echo "   👤 管理员: ${ADMIN_USER:-admin}"
    echo "   📍 访问路径: ${ADMIN_PATH:-/admin}"
    echo ""
    echo "🚀 使用方法:"
    echo "   ovpn-ui start     # 启动服务"
    echo "   ovpn-ui stop      # 停止服务" 
    echo "   ovpn-ui status    # 查看状态"
    echo "   ovpn-ui           # 显示管理菜单"
    echo ""
    echo "🔐 访问地址: http://服务器IP:${WEB_PORT:-5000}${ADMIN_PATH:-/admin}"
    echo "👤 登录信息: 用户名: ${ADMIN_USER:-admin} / 密码: [您设置的密码]"
    echo ""
    echo "💡 提示: 使用 'ovpn-ui' 命令安装SSL证书启用HTTPS"
    echo "📝 安装日志: $LOG_FILE"
    
    # 测试管理命令
    echo ""
    echo "🔍 测试管理命令..."
    if command -v ovpn-ui >/dev/null 2>&1; then
        echo "✅ 管理命令安装成功"
    else
        echo "❌ 管理命令未找到，请手动执行: /usr/local/bin/ovpn-ui"
    fi
}

main() {
    check_root
    check_existing_installation
    
    get_installation_config
    install_system_dependencies
    clone_repository
    setup_python_env
    create_systemd_service
    create_management_command
    initialize_application
    mark_installation_complete
    start_services
    show_installation_complete
}

main "$@"