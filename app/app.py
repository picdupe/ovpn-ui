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

# 路由
@app.route('/')
def index():
    return redirect(url_for('admin_login'))

@app.route('/admin/login', methods=['GET', 'POST'])
def admin_login():
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
    return render_template('admin/dashboard.html')

@app.route('/admin/logout')
@login_required
def admin_logout():
    logout_user()
    return redirect(url_for('admin_login'))

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
    users = NormalUser.query.filter_by(status='pending').all()
    return jsonify([{
        'id': u.id,
        'username': u.username,
        'email': u.email,
        'created_at': u.created_at.isoformat()
    } for u in users])

@app.route('/api/users/<int:user_id>/approve', methods=['POST'])
@login_required
def approve_user(user_id):
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

@app.route('/api/users/<username>/generate_download', methods=['POST'])
@login_required
def generate_download_link(username):
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

@app.route('/download/named/<temp_filename>')
def download_named_config(temp_filename):
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

if __name__ == '__main__':
    init_db()
    app.run(host='0.0.0.0', port=5000, debug=False)