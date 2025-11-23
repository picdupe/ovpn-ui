#!/bin/bash
# OpenVPN WebUI 安装脚本 - 自动检测最新版本

set -e

# 配置变量
INSTALL_DIR="/opt/ovpn-ui"
REPO_URL="https://github.com/picdupe/ovpn-ui.git"
LOG_FILE="/tmp/ovpn-ui-install.log"

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 版本检测变量
NGINX_LATEST=""
OPENVPN_LATEST=""
SQLITE_LATEST=""

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

get_latest_nginx_version() {
    log "检测最新 Nginx 版本..."
    NGINX_LATEST=$(curl -s https://nginx.org/en/download.html | grep -oP 'nginx-\K[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [ -z "$NGINX_LATEST" ]; then
        NGINX_LATEST="1.24.0"  # 默认版本
        warning "无法检测Nginx最新版本，使用默认版本: $NGINX_LATEST"
    else
        log "检测到 Nginx 最新版本: $NGINX_LATEST"
    fi
}

get_latest_openvpn_version() {
    log "正在检测最新 OpenVPN 版本..."
    
    # 方法一：从发布页面解析版本号
    OPENVPN_LATEST=$(curl -s "https://swupdate.openvpn.org/community/releases/" | grep -oP 'openvpn-\K[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -1)
    
    # 如果方法一失败，则使用方法二：设置一个已知的稳定版本
    if [ -z "$OPENVPN_LATEST" ]; then
        OPENVPN_LATEST="2.6.16"  # 一个已知的稳定版本[citation:2][citation:10]
        warning "无法自动检测OpenVPN最新版本，将使用预设稳定版本: $OPENVPN_LATEST"
    else
        log "检测到 OpenVPN 最新版本: $OPENVPN_LATEST"
    fi
}

get_latest_sqlite_version() {
    log "检测最新 SQLite 版本..."
    SQLITE_LATEST=$(curl -s https://www.sqlite.org/download.html | grep -oP 'sqlite-autoconf-\K[0-9]+' | head -1)
    if [ -z "$SQLITE_LATEST" ]; then
        SQLITE_LATEST="3440200"  # 默认版本
        warning "无法检测SQLite最新版本，使用默认版本: $SQLITE_LATEST"
    else
        log "检测到 SQLite 版本: $SQLITE_LATEST"
    fi
}

download_with_fallback() {
    local url="$1"
    local output="$2"
    local filename=$(basename "$output")
    
    log "下载 $filename..."
    
    # 主要下载方式
    if wget --timeout=30 -O "$output" "$url" >> $LOG_FILE 2>&1; then
        log "✅ $filename 下载成功"
        return 0
    fi
    
    warning "主要下载源失败，尝试备用源..."
    
    # 备用下载方式
    if curl -fL --connect-timeout 20 -o "$output" "$url" >> $LOG_FILE 2>&1; then
        log "✅ $filename 下载成功 (备用源)"
        return 0
    fi
    
    error "下载 $filename 失败"
    return 1
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
        echo "🔍 检测到系统未安装 OpenVPN WebUI"
        read -p "是否安装 OpenVPN WebUI? [Y/n]: " install
        if [[ $install =~ ^[Nn]$ ]]; then
            echo "安装取消"
            exit 0
        fi
    fi
}

get_installation_config() {
    echo ""
    echo "📝 请输入安装配置:"
    echo "─────────────────────────────────────"
    
    read -p "Web访问端口 [8443]: " web_port
    WEB_PORT=${web_port:-8443}
    
    read -p "管理员用户名 [admin]: " admin_user
    ADMIN_USER=${admin_user:-admin}
    
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
    ADMIN_PATH=${admin_path:-/admin}
}

install_system_dependencies() {
    log "安装编译依赖..."
    
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update >> $LOG_FILE 2>&1
        apt-get install -y build-essential git curl wget python3 python3-pip python3-venv \
            libpcre3-dev libssl-dev zlib1g-dev libsqlite3-dev >> $LOG_FILE 2>&1
    elif command -v yum >/dev/null 2>&1; then
        yum install -y epel-release >> $LOG_FILE 2>&1
        yum install -y gcc gcc-c++ make git curl wget python3 python3-pip \
            pcre-devel openssl-devel zlib-devel sqlite-devel >> $LOG_FILE 2>&1
    else
        error "不支持的包管理器"
    fi
}

create_directories() {
    log "创建目录结构..."
    
    mkdir -p $INSTALL_DIR
    mkdir -p $INSTALL_DIR/bin
    mkdir -p $INSTALL_DIR/src
    mkdir -p $INSTALL_DIR/etc
    mkdir -p $INSTALL_DIR/var/log
    mkdir -p $INSTALL_DIR/var/run
    mkdir -p $INSTALL_DIR/ssl
    mkdir -p $INSTALL_DIR/scripts
}

download_webui() {
    log "下载WebUI代码..."
    
    # 清理目录
    rm -rf "$INSTALL_DIR/app"
    
    # 直接执行克隆，依赖git命令的返回码
    if git clone "$REPO_URL" "$INSTALL_DIR/app" >> "$LOG_FILE" 2>&1; then
        log "WebUI代码下载成功"
        return 0
    else
        error "WebUI代码下载失败"
        return 1
    fi
}

compile_nginx() {
    log "编译安装 Nginx $NGINX_LATEST..."
    
    cd $INSTALL_DIR/src
    
    local nginx_dir="nginx-$NGINX_LATEST"
    local nginx_package="$nginx_dir.tar.gz"
    
    # 下载nginx源码
    if [ ! -f "$nginx_package" ]; then
        local nginx_url="https://nginx.org/download/$nginx_package"
        download_with_fallback "$nginx_url" "$nginx_package"
        tar -xzf "$nginx_package" >> $LOG_FILE 2>&1
    fi
    
    cd "$nginx_dir"
    
    # 编译nginx
    ./configure \
        --prefix=$INSTALL_DIR \
        --sbin-path=$INSTALL_DIR/bin/nginx \
        --conf-path=$INSTALL_DIR/etc/nginx.conf \
        --pid-path=$INSTALL_DIR/var/run/nginx.pid \
        --lock-path=$INSTALL_DIR/var/run/nginx.lock \
        --error-log-path=$INSTALL_DIR/var/log/nginx.error.log \
        --http-log-path=$INSTALL_DIR/var/log/nginx.access.log \
        --with-http_ssl_module \
        --with-http_v2_module \
        --with-threads \
        --without-http_rewrite_module \
        --without-http_gzip_module >> $LOG_FILE 2>&1
    
    make -j$(nproc) >> $LOG_FILE 2>&1
    make install >> $LOG_FILE 2>&1
    
    log "Nginx $NGINX_LATEST 安装完成"
}

compile_openvpn() {
    log "编译安装 OpenVPN $OPENVPN_LATEST..."
    
    cd $INSTALL_DIR/src
    
    local openvpn_dir="openvpn-$OPENVPN_LATEST"
    local openvpn_package="$openvpn_dir.tar.gz"
    local openvpn_url="https://swupdate.openvpn.org/community/releases/$openvpn_package"
    
    # 下载OpenVPN源码
    if [ ! -f "$openvpn_package" ]; then
        download_with_fallback "$openvpn_url" "$openvpn_package"
        tar -xzf "$openvpn_package" >> $LOG_FILE 2>&1
    fi
    
    cd "$openvpn_dir"
    
    # 编译OpenVPN
    ./configure \
        --prefix=$INSTALL_DIR \
        --sbindir=$INSTALL_DIR/bin \
        --sysconfdir=$INSTALL_DIR/etc/openvpn \
        --disable-plugin-auth-pam \
        --disable-dependency-tracking >> $LOG_FILE 2>&1
    
    make -j$(nproc) >> $LOG_FILE 2>&1
    make install >> $LOG_FILE 2>&1
    
    log "OpenVPN $OPENVPN_LATEST 安装完成"
}

compile_sqlite() {
    log "编译安装 SQLite $SQLITE_LATEST..."
    
    cd $INSTALL_DIR/src
    
    local sqlite_dir="sqlite-autoconf-$SQLITE_LATEST"
    local sqlite_package="$sqlite_dir.tar.gz"
    local sqlite_url="https://www.sqlite.org/2024/$sqlite_package"
    
    # 下载SQLite源码
    if [ ! -f "$sqlite_package" ]; then
        download_with_fallback "$sqlite_url" "$sqlite_package"
        tar -xzf "$sqlite_package" >> $LOG_FILE 2>&1
    fi
    
    cd "$sqlite_dir"
    
    # 编译SQLite
    ./configure --prefix=$INSTALL_DIR >> $LOG_FILE 2>&1
    make -j$(nproc) >> $LOG_FILE 2>&1
    make install >> $LOG_FILE 2>&1
    
    log "SQLite $SQLITE_LATEST 安装完成"
}

setup_python_env() {
    log "配置Python环境..."
    
    # 使用系统Python创建虚拟环境
    python3 -m venv $INSTALL_DIR/venv >> $LOG_FILE 2>&1
    source $INSTALL_DIR/venv/bin/activate
    
    pip install --upgrade pip >> $LOG_FILE 2>&1
    
    if [ -f "$INSTALL_DIR/app/requirements.txt" ]; then
        pip install -r $INSTALL_DIR/app/requirements.txt >> $LOG_FILE 2>&1
    else
        # 安装基础依赖
        pip install flask flask-sqlalchemy flask-login pyopenssl requests gunicorn >> $LOG_FILE 2>&1
    fi
}

generate_ssl_cert() {
    log "生成SSL证书..."
    
    # 生成自签名证书
    $INSTALL_DIR/bin/openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
        -subj "/C=US/ST=State/L=City/O=OpenVPN/CN=ovpn-ui" \
        -keyout $INSTALL_DIR/ssl/key.pem \
        -out $INSTALL_DIR/ssl/cert.pem >> $LOG_FILE 2>&1
    
    chmod 600 $INSTALL_DIR/ssl/key.pem
}

setup_nginx_config() {
    log "配置Nginx..."
    
    # 创建nginx配置目录
    mkdir -p $INSTALL_DIR/etc/nginx
    
    cat > $INSTALL_DIR/etc/nginx.conf << EOF
worker_processes 1;
error_log $INSTALL_DIR/var/log/nginx.error.log;
pid $INSTALL_DIR/var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile      on;
    keepalive_timeout 65;
    
    server {
        listen $WEB_PORT ssl;
        server_name _;
        
        ssl_certificate $INSTALL_DIR/ssl/cert.pem;
        ssl_certificate_key $INSTALL_DIR/ssl/key.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512;
        
        location /$ADMIN_PATH {
            proxy_pass http://127.0.0.1:5000;
            proxy_set_header Host \\$host;
            proxy_set_header X-Real-IP \\$remote_addr;
            proxy_set_header X-Forwarded-For \\$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \\$scheme;
        }
        
        location / {
            return 301 /$ADMIN_PATH;
        }
    }
}
EOF

    # 创建mime.types文件
    cat > $INSTALL_DIR/etc/mime.types << 'EOF'
types {
    text/html                             html htm shtml;
    text/css                              css;
    text/xml                              xml;
    image/gif                             gif;
    image/jpeg                            jpeg jpg;
    application/javascript                js;
    text/plain                            txt;
    text/x-component                      htc;
}
EOF
}

create_systemd_service() {
    log "创建系统服务..."
    
    cat > /etc/systemd/system/ovpn-ui.service << EOF
[Unit]
Description=OpenVPN WebUI
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR/app
Environment=PATH=$INSTALL_DIR/bin:$INSTALL_DIR/venv/bin
ExecStart=$INSTALL_DIR/venv/bin/gunicorn --bind 127.0.0.1:5000 --workers 3 app:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/ovpn-nginx.service << EOF
[Unit]
Description=OpenVPN Nginx
After=network.target

[Service]
Type=forking
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/bin/nginx -c $INSTALL_DIR/etc/nginx.conf
ExecReload=$INSTALL_DIR/bin/nginx -s reload
ExecStop=$INSTALL_DIR/bin/nginx -s quit
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload >> $LOG_FILE 2>&1
    systemctl enable ovpn-ui.service ovpn-nginx.service >> $LOG_FILE 2>&1
}

create_admin_user() {
    log "创建管理员账户..."
    
    # 创建初始化脚本
    cat > $INSTALL_DIR/scripts/init_admin.py << 'EOF'
#!/usr/bin/env python3
import sqlite3
import hashlib
import os
import sys

def init_admin(username, password):
    db_path = "/opt/ovpn-ui/data/webui.db"
    os.makedirs(os.path.dirname(db_path), exist_ok=True)
    
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS admin_users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username VARCHAR(50) UNIQUE NOT NULL,
            password_hash VARCHAR(255) NOT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    
    password_hash = hashlib.sha256(password.encode()).hexdigest()
    
    cursor.execute('''
        INSERT OR REPLACE INTO admin_users (username, password_hash)
        VALUES (?, ?)
    ''', (username, password_hash))
    
    conn.commit()
    conn.close()
    print(f"管理员账户 '{username}' 初始化完成")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("用法: python3 init_admin.py <用户名> <密码>")
        sys.exit(1)
    
    init_admin(sys.argv[1], sys.argv[2])
EOF

    # 执行初始化
    source $INSTALL_DIR/venv/bin/activate
    python3 $INSTALL_DIR/scripts/init_admin.py "$ADMIN_USER" "$admin_pass" >> $LOG_FILE 2>&1
}

start_services() {
    log "启动服务..."
    
    systemctl start ovpn-nginx >> $LOG_FILE 2>&1
    systemctl start ovpn-ui >> $LOG_FILE 2>&1
    
    # 标记安装完成
    touch $INSTALL_DIR/.installed
    date > $INSTALL_DIR/.installed
    
    # 保存安装版本信息
    echo "NGINX_VERSION=$NGINX_LATEST" >> $INSTALL_DIR/.installed
    echo "OPENVPN_VERSION=$OPENVPN_LATEST" >> $INSTALL_DIR/.installed
    echo "SQLITE_VERSION=$SQLITE_LATEST" >> $INSTALL_DIR/.installed
}

show_installation_complete() {
    echo ""
    echo "✅ 安装完成！"
    echo ""
    echo "🌐 访问地址: https://你的服务器IP:$WEB_PORT/$ADMIN_PATH"
    echo "👤 管理员: $ADMIN_USER"
    echo "📦 安装版本:"
    echo "   - Nginx: $NGINX_LATEST"
    echo "   - OpenVPN: $OPENVPN_LATEST" 
    echo "   - SQLite: $SQLITE_LATEST"
    echo ""
    echo "💡 提示: 使用HTTPS安全连接访问"
    echo ""
    echo "🛠️  管理命令: $INSTALL_DIR/app/ovpn-ui.sh"
}

main() {
    check_root
    check_existing_installation
    get_installation_config
    
    # 检测最新版本
    get_latest_nginx_version
    get_latest_openvpn_version
    get_latest_sqlite_version
    
    install_system_dependencies
    create_directories
    download_webui
    compile_nginx
    compile_openvpn
    compile_sqlite
    setup_python_env
    generate_ssl_cert
    setup_nginx_config
    create_systemd_service
    create_admin_user
    start_services
    show_installation_complete
}

main "$@"