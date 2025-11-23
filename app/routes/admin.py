from flask import Blueprint, render_template, jsonify, request
from flask_login import login_required, current_user
from app.models import NormalUser, db
from datetime import datetime

admin_bp = Blueprint('admin', __name__, url_prefix='/admin')

@admin_bp.route('/users')
@login_required
def manage_users():
    """用户管理页面"""
    return render_template('admin/users.html')

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