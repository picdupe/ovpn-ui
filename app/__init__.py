from flask import Flask

def create_app():
    app = Flask(
        __name__,
        static_folder="static",       # 指向 app/static
        template_folder="templates"   # 指向 app/templates
    )

    # 必须设置 SECRET_KEY 才能使用 session
    app.secret_key = "your_random_secret_123456"

    # 注册蓝图
    from app.routes.user import user_bp
    app.register_blueprint(user_bp)

    # 你可以在这里注册其他蓝图
    # from app.routes.admin import admin_bp
    # app.register_blueprint(admin_bp)

    return app
