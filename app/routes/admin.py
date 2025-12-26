from flask import Blueprint, render_template, jsonify, request
from flask_login import login_required, current_user
from app.models import NormalUser, db, AdminUser
from werkzeug.security import check_password_hash
from datetime import datetime

admin_bp = Blueprint('admin', __name__, url_prefix='/admin')

# 管理员登录路由
@admin_bp.route('/login', methods=['GET', 'POST'])
def admin_login():
    if request.method == 'POST':
        username = request.json.get('username')
        password = request.json.get('password')
        user = AdminUser.query.filter_by(username=username).first()
        if user and check_password_hash(user.password_hash, password):
            login_user(user, remember=True)
            # 设置用户ID格式为 admin-<id>
            from flask_login import login_user
            login_user(user)
            session['_user_id'] = f"admin-{user.id}"
            return jsonify({'success': True})
        return jsonify({'success': False, 'error': '用户名或密码错误'})
    return render_template('admin/login.html')

@admin_bp.route('/logout')
@login_required
def admin_logout():
    logout_user()
    return redirect(url_for('admin_login'))

@admin_bp.route('/dashboard')
@login_required
def admin_dashboard():
    if getattr(current_user, 'user_type', '') != 'admin':
        return redirect(url_for('user_login'))
    return render_template('admin/dashboard.html')

@admin_bp.route('/users')
@login_required
def admin_users():
    if getattr(current_user, 'user_type', '') != 'admin':
        return redirect(url_for('user_login'))
    return render_template('admin/users.html')

@admin_bp.route('/openvpn')
@login_required
def admin_openvpn():
    if getattr(current_user, 'user_type', '') != 'admin':
        return redirect(url_for('user_login'))
    return render_template('admin/openvpn.html')

@admin_bp.route('/', defaults={'path': ''})
@admin_bp.route('/<path:path>')
@login_required
def admin_index(path):
    if getattr(current_user, 'user_type', '') != 'admin':
        return redirect(url_for('user_login'))
    # 根据不同路径返回相应的模板
    if path == '' or path == 'dashboard':
        return render_template('admin/dashboard.html')
    elif path == 'users':
        return render_template('admin/users.html')
    elif path == 'openvpn':
        return render_template('admin/openvpn.html')
    else:
        return render_template('admin/dashboard.html')

# 管理员API路由
@admin_bp.route('/api/users')
@login_required
def get_users():
    """获取用户列表"""
    users = NormalUser.query.all()
    return jsonify([{
        'id': u.id,
        'username': u.username,
        'email': u.email,
        'status': u.status,
        'ovpn_username': u.ovpn_username,
        'max_devices': u.max_devices,
        'ip_type': u.ip_type,
        'static_ip': u.static_ip,
        'created_at': u.created_at.isoformat(),
        'approved_at': u.approved_at.isoformat() if u.approved_at else None
    } for u in users])

@admin_bp.route('/api/users/<int:user_id>', methods=['DELETE'])
@login_required
def delete_user(user_id):
    """删除用户"""
    user = NormalUser.query.get_or_404(user_id)
    db.session.delete(user)
    db.session.commit()
    return jsonify({'success': True})

@admin_bp.route('/api/users/<int:user_id>/suspend', methods=['POST'])
@login_required
def suspend_user(user_id):
    """暂停用户"""
    user = NormalUser.query.get_or_404(user_id)
    user.status = 'suspended'
    db.session.commit()
    return jsonify({'success': True})

@admin_bp.route('/api/users/<int:user_id>/activate', methods=['POST'])
@login_required
def activate_user(user_id):
    """激活用户"""
    user = NormalUser.query.get_or_404(user_id)
    user.status = 'approved'
    db.session.commit()
    return jsonify({'success': True})