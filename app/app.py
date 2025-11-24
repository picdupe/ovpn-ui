from flask import Flask, render_template, request, jsonify, send_file, session, redirect, url_for
from flask_sqlalchemy import SQLAlchemy
from flask_login import LoginManager, UserMixin, login_user, logout_user, login_required, current_user
import secrets
import os
import subprocess
from datetime import datetime, timedelta
import sqlite3
import logging

app = Flask(__name__)
app.secret_key = secrets.token_hex(32)

# 更新配置路径
INSTALL_DIR = "/usr/local/ovpn-ui"
CONFIG_DIR = "/etc/ovpn-ui"
LOG_DIR = "/var/log/ovpn-ui"
DATA_DIR = "/var/lib/ovpn-ui"

# 创建必要的目录
os.makedirs(CONFIG_DIR, exist_ok=True)
os.makedirs(LOG_DIR, exist_ok=True)
os.makedirs(DATA_DIR, exist_ok=True)
os.makedirs(f"{DATA_DIR}/temp_links", exist_ok=True)

# 数据库配置
app.config['SQLALCHEMY_DATABASE_URI'] = f'sqlite:///{DATA_DIR}/webui.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(f'{LOG_DIR}/webui.log'),
        logging.StreamHandler()
    ]
)

db = SQLAlchemy(app)
login_manager = LoginManager()
login_manager.init_app(app)
login_manager.login_view = 'admin_login'

# 数据库模型
class AdminUser(UserMixin, db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(50), unique=True, nullable=False)
    password_hash = db.Column(db.String(255), nullable=False)
    email = db.Column(db.String(100))
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

class NormalUser(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(50), unique=True, nullable=False)
    email = db.Column(db.String(100), unique=True, nullable=False)
    email_verified = db.Column(db.Boolean, default=False)
    status = db.Column(db.String(20), default='pending')  # pending, approved, rejected
    ovpn_username = db.Column(db.String(50))
    max_devices = db.Column(db.Integer, default=2)
    ip_type = db.Column(db.String(10), default='dhcp')
    static_ip = db.Column(db.String(15))
    password_set = db.Column(db.Boolean, default=False)
    approved_by = db.Column(db.Integer, db.ForeignKey('admin_user.id'))
    approved_at = db.Column(db.DateTime)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

class TempDownloadLink(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('normal_user.id'))
    username = db.Column(db.String(50))
    token = db.Column(db.String(64), unique=True)
    temp_filename = db.Column(db.String(100))
    actual_filename = db.Column(db.String(100))
    download_count = db.Column(db.Integer, default=0)
    max_downloads = db.Column(db.Integer, default=1)
    expires_at = db.Column(db.DateTime)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

@login_manager.user_loader
def load_user(user_id):
    return AdminUser.query.get(int(user_id))

def init_db():
    """初始化数据库"""
    with app.app_context():
        db.create_all()
        # 创建默认管理员账户（如果不存在）
        admin_user = AdminUser.query.filter_by(username='admin').first()
        if not admin_user:
            default_admin = AdminUser(
                username='admin',
                password_hash='admin123',  # 默认密码
                email='admin@example.com'
            )
            db.session.add(default_admin)
            db.session.commit()
            app.logger.info("创建默认管理员账户: admin/admin123")
        
        app.logger.info("数据库初始化完成")

# 工具函数
def create_ovpn_user(username, password, max_devices=2):
    """创建OpenVPN用户"""
    try:
        script_path = f'{INSTALL_DIR}/scripts/create_ovpn_user.sh'
        result = subprocess.run([
            script_path, username, password, str(max_devices)
        ], capture_output=True, text=True, timeout=30)
        
        return result.returncode == 0, result.stdout, result.stderr
    except Exception as e:
        return False, '', str(e)

def change_ovpn_password(username, current_password, new_password):
    """修改OpenVPN密码"""
    try:
        script_path = f'{INSTALL_DIR}/scripts/change_ovpn_password.sh'
        result = subprocess.run([
            script_path, username, current_password, new_password
        ], capture_output=True, text=True, timeout=30)
        
        return result.returncode == 0, result.stdout, result.stderr
    except Exception as e:
        return False, '', str(e)

# ==================== 路由定义 ====================

@app.route('/')
def index():
    """根路径 - 跳转到用户注册页面"""
    return redirect(url_for('user_register'))

@app.route('/admin/login', methods=['GET', 'POST'])
def admin_login():
    """管理员登录"""
    if request.method == 'POST':
        username = request.json.get('username')
        password = request.json.get('password')
        
        # 验证管理员账户 - 使用明文密码比较
        user = AdminUser.query.filter_by(username=username).first()
        if user and user.password_hash == password:  # 直接比较明文密码
            login_user(user)
            return jsonify({'success': True})
        
        return jsonify({'success': False, 'error': '用户名或密码错误'})
    
    return render_template('admin/login.html')

@app.route('/admin/dashboard')
@login_required
def admin_dashboard():
    """管理员仪表板"""
    return render_template('admin/dashboard.html')

@app.route('/admin/users')
@login_required
def admin_users():
    """用户管理页面"""
    return render_template('admin/users.html')

@app.route('/admin/openvpn')
@login_required
def admin_openvpn():
    """OpenVPN配置页面"""
    return render_template('admin/openvpn.html')

@app.route('/admin/logout')
@login_required
def admin_logout():
    """管理员登出"""
    logout_user()
    return redirect(url_for('admin_login'))

@app.route('/admin')
@login_required
def admin_index():
    """管理员首页"""
    return redirect(url_for('admin_dashboard'))

# ==================== 用户路由 ====================

@app.route('/register', methods=['GET', 'POST'])
def user_register():
    """用户注册页面"""
    if request.method == 'POST':
        try:
            data = request.json
            username = data.get('username')
            email = data.get('email')
            
            # 检查用户是否已存在
            existing_user = NormalUser.query.filter(
                (NormalUser.username == username) | (NormalUser.email == email)
            ).first()
            
            if existing_user:
                return jsonify({
                    'success': False,
                    'error': '用户名或邮箱已存在'
                })
            
            # 创建新用户
            new_user = NormalUser(
                username=username,
                email=email,
                status='pending'
            )
            db.session.add(new_user)
            db.session.commit()
            
            app.logger.info(f"新用户注册: {username} ({email})")
            return jsonify({'success': True})
            
        except Exception as e:
            return jsonify({'success': False, 'error': str(e)})
    
    return render_template('user/register.html')

@app.route('/user/profile')
def user_profile():
    """用户个人资料页面"""
    return render_template('user/profile.html')

@app.route('/user')
def user_index():
    """用户首页"""
    return redirect(url_for('user_profile'))

# ==================== API 路由 ====================

@app.route('/api/admin/stats')
@login_required
def admin_stats():
    """获取管理员统计信息"""
    total_users = NormalUser.query.count()
    pending_users = NormalUser.query.filter_by(status='pending').count()
    approved_users = NormalUser.query.filter_by(status='approved').count()
    
    return jsonify({
        'total_users': total_users,
        'pending_users': pending_users,
        'approved_users': approved_users
    })

@app.route('/api/users/pending')
@login_required
def get_pending_users():
    """获取待审核用户列表"""
    users = NormalUser.query.filter_by(status='pending').all()
    return jsonify([{
        'id': u.id,
        'username': u.username,
        'email': u.email,
        'created_at': u.created_at.isoformat()
    } for u in users])

@app.route('/api/users/list')
@login_required
def get_users_list():
    """获取所有用户列表"""
    try:
        users = NormalUser.query.all()
        user_list = []
        
        for user in users:
            user_data = {
                'id': user.id,
                'username': user.username,
                'email': user.email,
                'status': user.status,
                'ovpn_username': user.ovpn_username,
                'max_devices': user.max_devices,
                'created_at': user.created_at.isoformat() if user.created_at else None,
                'approved_at': user.approved_at.isoformat() if user.approved_at else None
            }
            user_list.append(user_data)
        
        return jsonify({
            'success': True,
            'users': user_list
        })
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        })

@app.route('/api/users/<int:user_id>/approve', methods=['POST'])
@login_required
def approve_user(user_id):
    """批准用户申请"""
    user = NormalUser.query.get_or_404(user_id)
    data = request.json
    
    # 创建OpenVPN用户
    success, stdout, stderr = create_ovpn_user(
        data['ovpn_username'],
        data['password'],
        data.get('max_devices', 2)
    )
    
    if success:
        user.status = 'approved'
        user.ovpn_username = data['ovpn_username']
        user.max_devices = data.get('max_devices', 2)
        user.approved_by = current_user.id
        user.approved_at = datetime.utcnow()
        user.password_set = True
        db.session.commit()
        
        app.logger.info(f"用户 {user.username} 审核通过")
        return jsonify({'success': True})
    else:
        app.logger.error(f"用户审核失败: {stderr}")
        return jsonify({'success': False, 'error': stderr})

@app.route('/api/users/<int:user_id>/reject', methods=['POST'])
@login_required
def reject_user(user_id):
    """拒绝用户申请"""
    try:
        user = NormalUser.query.get_or_404(user_id)
        user.status = 'rejected'
        db.session.commit()
        
        app.logger.info(f"用户 {user.username} 申请被拒绝")
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/users/<int:user_id>/delete', methods=['POST'])
@login_required
def delete_user(user_id):
    """删除用户"""
    try:
        user = NormalUser.query.get_or_404(user_id)
        
        # 删除OpenVPN用户（如果已创建）
        if user.ovpn_username:
            try:
                # 从认证文件中删除用户
                auth_file = "/etc/ovpn-ui/openvpn/auth/users"
                if os.path.exists(auth_file):
                    with open(auth_file, 'r') as f:
                        lines = f.readlines()
                    
                    with open(auth_file, 'w') as f:
                        for line in lines:
                            if not line.startswith(f"{user.ovpn_username}:"):
                                f.write(line)
                
                # 删除CCD文件
                ccd_file = f"/etc/ovpn-ui/openvpn/ccd/{user.ovpn_username}"
                if os.path.exists(ccd_file):
                    os.remove(ccd_file)
                    
            except Exception as e:
                app.logger.warning(f"删除OpenVPN用户失败: {e}")
        
        # 删除数据库记录
        db.session.delete(user)
        db.session.commit()
        
        app.logger.info(f"用户 {user.username} 已删除")
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/users/<username>/generate_download', methods=['POST'])
@login_required
def generate_download_link(username):
    """生成配置文件下载链接"""
    user = NormalUser.query.filter_by(username=username, status='approved').first_or_404()
    
    token = secrets.token_urlsafe(16)
    expires_at = datetime.utcnow() + timedelta(minutes=5)
    temp_filename = f'{user.username}_{token}.ovpn'
    actual_filename = f'{user.username}.ovpn'
    
    # 创建符号链接
    source_file = f'{INSTALL_DIR}/config/openvpn/common-client.ovpn'
    temp_filepath = f'{DATA_DIR}/temp_links/{temp_filename}'
    
    if os.path.exists(temp_filepath):
        os.remove(temp_filepath)
    os.symlink(source_file, temp_filepath)
    
    # 保存到数据库
    link = TempDownloadLink(
        user_id=user.id,
        username=user.username,
        token=token,
        temp_filename=temp_filename,
        actual_filename=actual_filename,
        expires_at=expires_at
    )
    db.session.add(link)
    db.session.commit()
    
    app.logger.info(f"为用户 {user.username} 生成下载链接")
    
    return jsonify({
        'success': True,
        'download_url': f'/download/named/{temp_filename}',
        'expires_at': expires_at.isoformat(),
        'actual_filename': actual_filename
    })

@app.route('/api/openvpn/status')
@login_required
def openvpn_status():
    """获取OpenVPN状态"""
    try:
        # 检查OpenVPN服务状态
        result = subprocess.run(
            ['systemctl', 'is-active', 'openvpn'],
            capture_output=True, text=True
        )
        
        # 如果openvpn服务不存在，尝试openvpn-server@server
        if result.returncode != 0:
            result = subprocess.run(
                ['systemctl', 'is-active', 'openvpn-server@server'],
                capture_output=True, text=True
            )
        
        status = "active" if result.returncode == 0 else "inactive"
        
        # 获取连接客户端数量
        connected_clients = 0
        if status == "active":
            status_file = "/var/log/openvpn-status.log"
            if os.path.exists(status_file):
                with open(status_file, 'r') as f:
                    for line in f:
                        if line.startswith("CLIENT_LIST"):
                            connected_clients += 1
        
        return jsonify({
            'success': True,
            'status': status,
            'connected_clients': connected_clients,
            'server_running': status == 'active'
        })
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e),
            'status': 'error',
            'connected_clients': 0
        })

@app.route('/api/openvpn/restart', methods=['POST'])
@login_required
def restart_openvpn():
    """重启OpenVPN服务"""
    try:
        # 尝试不同的服务名称
        services = ['openvpn', 'openvpn-server@server']
        success = False
        
        for service in services:
            result = subprocess.run(
                ['systemctl', 'restart', service],
                capture_output=True, text=True
            )
            if result.returncode == 0:
                success = True
                break
        
        return jsonify({
            'success': success,
            'message': 'OpenVPN服务重启成功' if success else '重启失败，请检查服务名称'
        })
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        })

@app.route('/download/named/<temp_filename>')
def download_named_config(temp_filename):
    """下载配置文件"""
    # 验证下载权限
    link = TempDownloadLink.query.filter_by(temp_filename=temp_filename).first()
    
    if not link or link.expires_at < datetime.utcnow() or link.download_count >= link.max_downloads:
        return "下载链接无效或已过期", 410
    
    # 更新下载计数
    link.download_count += 1
    db.session.commit()
    
    file_path = f'{DATA_DIR}/temp_links/{temp_filename}'
    if not os.path.exists(file_path):
        return "文件不存在", 404
    
    app.logger.info(f"用户 {link.username} 下载配置文件")
    
    return send_file(file_path, as_attachment=True, download_name=link.actual_filename)

# ==================== 错误处理 ====================

@app.errorhandler(404)
def not_found(error):
    return jsonify({'error': '资源未找到'}), 404

@app.errorhandler(500)
def internal_error(error):
    return jsonify({'error': '服务器内部错误'}), 500

if __name__ == '__main__':
    init_db()
    app.logger.info("启动 OpenVPN WebUI 服务...")
    app.run(host='0.0.0.0', port=5000, debug=False)