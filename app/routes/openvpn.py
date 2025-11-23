from flask import Blueprint, jsonify, request
from flask_login import login_required
import subprocess
import os

openvpn_bp = Blueprint('openvpn', __name__, url_prefix='/api/openvpn')

@openvpn_bp.route('/status')
@login_required
def get_status():
    """获取OpenVPN状态"""
    try:
        # 检查OpenVPN服务状态
        result = subprocess.run(
            ['systemctl', 'is-active', 'openvpn-server@server'],
            capture_output=True, text=True
        )
        
        status = 'active' if result.returncode == 0 else 'inactive'
        
        # 获取连接用户数
        if status == 'active':
            status_result = subprocess.run(
                ['/opt/ovpn-ui/bin/openvpn', '--status', '/opt/ovpn-ui/logs/openvpn-status.log', '1'],
                capture_output=True, text=True
            )
            connected_clients = len([line for line in status_result.stdout.split('\n') if line.startswith('CLIENT_LIST')])
        else:
            connected_clients = 0
        
        return jsonify({
            'status': status,
            'connected_clients': connected_clients
        })
    except Exception as e:
        return jsonify({'status': 'error', 'error': str(e)})

@openvpn_bp.route('/restart', methods=['POST'])
@login_required
def restart_service():
    """重启OpenVPN服务"""
    try:
        subprocess.run(['systemctl', 'restart', 'openvpn-server@server'], check=True)
        return jsonify({'success': True})
    except subprocess.CalledProcessError as e:
        return jsonify({'success': False, 'error': str(e)})

@openvpn_bp.route('/config', methods=['GET', 'POST'])
@login_required
def manage_config():
    """管理OpenVPN配置"""
    config_file = '/opt/ovpn-ui/config/openvpn/server.conf'
    
    if request.method == 'GET':
        # 读取配置
        try:
            with open(config_file, 'r') as f:
                config_content = f.read()
            return jsonify({'config': config_content})
        except FileNotFoundError:
            return jsonify({'config': ''})
    
    elif request.method == 'POST':
        # 保存配置
        config_content = request.json.get('config', '')
        try:
            with open(config_file, 'w') as f:
                f.write(config_content)
            return jsonify({'success': True})
        except Exception as e:
            return jsonify({'success': False, 'error': str(e)})