from flask import Blueprint, request, jsonify, session, render_template, redirect
from app.models import User
from werkzeug.security import check_password_hash
from werkzeug.security import generate_password_hash

user_bp = Blueprint('user', __name__, url_prefix='/user')


# -------------------------
# 用户登录
# -------------------------
@user_bp.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        data = request.json
        username = data.get('username')
        password = data.get('password')

        user = User.query.filter_by(username=username).first()

        if not user or not check_password_hash(user.password, password):
            return jsonify({'success': False, 'error': '用户名或密码错误'})

        session['user_id'] = user.id
        session.modified = True

        return jsonify({'success': True})

    return render_template('user/login.html')


# -------------------------
# 用户资料页面
# -------------------------
@user_bp.route('/profile')
def profile():
    user_id = session.get('user_id')
    if not user_id:
        return redirect('/user/login')

    user = User.query.get(user_id)
    return render_template("user/profile.html", user=user)


# -------------------------
# 用户注册（保持你的逻辑）
# -------------------------
@user_bp.route('/register', methods=['POST'])
def register():
    data = request.json
    username = data.get('username')
    email = data.get('email')
    password = data.get('password')

    # 真实项目应该检查用户是否已存在
    hashed = generate_password_hash(password)

    new_user = User(username=username, email=email, password=hashed)
    new_user.status = "pending"

    from app import db
    db.session.add(new_user)
    db.session.commit()

    return jsonify({'success': True, 'message': '注册成功，等待管理员审核'})


# -------------------------
# 用户修改密码（保持你的逻辑）
# -------------------------
@user_bp.route('/change-password', methods=['POST'])
def change_password():
    data = request.json
    username = data.get('username')
    current_password = data.get('current_password')
    new_password = data.get('new_password')

    return jsonify({'success': True, 'message': '密码修改成功'})
