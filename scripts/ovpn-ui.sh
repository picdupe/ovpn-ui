#!/bin/bash
# OpenVPN WebUI 管理脚本

set -e

INSTALL_DIR="/usr/local/ovpn-ui"
CONFIG_DIR="/etc/ovpn-ui"
LOG_DIR="/var/log/ovpn-ui"

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

install_nginx_silent() {
    # 静默安装Nginx（如果未安装）
    if ! command -v nginx >/dev/null 2>&1; then
        log "正在安装Nginx..."
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update >/dev/null 2>&1
            apt-get install -y nginx >/dev/null 2>&1
        elif command -v yum >/dev/null 2>&1; then
            yum install -y nginx >/dev/null 2>&1
        fi
        systemctl enable nginx >/dev/null 2>&1
        log "Nginx安装完成"
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
    if systemctl is-active nginx >/dev/null 2>&1; then
        echo "🟢 Nginx服务: 运行中"
    else
        echo "🔴 Nginx服务: 停止"
    fi
    
    # OpenVPN服务状态
    if systemctl is-active openvpn >/dev/null 2>&1; then
        echo "🟢 OpenVPN服务: 运行中"
    elif systemctl is-active openvpn-server@server >/dev/null 2>&1; then
        echo "🟢 OpenVPN服务: 运行中"
    else
        echo "🔴 OpenVPN服务: 停止"
    fi
    
    # 显示访问信息
    echo ""
    echo "🌐 访问信息:"
    if [ -f "/etc/nginx/sites-enabled/ovpn-ui" ]; then
        echo "   🔒 HTTPS: 已启用 (通过Nginx代理)"
        echo "   📍 端口: 443"
    else
        echo "   🔓 HTTP: 直接访问"
        echo "   📍 端口: 5000"
    fi
}

show_config() {
    echo "📋 系统配置:"
    echo "─────────────────────────────────────"
    
    # 检查SSL证书
    if [ -f "/etc/ssl/ovpn-ui/cert.pem" ]; then
        echo "🔒 SSL证书: 已配置"
        expiry=$(openssl x509 -in /etc/ssl/ovpn-ui/cert.pem -noout -enddate 2>/dev/null | cut -d= -f2)
        if [ $? -eq 0 ]; then
            echo "   📅 到期时间: $expiry"
        fi
    else
        echo "🔒 SSL证书: 未配置"
    fi
    
    # 显示安装时间
    if [ -f "$INSTALL_DIR/.installed" ]; then
        install_time=$(stat -c %y $INSTALL_DIR/.installed 2>/dev/null | cut -d'.' -f1 || echo "未知")
        echo "⏰ 安装时间: $install_time"
    fi
    
    # 显示安装目录
    echo "📁 安装目录: $INSTALL_DIR"
}

start_services() {
    log "启动服务..."
    
    systemctl start ovpn-ui
    
    # 如果配置了Nginx，也启动它
    if [ -f "/etc/nginx/sites-enabled/ovpn-ui" ]; then
        systemctl start nginx
    fi
    
    log "服务启动完成"
}

stop_services() {
    log "停止服务..."
    
    systemctl stop ovpn-ui
    systemctl stop nginx
    
    log "服务已停止"
}

restart_services() {
    log "重启服务..."
    
    systemctl restart ovpn-ui
    
    if [ -f "/etc/nginx/sites-enabled/ovpn-ui" ]; then
        systemctl restart nginx
    fi
    
    log "服务重启完成"
}

install_certificate() {
    echo "🔐 安装SSL证书"
    echo "─────────────────────────────────────"
    
    # 静默安装Nginx
    install_nginx_silent
    
    echo "请选择证书类型:"
    echo "1) 使用自签名证书 (自动生成)"
    echo "2) 使用现有证书文件"
    echo "3) 申请Let's Encrypt证书 (需要域名)"
    echo "4) 返回主菜单"
    
    read -p "输入选择 [1-4]: " cert_choice
    
    case $cert_choice in
        1)
            generate_self_signed_cert
            ;;
        2)
            use_existing_cert
            ;;
        3)
            install_letsencrypt_cert
            ;;
        4)
            return
            ;;
        *)
            error "无效选择"
            return
            ;;
    esac
    
    # 配置Nginx
    configure_nginx_ssl
    
    read -p "是否立即重启服务应用更改? [Y/n]: " restart
    if [[ $restart =~ ^[Yy]$ ]] || [[ -z $restart ]]; then
        restart_services
    fi
}

generate_self_signed_cert() {
    log "生成自签名证书..."
    
    mkdir -p /etc/ssl/ovpn-ui
    
    openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
        -subj "/C=CN/ST=Beijing/L=Beijing/O=OpenVPN/CN=ovpn-ui" \
        -keyout /etc/ssl/ovpn-ui/key.pem \
        -out /etc/ssl/ovpn-ui/cert.pem
    
    chmod 600 /etc/ssl/ovpn-ui/key.pem
    log "自签名证书生成完成"
}

use_existing_cert() {
    read -p "SSL证书文件路径 (.crt或.pem): " cert_file
    read -p "SSL私钥文件路径 (.key): " key_file
    
    if [ ! -f "$cert_file" ] || [ ! -f "$key_file" ]; then
        error "证书文件不存在"
        return
    fi
    
    mkdir -p /etc/ssl/ovpn-ui
    cp "$cert_file" /etc/ssl/ovpn-ui/cert.pem
    cp "$key_file" /etc/ssl/ovpn-ui/key.pem
    chmod 600 /etc/ssl/ovpn-ui/key.pem
    
    log "证书文件配置完成"
}

install_letsencrypt_cert() {
    if ! command -v certbot >/dev/null 2>&1; then
        log "安装Certbot..."
        if command -v apt-get >/dev/null 2>&1; then
            apt-get install -y certbot >/dev/null 2>&1
        elif command -v yum >/dev/null 2>&1; then
            yum install -y certbot >/dev/null 2>&1
        fi
    fi
    
    read -p "请输入域名: " domain_name
    if [ -z "$domain_name" ]; then
        error "域名不能为空"
        return
    fi
    
    log "申请Let's Encrypt证书..."
    certbot certonly --standalone -d "$domain_name" --non-interactive --agree-tos --email admin@$domain_name
    
    if [ $? -eq 0 ]; then
        mkdir -p /etc/ssl/ovpn-ui
        cp /etc/letsencrypt/live/$domain_name/fullchain.pem /etc/ssl/ovpn-ui/cert.pem
        cp /etc/letsencrypt/live/$domain_name/privkey.pem /etc/ssl/ovpn-ui/key.pem
        chmod 600 /etc/ssl/ovpn-ui/key.pem
        log "Let's Encrypt证书安装完成"
    else
        error "证书申请失败"
    fi
}

configure_nginx_ssl() {
    log "配置Nginx SSL..."
    
    # 创建Nginx配置
    cat > /etc/nginx/sites-available/ovpn-ui << 'EOF'
server {
    listen 80;
    server_name _;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl;
    server_name _;
    
    ssl_certificate /etc/ssl/ovpn-ui/cert.pem;
    ssl_certificate_key /etc/ssl/ovpn-ui/key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512;
    
    client_max_body_size 10M;
    
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    location /static {
        alias /usr/local/ovpn-ui/app/static;
        expires 30d;
    }
}
EOF

    # 启用站点
    ln -sf /etc/nginx/sites-available/ovpn-ui /etc/nginx/sites-enabled/
    
    # 测试配置
    if nginx -t >/dev/null 2>&1; then
        log "Nginx配置成功"
    else
        error "Nginx配置测试失败"
        return 1
    fi
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
import os

db_path = "/var/lib/ovpn-ui/webui.db"
password_hash = hashlib.sha256("$new_pass".encode()).hexdigest()

try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute('UPDATE admin_user SET password_hash = ? WHERE username = "admin"', (password_hash,))
    conn.commit()
    conn.close()
    print("密码修改成功")
except Exception as e:
    print(f"密码修改失败: {e}")
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
    
    # 备份SSL证书
    if [ -d "/etc/ssl/ovpn-ui" ]; then
        cp -r /etc/ssl/ovpn-ui $backup_dir/
    fi
    
    # 备份Nginx配置
    if [ -f "/etc/nginx/sites-available/ovpn-ui" ]; then
        cp /etc/nginx/sites-available/ovpn-ui $backup_dir/
    fi
    
    # 备份数据库
    if [ -f "/var/lib/ovpn-ui/webui.db" ]; then
        cp /var/lib/ovpn-ui/webui.db $backup_dir/
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
    warning "将删除以下内容："
    echo "  📁 $INSTALL_DIR - 程序文件"
    echo "  📁 $CONFIG_DIR - 配置文件"
    echo "  📁 /var/lib/ovpn-ui - 数据文件"
    echo "  📁 /var/log/ovpn-ui - 日志文件"
    echo "  📁 /etc/ssl/ovpn-ui - SSL证书"
    echo "  🔧 /usr/local/bin/ovpn-ui - 管理命令"
    echo "  🛠️  /etc/systemd/system/ovpn-ui.service - 系统服务"
    echo ""
    read -p "确定要卸载? [y/N]: " confirm
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        log "开始卸载..."
        
        # 停止服务
        log "停止服务..."
        systemctl stop ovpn-ui 2>/dev/null || true
        systemctl stop nginx 2>/dev/null || true
        
        # 禁用服务
        log "禁用服务..."
        systemctl disable ovpn-ui 2>/dev/null || true
        
        # 删除服务文件
        log "删除服务文件..."
        rm -f /etc/systemd/system/ovpn-ui.service
        
        # 删除Nginx配置
        log "删除Nginx配置..."
        rm -f /etc/nginx/sites-available/ovpn-ui
        rm -f /etc/nginx/sites-enabled/ovpn-ui
        
        # 重新加载systemd和nginx
        systemctl daemon-reload
        systemctl reload nginx 2>/dev/null || true
        
        # 删除管理命令
        log "删除管理命令..."
        rm -f /usr/local/bin/ovpn-ui
        rm -f /usr/bin/ovpn-ui
        
        # 删除所有安装的文件和目录
        log "删除程序文件..."
        rm -rf $INSTALL_DIR           # 删除克隆的代码
        
        log "删除配置文件..."
        rm -rf $CONFIG_DIR            # 删除配置文件
        
        log "删除数据文件..."
        rm -rf /var/lib/ovpn-ui       # 删除数据文件
        
        log "删除日志文件..."
        rm -rf /var/log/ovpn-ui       # 删除日志文件
        
        log "删除SSL证书..."
        rm -rf /etc/ssl/ovpn-ui       # 删除SSL证书
        
        # 删除数据库文件（如果存在）
        log "删除数据库文件..."
        rm -f /etc/ovpn-ui/webui.db 2>/dev/null || true
        rm -f /var/lib/ovpn-ui/webui.db 2>/dev/null || true
        
        log "卸载完成"
        echo ""
        echo "✅ OpenVPN WebUI 已完全卸载"
        echo "📝 所有相关文件和配置已彻底删除"
    else
        log "卸载取消"
    fi
}

show_menu() {
    echo "=== OpenVPN WebUI 管理菜单 ==="
    echo ""
    echo "请选择操作:"
    echo "1) 启动服务"
    echo "2) 停止服务"  
    echo "3) 重启服务"
    echo "4) 查看状态"
    echo "5) 查看配置"
    echo "6) 安装证书 (启用HTTPS)"
    echo "7) 修改密码"
    echo "8) 备份配置"
    echo "9) 卸载系统"
    echo "0) 退出"
    echo ""
}

handle_choice() {
    case $1 in
        1) start_services ;;
        2) stop_services ;;
        3) restart_services ;;
        4) show_status ;;
        5) show_config ;;
        6) install_certificate ;;
        7) change_password ;;
        8) backup_config ;;
        9) uninstall_system ;;
        0) exit 0 ;;
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
        read -p "输入选择 [0-9]: " choice
        handle_choice $choice
    done
}

# 命令行参数处理
case "${1:-}" in
    "start") start_services ;;
    "stop") stop_services ;;
    "restart") restart_services ;;
    "status") show_status ;;
    "config") show_config ;;
    "cert") install_certificate ;;
    "password") change_password ;;
    "backup") backup_config ;;
    "uninstall") uninstall_system ;;
    *) main ;;
esac