from flask import Blueprint, request, jsonify, session
import hashlib
import json
import os
from datetime import datetime

user_bp = Blueprint('user', __name__, url_prefix='/user')

# 简单用户存储文件（可换成数据库）
USER_DB = "users.json"

def load_users():
    if not os.path.exists(USER_DB):
        return {}
    with open(USER_DB, "r", encoding="utf-8") as f:
        return json.load(f)

def save_users(users):
    with open(USER_DB, "w", encoding="utf-8") as f:
        json.dump(users, f, indent=4, ensure_ascii=False)

def hash_password(password):
    return hashlib.sha256(password.encode()).hexdigest()


# --------------------------- 用户注册 ---------------------------

@user_bp.route('/register', methods=['POST'])
def register():
    data = request.json
    username = data.get("username")
    email = data.get("email")
    password = data.get("password")

    if not username or not email or not password:
        return jsonify({"success": False, "error": "缺少必要字段"})

    users = load_users()

    if username in users:
        return jsonify({"success": False, "error": "该用户名已存在"})

    users[username] = {
        "username": username,
        "email": email,
        "password": hash_password(password),
        "created_at": str(datetime.now())
    }

    save_users(users)
    return jsonify({"success": True, "message": "注册成功，等待管理员审核"})


# --------------------------- 用户登录 ---------------------------

@user_bp.route('/login', methods=['POST'])
def login():
    data = request.json
    username = data.get("username")
    password = data.get("password")

    users = load_users()

    if username not in users:
        return jsonify({"success": False, "error": "用户不存在"})

    if users[username]["password"] != hash_password(password):
        return jsonify({"success": False, "error": "密码错误"})

    # 登录成功
    session["username"] = username
    return jsonify({"success": True})


# --------------------------- 修改密码 ---------------------------

@user_bp.route('/change-password', methods=['POST'])
def change_password():
    data = request.json
    username = data.get("username")
    current_password = data.get("current_password")
    new_password = data.get("new_password")

    users = load_users()

    if username not in users:
        return jsonify({"success": False, "error": "用户不存在"})

    if users[username]["password"] != hash_password(current_password):
        return jsonify({"success": False, "error": "旧密码错误"})

    users[username]["password"] = hash_password(new_password)
    save_users(users)

    return jsonify({"success": True, "message": "密码修改成功"})
