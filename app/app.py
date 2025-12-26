from flask import Flask, render_template, request, jsonify, session, redirect, url_for
from flask_sqlalchemy import SQLAlchemy
from flask_login import LoginManager, UserMixin, login_user, logout_user, login_required, current_user
from werkzeug.security import generate_password_hash, check_password_hash
import secrets
import os
import subprocess
from datetime import datetime, timezone
import logging

# ==================== 应用初始化 ====================
app = Flask(__name__)
app.secret_key = secrets.token_hex(32)

# 目录配置
INSTALL_DIR = "/usr/local/ovpn-ui"
CONFIG_DIR = "/etc/ovpn-ui"
LOG_DIR = "/var/log/ovpn-ui"
DATA_DIR = "/var/lib/ovpn-ui"

# 创建必要目录
os.makedirs(CONFIG_DIR, exist_ok=True)
os.makedirs(LOG_DIR, exist_ok=True)
os.makedirs(DATA_DIR, exist_ok=True)
os.makedirs(f"{DATA_DIR}/temp_links", exist_ok=True)

# 数据库配置
app.config['SQLALCHEMY_DATABASE_URI'] = f'sqlite:///{DATA_DIR}/webui.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

# 日志配置
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
login_manager.login_view = 'user_login'

# ==================== 数据库模型 ====================
class AdminUser(UserMixin, db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(50), unique=True, nullable=False)
    password_hash = db.Column(db.String(255), nullable=False)
    email = db.Column(db.String(100))
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    @property
    def user_type(self):
        return "admin"

class NormalUser(UserMixin, db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(50), unique=True, nullable=False)
    email = db.Column(db.String(100), unique=True, nullable=False)
    password_hash = db.Column(db.String(255), nullable=False)
    status = db.Column(db.String(20), default='pending')
    ovpn_username = db.Column(db.String(50))
    ovpn_password = db.Column(db.String(255))
    max_devices = db.Column(db.Integer, default=2)
    password_set = db.Column(db.Boolean, default=False)
    approved_by = db.Column(db.Integer, db.ForeignKey('admin_user.id'))
    approved_at = db.Column(db.DateTime)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    @property
    def user_type(self):
        return "user"

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

# ==================== Flask-Login ====================
@login_manager.user_loader
def load_user(user_id):
    # user_id 格式：<type>-<id>，如 admin-1 或 user-5
    try:
        user_type, actual_id = user_id.split('-')
        if user_type == "admin":
            return AdminUser.query.get(int(actual_id))
        else:
            return NormalUser.query.get(int(actual_id))
    except Exception:
        return None

# ==================== 数据库初始化 ====================
def init_db():
    with app.app_context():
        db.create_all()
        # 检查是否存在管理员账户
        admin_user = AdminUser.query.first()
        if not admin_user:
            # 提示首次运行需要创建管理员账户
            app.logger.info("首次运行：请使用 init_admin.py 脚本创建管理员账户")
        else:
            app.logger.info("数据库初始化完成，找到现有管理员账户")

# ==================== OpenVPN 工具函数 ====================
from utils.openvpn_manager import OpenVPNManager

ovpn_manager = OpenVPNManager()

def create_ovpn_user(username, password, max_devices=2):
    try:
        success = ovpn_manager.create_user(username, password, max_devices)
        if success:
            return True, "用户创建成功", ""
        else:
            return False, "", "用户创建失败"
    except Exception as e:
        return False, '', str(e)

def change_ovpn_password(username, new_password):
    try:
        success, stdout, stderr = ovpn_manager.change_password_direct(username, new_password)
        return success, stdout, stderr
    except Exception as e:
        return False, '', str(e)

# ==================== 蓝图注册 ====================
from routes.admin import admin_bp
from routes.openvpn import openvpn_bp

app.register_blueprint(admin_bp)
app.register_blueprint(openvpn_bp)

# ==================== 路由 ====================
@app.route('/')
def index():
    return redirect(url_for('user_login'))

# ---------- 用户路由 ----------
@app.route('/register', methods=['GET', 'POST'])
def user_register():
    if request.method == 'POST':
        data = request.json
        username = data.get('username')
        email = data.get('email')
        password = data.get('password')
        password_confirm = data.get('password_confirm')
        if not all([username, email, password, password_confirm]):
            return jsonify({'success': False, 'error': '请填写所有必填字段'})
        if password != password_confirm:
            return jsonify({'success': False, 'error': '两次输入的密码不一致'})
        if len(password) < 6:
            return jsonify({'success': False, 'error': '密码长度至少6位'})
        existing_user = NormalUser.query.filter(
            (NormalUser.username == username) | (NormalUser.email == email)
        ).first()
        if existing_user:
            return jsonify({'success': False, 'error': '用户名或邮箱已存在'})
        new_user = NormalUser(
            username=username,
            email=email,
            password_hash=generate_password_hash(password),
            status='pending'
        )
        db.session.add(new_user)
        db.session.commit()
        app.logger.info(f"新用户注册: {username} ({email})")
        return jsonify({'success': True, 'message': '注册成功！请等待管理员审核。'})
    return render_template('user/register.html')

@app.route('/user/login', methods=['GET', 'POST'])
def user_login():
    if request.method == 'POST':
        username = request.json.get('username')
        password = request.json.get('password')
        user = NormalUser.query.filter_by(username=username).first()
        if user and check_password_hash(user.password_hash, password):
            if user.status == 'approved':
                login_user(user, remember=True)
                return jsonify({'success': True})
            else:
                return jsonify({'success': False, 'error': '账户尚未审核通过'})
        return jsonify({'success': False, 'error': '用户名或密码错误'})
    return render_template('user/login.html')

@app.route('/user/logout')
@login_required
def user_logout():
    logout_user()
    return redirect(url_for('user_login'))

@app.route('/user/profile')
@login_required
def user_profile():
    if getattr(current_user, 'user_type', '') != 'user':
        return redirect(url_for('user_login'))
    user = NormalUser.query.get(current_user.id)
    return render_template('user/profile.html', user=user)

@app.route('/user')
def user_index():
    return redirect(url_for('user_profile'))

@app.route('/user/change_ovpn_password', methods=['POST'])
@login_required
def change_user_ovpn_password():
    if getattr(current_user, 'user_type', '') != 'user':
        return jsonify({'success': False, 'error': '无权限'})
    data = request.json
    new_password = data.get('new_password')
    confirm_password = data.get('confirm_password')
    if not new_password or not confirm_password:
        return jsonify({'success': False, 'error': '请填写密码'})
    if new_password != confirm_password:
        return jsonify({'success': False, 'error': '两次输入的密码不一致'})
    if len(new_password) < 6:
        return jsonify({'success': False, 'error': '密码长度至少6位'})
    user = NormalUser.query.get(current_user.id)
    if not user.ovpn_username:
        return jsonify({'success': False, 'error': 'OpenVPN用户名未设置'})
    if user.password_set:
        success, stdout, stderr = change_ovpn_password(user.ovpn_username, new_password)
        action = "修改"
    else:
        success, stdout, stderr = create_ovpn_user(user.ovpn_username, new_password, user.max_devices)
        action = "创建"
    if success:
        user.ovpn_password = generate_password_hash(new_password)
        user.password_set = True
        db.session.commit()
        app.logger.info(f"用户 {user.username} {action}OpenVPN密码成功")
        return jsonify({'success': True, 'message': f'OpenVPN密码{action}成功'})
    else:
        app.logger.error(f"{action}OpenVPN密码失败: {stderr}")
        return jsonify({'success': False, 'error': f'OpenVPN密码{action}失败: {stderr}'})

# ==================== 错误处理 ====================
@app.errorhandler(404)
def not_found(error):
    return jsonify({'error': '资源未找到'}), 404

@app.errorhandler(500)
def internal_error(error):
    return jsonify({'error': '服务器内部错误'}), 500

# ==================== 启动 ====================
if __name__ == '__main__':
    init_db()
    app.logger.info("启动 OpenVPN WebUI 服务...")
    app.run(host='0.0.0.0', port=5000, debug=False)
