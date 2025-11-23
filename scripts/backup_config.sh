#!/bin/bash
# 配置备份脚本

set -e

INSTALL_DIR="/opt/ovpn-ui"
BACKUP_NAME="ovpn-ui-backup-$(date +%Y%m%d_%H%M%S)"
BACKUP_FILE="/tmp/${BACKUP_NAME}.tar.gz"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

show_usage() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  backup    创建备份 (默认)"
    echo "  restore   从备份恢复"
    echo "  list      列出备份文件"
}

create_backup() {
    log "创建配置备份..."
    
    # 创建临时备份目录
    TEMP_DIR=$(mktemp -d)
    BACKUP_DIR="$TEMP_DIR/$BACKUP_NAME"
    mkdir -p "$BACKUP_DIR"
    
    # 备份配置文件
    if [ -d "$INSTALL_DIR/config" ]; then
        log "备份配置文件..."
        cp -r "$INSTALL_DIR/config" "$BACKUP_DIR/"
    fi
    
    # 备份数据文件
    if [ -d "$INSTALL_DIR/data" ]; then
        log "备份数据文件..."
        cp -r "$INSTALL_DIR/data" "$BACKUP_DIR/"
    fi
    
    # 备份SSL证书
    if [ -d "$INSTALL_DIR/ssl" ]; then
        log "备份SSL证书..."
        cp -r "$INSTALL_DIR/ssl" "$BACKUP_DIR/"
    fi
    
    # 备份安装信息
    if [ -f "$INSTALL_DIR/.installed" ]; then
        log "备份安装信息..."
        cp "$INSTALL_DIR/.installed" "$BACKUP_DIR/"
    fi
    
    # 创建压缩包
    log "创建压缩包..."
    cd "$TEMP_DIR"
    tar -czf "$BACKUP_FILE" "$BACKUP_NAME"
    
    # 清理临时文件
    rm -rf "$TEMP_DIR"
    
    log "备份完成: $BACKUP_FILE"
    echo "✅ 备份已保存到: $BACKUP_FILE"
}

restore_backup() {
    local backup_file=$1
    
    if [ -z "$backup_file" ]; then
        echo "请指定备份文件:"
        ls -1 /tmp/ovpn-ui-backup-*.tar.gz 2>/dev/null || echo "未找到备份文件"
        read -p "备份文件路径: " backup_file
    fi
    
    if [ ! -f "$backup_file" ]; then
        echo "错误: 备份文件不存在: $backup_file"
        exit 1
    fi
    
    log "从备份恢复: $backup_file"
    
    # 确认恢复
    read -p "确定要恢复备份? 这将覆盖现有配置 [y/N]: " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        log "恢复取消"
        exit 0
    fi
    
    # 创建临时目录
    TEMP_DIR=$(mktemp -d)
    
    # 解压备份文件
    log "解压备份文件..."
    tar -xzf "$backup_file" -C "$TEMP_DIR"
    
    # 查找备份目录
    BACKUP_DIR=$(find "$TEMP_DIR" -name "ovpn-ui-backup-*" -type d | head -1)
    
    if [ -z "$BACKUP_DIR" ]; then
        echo "错误: 无效的备份文件"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    # 停止服务
    log "停止服务..."
    systemctl stop ovpn-ui 2>/dev/null || true
    systemctl stop ovpn-nginx 2>/dev/null || true
    
    # 恢复文件
    log "恢复配置文件..."
    if [ -d "$BACKUP_DIR/config" ]; then
        rm -rf "$INSTALL_DIR/config"
        cp -r "$BACKUP_DIR/config" "$INSTALL_DIR/"
    fi
    
    log "恢复数据文件..."
    if [ -d "$BACKUP_DIR/data" ]; then
        rm -rf "$INSTALL_DIR/data"
        cp -r "$BACKUP_DIR/data" "$INSTALL_DIR/"
    fi
    
    log "恢复SSL证书..."
    if [ -d "$BACKUP_DIR/ssl" ]; then
        rm -rf "$INSTALL_DIR/ssl"
        cp -r "$BACKUP_DIR/ssl" "$INSTALL_DIR/"
    fi
    
    # 恢复安装信息
    if [ -f "$BACKUP_DIR/.installed" ]; then
        cp "$BACKUP_DIR/.installed" "$INSTALL_DIR/"
    fi
    
    # 设置权限
    chmod -R 755 "$INSTALL_DIR/config"
    chmod -R 755 "$INSTALL_DIR/data"
    chmod 600 "$INSTALL_DIR/ssl/key.pem" 2>/dev/null || true
    
    # 清理临时文件
    rm -rf "$TEMP_DIR"
    
    # 重启服务
    log "重启服务..."
    systemctl start ovpn-nginx
    systemctl start ovpn-ui
    
    log "恢复完成"
    echo "✅ 配置恢复成功"
}

list_backups() {
    echo "可用的备份文件:"
    echo "─────────────────────────────────────"
    ls -lh /tmp/ovpn-ui-backup-*.tar.gz 2>/dev/null | while read line; do
        echo "  $line"
    done || echo "  未找到备份文件"
}

# 主程序
case "${1:-backup}" in
    "backup")
        create_backup
        ;;
    "restore")
        restore_backup "$2"
        ;;
    "list")
        list_backups
        ;;
    *)
        show_usage
        ;;
esac