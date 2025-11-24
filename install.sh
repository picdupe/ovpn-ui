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

install_system_dependencies() {
    log "安装系统依赖..."
    
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update >> $LOG_FILE 2>&1
        apt-get install -y git curl wget python3 python3-pip python3-venv \
            openvpn sqlite3 >> $LOG_FILE 2>&1
    elif command -v yum >/dev/null 2>&1; then
        yum install -y epel-release >> $LOG_FILE 2>&1
        yum install -y git curl wget python3 python3-pip openvpn sqlite >> $LOG_FILE 2>&1
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
        pip install flask flask-sqlalchemy flask-login pyopenssl requests >> $LOG_FILE 2>&1
    fi
    
    log "Python环境配置完成"
}

create_systemd_service() {
    log "创建系统服务..."
    
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
    
    # 复制管理脚本到 /usr/bin
    cp $INSTALL_DIR/scripts/ovpn-ui.sh /usr/bin/ovpn-ui
    chmod +x /usr/bin/ovpn-ui
    
    log "管理命令安装完成: ovpn-ui"
}

initialize_application() {
    log "初始化应用..."
    
    # 创建必要目录
    mkdir -p /var/log/ovpn-ui
    mkdir -p /etc/ovpn-ui
    
    # 初始化管理员账户
    if [ -f "$INSTALL_DIR/scripts/init_admin.py" ]; then
        source $INSTALL_DIR/venv/bin/activate
        python3 $INSTALL_DIR/scripts/init_admin.py >> $LOG_FILE 2>&1 || warning "管理员初始化可能失败，请手动检查"
    fi
    
    log "应用初始化完成"
}

mark_installation_complete() {
    # 标记安装完成
    touch $INSTALL_DIR/.installed
    echo "INSTALL_DATE=$(date)" >> $INSTALL_DIR/.installed
    echo "INSTALL_DIR=$INSTALL_DIR" >> $INSTALL_DIR/.installed
}

show_installation_complete() {
    echo ""
    echo "🎉 OpenVPN WebUI 安装完成！"
    echo ""
    echo "📁 安装目录: $INSTALL_DIR"
    echo "🛠️  管理命令: ovpn-ui"
    echo ""
    echo "🚀 使用方法:"
    echo "   ovpn-ui start     # 启动服务"
    echo "   ovpn-ui stop      # 停止服务"
    echo "   ovpn-ui status    # 查看状态"
    echo "   ovpn-ui           # 显示管理菜单"
    echo ""
    echo "🔐 默认访问: http://服务器IP:5000"
    echo "💡 提示: 使用 'ovpn-ui' 命令安装SSL证书启用HTTPS"
    echo ""
    echo "📝 日志文件: $LOG_FILE"
}

main() {
    check_root
    check_existing_installation
    
    install_system_dependencies
    clone_repository
    setup_python_env
    create_systemd_service
    create_management_command
    initialize_application
    mark_installation_complete
    show_installation_complete
}

main "$@"