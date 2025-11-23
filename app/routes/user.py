from flask import Blueprint, request, jsonify
import hashlib

user_bp = Blueprint('user', __name__, url_prefix='/api/user')

@user_bp.route('/register', methods=['POST'])
def register():
    """用户注册"""
    data = request.json
    username = data.get('username')
    email = data.get('email')
    password = data.get('password')
    
    # 这里应该添加用户注册逻辑
    # 包括邮箱验证等
    
    return jsonify({'success': True, 'message': '注册成功，等待管理员审核'})

@user_bp.route('/change-password', methods=['POST'])
def change_password():
    """用户修改密码"""
    data = request.json
    username = data.get('username')
    current_password = data.get('current_password')
    new_password = data.get('new_password')
    
    # 这里应该添加密码修改逻辑
    
    return jsonify({'success': True, 'message': '密码修改成功'})