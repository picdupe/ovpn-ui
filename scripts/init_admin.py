#!/usr/bin/env python3
"""
OpenVPN WebUI 管理员初始化脚本
"""

import sqlite3
import os
import sys
import secrets
from werkzeug.security import generate_password_hash

# 配置路径
INSTALL_DIR = "/usr/local/ovpn-ui"
CONFIG_DIR = "/etc/ovpn-ui"
DATA_DIR = "/var/lib/ovpn-ui"
LOG_DIR = "/var/log/ovpn-ui"

def create_directories():
    """创建必要的目录"""
    directories = [CONFIG_DIR, DATA_DIR, LOG_DIR, f"{DATA_DIR}/temp_links"]
    
    for directory in directories:
        os.makedirs(directory, exist_ok=True)
        print(f"✅ 创建目录: {directory}")

def init_database():
    """初始化数据库"""
    db_path = f"{DATA_DIR}/webui.db"
    
    # 创建数据库连接
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # 创建管理员用户表
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS admin_user (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username VARCHAR(50) UNIQUE NOT NULL,
            password_hash VARCHAR(255) NOT NULL,
            email VARCHAR(100),
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    
    # 创建普通用户表
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS normal_user (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username VARCHAR(50) UNIQUE NOT NULL,
            email VARCHAR(100) UNIQUE NOT NULL,
            email_verified BOOLEAN DEFAULT 0,
            status VARCHAR(20) DEFAULT 'pending',
            ovpn_username VARCHAR(50),
            max_devices INTEGER DEFAULT 2,
            ip_type VARCHAR(10) DEFAULT 'dhcp',
            static_ip VARCHAR(15),
            password_set BOOLEAN DEFAULT 0,
            approved_by INTEGER,
            approved_at DATETIME,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (approved_by) REFERENCES admin_user (id)
        )
    ''')
    
    # 创建下载链接表
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS temp_download_link (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER,
            username VARCHAR(50),
            token VARCHAR(64) UNIQUE,
            temp_filename VARCHAR(100),
            actual_filename VARCHAR(100),
            download_count INTEGER DEFAULT 0,
            max_downloads INTEGER DEFAULT 1,
            expires_at DATETIME,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES normal_user (id)
        )
    ''')
    
    print("✅ 数据库表创建完成")
    
    # 检查是否已存在管理员用户
    cursor.execute("SELECT COUNT(*) FROM admin_user")
    count = cursor.fetchone()[0]
    
    if count == 0:
        # 创建默认管理员账户
        default_username = "admin"
        default_password = secrets.token_urlsafe(12)  # 生成随机密码
        password_hash = generate_password_hash(default_password)
        
        cursor.execute(
            "INSERT INTO admin_user (username, password_hash, email) VALUES (?, ?, ?)",
            (default_username, password_hash, "admin@localhost")
        )
        
        conn.commit()
        print("✅ 默认管理员账户创建完成")
        print(f"👤 用户名: {default_username}")
        print(f"🔑 密码: {default_password}")
        print("⚠️  请及时登录系统修改默认密码！")
    else:
        print(f"✅ 系统中已存在 {count} 个管理员账户")
    
    conn.close()

def create_default_config():
    """创建默认配置文件"""
    config_path = f"{CONFIG_DIR}/webui.json"
    
    if not os.path.exists(config_path):
        # 从模板复制或创建默认配置
        template_path = f"{INSTALL_DIR}/config/webui.json.template"
        
        if os.path.exists(template_path):
            # 复制模板文件
            import shutil
            shutil.copy2(template_path, config_path)
            print(f"✅ 配置文件已从模板创建: {config_path}")
        else:
            # 创建默认配置
            default_config = {
                "webui": {
                    "host": "0.0.0.0",
                    "port": 5000,
                    "debug": False,
                    "secret_key": secrets.token_hex(32),
                    "session_timeout": 3600
                },
                "database": {
                    "path": f"{DATA_DIR}/webui.db"
                },
                "openvpn": {
                    "config_dir": f"{INSTALL_DIR}/config/openvpn",
                    "easy_rsa_dir": f"{INSTALL_DIR}/easy-rsa",
                    "log_file": "/var/log/openvpn-status.log"
                },
                "security": {
                    "password_min_length": 8,
                    "max_login_attempts": 5,
                    "lockout_time": 900
                },
                "paths": {
                    "install_dir": INSTALL_DIR,
                    "config_dir": CONFIG_DIR,
                    "data_dir": DATA_DIR,
                    "log_dir": LOG_DIR,
                    "temp_dir": f"{DATA_DIR}/temp_links"
                }
            }
            
            import json
            with open(config_path, 'w') as f:
                json.dump(default_config, f, indent=4)
            
            print(f"✅ 默认配置文件已创建: {config_path}")
    else:
        print(f"✅ 配置文件已存在: {config_path}")

def set_permissions():
    """设置文件权限"""
    try:
        # 设置数据目录权限
        os.chmod(DATA_DIR, 0o755)
        os.chmod(f"{DATA_DIR}/webui.db", 0o644)
        
        # 设置配置目录权限
        os.chmod(CONFIG_DIR, 0o755)
        os.chmod(f"{CONFIG_DIR}/webui.json", 0o644)
        
        print("✅ 文件权限设置完成")
    except Exception as e:
        print(f"⚠️  权限设置警告: {e}")

def main():
    """主函数"""
    print("🚀 OpenVPN WebUI 初始化脚本")
    print("=" * 50)
    
    try:
        # 创建目录
        create_directories()
        
        # 初始化数据库
        init_database()
        
        # 创建配置文件
        create_default_config()
        
        # 设置权限
        set_permissions()
        
        print("=" * 50)
        print("🎉 初始化完成！")
        print("")
        print("🌐 访问地址: http://服务器IP:5000")
        print("💡 使用 'ovpn-ui' 命令管理服务")
        
    except Exception as e:
        print(f"❌ 初始化失败: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()