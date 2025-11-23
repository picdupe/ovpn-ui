from flask_sqlalchemy import SQLAlchemy
from flask_login import UserMixin
from datetime import datetime

db = SQLAlchemy()

class AdminUser(UserMixin, db.Model):
    __tablename__ = 'admin_users'
    
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(50), unique=True, nullable=False)
    password_hash = db.Column(db.String(255), nullable=False)
    email = db.Column(db.String(100))
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    
    def __repr__(self):
        return f'<AdminUser {self.username}>'

class NormalUser(db.Model):
    __tablename__ = 'normal_users'
    
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
    approved_by = db.Column(db.Integer, db.ForeignKey('admin_users.id'))
    approved_at = db.Column(db.DateTime)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    
    def __repr__(self):
        return f'<NormalUser {self.username}>'

class TempDownloadLink(db.Model):
    __tablename__ = 'temp_download_links'
    
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('normal_users.id'))
    username = db.Column(db.String(50))
    token = db.Column(db.String(64), unique=True)
    temp_filename = db.Column(db.String(100))
    actual_filename = db.Column(db.String(100))
    download_count = db.Column(db.Integer, default=0)
    max_downloads = db.Column(db.Integer, default=1)
    expires_at = db.Column(db.DateTime)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    
    def __repr__(self):
        return f'<TempDownloadLink {self.token}>'