#!/bin/bash
# OpenVPN WebUI 管理脚本

set -e

INSTALL_DIR="/opt/ovpn-ui"
CONFIG_DIR="$INSTALL_DIR/config"
LOG_DIR="$INSTALL_DIR/logs"

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

check_installation() {
    if [ ! -d "$INSTALL_DIR" ] || [ ! -f "$INSTALL_DIR/.installed" ]; then
        error "OpenVPN WebUI 未安装或安装不完整"
        exit 1
    fi
}

show_status() {
    echo "🔍 服务状态:"
    echo "─────────────────────────────────────"
    
    # WebUI服务状态
    if systemctl is-active ovpn-ui >/dev/null 2>&1; then
        echo "🟢 WebUI服务: 运行中"
    else
        echo "🔴 WebUI服务: 停止"
    fi
    
    # Nginx服务状态
    if systemctl is-active ovpn-nginx >/dev/null 2>&1; then
        echo "🟢 Nginx服务: 运行中"
    else
        echo "🔴 Nginx服务: 停止"
    fi
    
    # OpenVPN服务状态
    if systemctl is-active openvpn-server@server >/dev/null 2>&1; then
        echo "🟢 OpenVPN服务: 运行中"
    else
        echo "🔴 OpenVPN服务: 停止"
    fi
    
    # 显示版本信息
    if [ -f "$INSTALL_DIR/.installed" ]; then
        echo ""
        echo "📦 安装版本:"
        source $INSTALL_DIR/.installed
        echo "   - Nginx: ${NGINX_VERSION:-未知}"
        echo "   - OpenVPN: ${OPENVPN_VERSION:-未知}"
        echo "   - SQLite: ${SQLITE_VERSION:-未知}"
    fi
}

show_config() {
    echo "📋 系统配置:"
    echo "─────────────────────────────────────"
    
    # 读取nginx配置获取端口
    if [ -f "$INSTALL_DIR/etc/nginx.conf" ]; then
        port=$(grep "listen" $INSTALL_DIR/etc/nginx.conf | head -1 | awk '{print $2}' | sed 's/;//')
        echo "🌐 访问端口: $port"
    else
        echo "🌐 访问端口: 未知"
    fi
    
    # 检查SSL证书
    if [ -f "$INSTALL_DIR/ssl/cert.pem" ] && [ -f "$INSTALL_DIR/ssl/key.pem" ]; then
        echo "🔒 SSL证书: 已配置"
        expiry=$(openssl x509 -in $INSTALL_DIR/ssl/cert.pem -noout -enddate | cut -d= -f2)
        echo "   📅 到期时间: $expiry"
    else
        echo "🔒 SSL证书: 未配置"
    fi
    
    # 显示安装时间
    if [ -f "$INSTALL_DIR/.installed" ]; then
        install_time=$(stat -c %y $INSTALL_DIR/.installed | cut -d'.' -f1)
        echo "⏰ 安装时间: $install_time"
    fi
}

restart_services() {
    log "重启服务..."
    
    systemctl restart ovpn-ui
    systemctl restart ovpn-nginx
    
    # 尝试重启OpenVPN服务
    if systemctl is-active openvpn-server@server >/dev/null 2>&1; then
        systemctl restart openvpn-server@server
    fi
    
    log "服务重启完成"
    show_status
}

stop_services() {
    log "停止服务..."
    
    systemctl stop ovpn-ui
    systemctl stop ovpn-nginx
    
    # 停止OpenVPN服务
    if systemctl is-active openvpn-server@server >/dev/null 2>&1; then
        systemctl stop openvpn-server@server
    fi
    
    log "服务已停止"
}

configure_certificate() {
    echo "🔐 证书配置:"
    echo "─────────────────────────────────────"
    
    # 检查当前证书
    if [ -f "$INSTALL_DIR/ssl/cert.pem" ]; then
        expiry=$(openssl x509 -in $INSTALL_DIR/ssl/cert.pem -noout -enddate | cut -d= -f2)
        echo "当前证书: 自签名证书 ($expiry到期)"
    else
        echo "当前证书: 未配置"
    fi
    
    echo ""
    echo "请选择证书类型:"
    echo "1) 使用自签名证书 (自动生成)"
    echo "2) 使用现有证书文件"
    echo "3) 返回主菜单"
    
    read -p "输入选择 [1-3]: " cert_choice
    
    case $cert_choice in
        1)
            generate_self_signed_cert
            ;;
        2)
            use_existing_cert
            ;;
        3)
            return
            ;;
        *)
            error "无效选择"
            return
            ;;
    esac
    
    read -p "是否立即重启服务? [Y/n]: " restart
    if [[ $restart =~ ^[Yy]$ ]] || [[ -z $restart ]]; then
        restart_services
    fi
}

generate_self_signed_cert() {
    log "生成自签名证书..."
    
    mkdir -p $INSTALL_DIR/ssl
    
    openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
        -subj "/C=US/ST=State/L=City/O=OpenVPN/CN=ovpn-ui" \
        -keyout $INSTALL_DIR/ssl/key.pem \
        -out $INSTALL_DIR/ssl/cert.pem
    
    chmod 600 $INSTALL_DIR/ssl/key.pem
    log "自签名证书生成完成"
}

use_existing_cert() {
    read -p "SSL证书文件路径: " cert_file
    read -p "SSL私钥文件路径: " key_file
    
    if [ ! -f "$cert_file" ] || [ ! -f "$key_file" ]; then
        error "证书文件不存在"
        return
    fi
    
    mkdir -p $INSTALL_DIR/ssl
    cp "$cert_file" $INSTALL_DIR/ssl/cert.pem
    cp "$key_file" $INSTALL_DIR/ssl/key.pem
    chmod 600 $INSTALL_DIR/ssl/key.pem
    
    log "证书文件配置完成"
}

change_password() {
    echo "🔐 修改管理员密码:"
    echo "─────────────────────────────────────"
    
    read -p "请输入新的管理员密码: " -s new_pass
    echo
    read -p "确认新密码: " -s confirm_pass
    echo
    
    if [ "$new_pass" != "$confirm_pass" ]; then
        error "密码不匹配"
        return
    fi
    
    if [ ${#new_pass} -lt 8 ]; then
        error "密码至少需要8位字符"
        return
    fi
    
    # 更新数据库中的密码
    source $INSTALL_DIR/venv/bin/activate
    python3 << EOF
import sqlite3
import hashlib

db_path = "/opt/ovpn-ui/data/webui.db"
password_hash = hashlib.sha256("$new_pass".encode()).hexdigest()

conn = sqlite3.connect(db_path)
cursor = conn.cursor()
cursor.execute('UPDATE admin_users SET password_hash = ? WHERE username = "admin"', (password_hash,))
conn.commit()
conn.close()
print("密码修改成功")
EOF
    
    log "管理员密码修改成功"
}

backup_config() {
    echo "📦 备份配置..."
    
    backup_dir="/tmp/ovpn-ui-backup-$(date +%Y%m%d_%H%M%S)"
    mkdir -p $backup_dir
    
    # 备份配置文件
    if [ -d "$CONFIG_DIR" ]; then
        cp -r $CONFIG_DIR $backup_dir/
    fi
    
    # 备份数据文件
    if [ -d "$INSTALL_DIR/data" ]; then
        cp -r $INSTALL_DIR/data $backup_dir/
    fi
    
    # 备份SSL证书
    if [ -d "$INSTALL_DIR/ssl" ]; then
        cp -r $INSTALL_DIR/ssl $backup_dir/
    fi
    
    # 创建压缩包
    cd /tmp
    tar -czf $backup_dir.tar.gz $(basename $backup_dir)
    rm -rf $backup_dir
    
    echo "✅ 备份完成: $backup_dir.tar.gz"
}

uninstall_system() {
    echo "⚠️  卸载系统"
    echo "─────────────────────────────────────"
    warning "此操作将完全删除 OpenVPN WebUI 系统！"
    echo ""
    read -p "确定要卸载? [y/N]: " confirm
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        log "开始卸载..."
        
        # 停止服务
        systemctl stop ovpn-ui 2>/dev/null || true
        systemctl stop ovpn-nginx 2>/dev/null || true
        
        # 禁用服务
        systemctl disable ovpn-ui 2>/dev/null || true
        systemctl disable ovpn-nginx 2>/dev/null || true
        
        # 删除服务文件
        rm -f /etc/systemd/system/ovpn-ui.service
        rm -f /etc/systemd/system/ovpn-nginx.service
        
        # 删除Nginx配置
        rm -f /etc/nginx/sites-available/ovpn-ui
        rm -f /etc/nginx/sites-enabled/ovpn-ui
        
        # 重新加载systemd和nginx
        systemctl daemon-reload
        systemctl reload nginx
        
        # 删除安装目录
        rm -rf $INSTALL_DIR
        
        log "卸载完成"
    else
        log "卸载取消"
    fi
}

show_menu() {
    echo "=== OpenVPN WebUI 管理工具 ==="
    echo ""
    echo "请选择操作:"
    echo "1) 重启服务"
    echo "2) 停止服务"  
    echo "3) 查看状态"
    echo "4) 查看配置"
    echo "5) 配置证书"
    echo "6) 修改密码"
    echo "7) 备份配置"
    echo "8) 卸载系统"
    echo "9) 退出"
    echo ""
}

handle_choice() {
    case $1 in
        1) restart_services ;;
        2) stop_services ;;
        3) show_status ;;
        4) show_config ;;
        5) configure_certificate ;;
        6) change_password ;;
        7) backup_config ;;
        8) uninstall_system ;;
        9) exit 0 ;;
        *) error "无效选择" ;;
    esac
    
    echo ""
    read -p "按回车键继续..."
}

# 主程序
main() {
    check_installation
    
    while true; do
        clear
        show_menu
        read -p "输入选择 [1-9]: " choice
        handle_choice $choice
    done
}

# 命令行参数处理
case "${1:-}" in
    "start") restart_services ;;
    "stop") stop_services ;;
    "status") show_status ;;
    "config") show_config ;;
    "cert") configure_certificate ;;
    "password") change_password ;;
    "backup") backup_config ;;
    "uninstall") uninstall_system ;;
    *) main ;;
esac