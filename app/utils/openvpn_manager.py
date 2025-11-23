import subprocess
import os
import logging
from typing import Dict, List, Optional

logger = logging.getLogger(__name__)

class OpenVPNManager:
    def __init__(self, install_dir: str = "/opt/ovpn-ui"):
        self.install_dir = install_dir
        self.openvpn_bin = os.path.join(install_dir, "bin", "openvpn")
        self.config_dir = os.path.join(install_dir, "config", "openvpn")
        self.auth_dir = os.path.join(self.config_dir, "auth")
        
    def create_user(self, username: str, password: str, max_devices: int = 2) -> bool:
        """创建OpenVPN用户"""
        try:
            # 创建用户认证文件
            auth_file = os.path.join(self.auth_dir, "users")
            
            # 使用openssl生成密码哈希
            result = subprocess.run(
                ['openssl', 'passwd', '-1', password],
                capture_output=True, text=True, check=True
            )
            password_hash = result.stdout.strip()
            
            # 添加用户到认证文件
            with open(auth_file, 'a') as f:
                f.write(f"{username}:{password_hash}\n")
            
            # 创建CCD配置文件
            ccd_file = os.path.join(self.config_dir, "ccd", username)
            with open(ccd_file, 'w') as f:
                f.write(f"ifconfig-push 10.8.0.{self._get_next_ip()} 255.255.255.0\n")
                f.write(f"push \"max-routes {max_devices}\"\n")
            
            logger.info(f"OpenVPN用户 {username} 创建成功")
            return True
            
        except Exception as e:
            logger.error(f"创建OpenVPN用户失败: {e}")
            return False
    
    def change_password(self, username: str, current_password: str, new_password: str) -> bool:
        """修改用户密码"""
        try:
            auth_file = os.path.join(self.auth_dir, "users")
            
            # 读取现有用户文件
            with open(auth_file, 'r') as f:
                lines = f.readlines()
            
            # 更新密码
            updated = False
            new_lines = []
            for line in lines:
                if line.startswith(f"{username}:"):
                    # 验证当前密码
                    result = subprocess.run(
                        ['openssl', 'passwd', '-1', current_password],
                        capture_output=True, text=True, check=True
                    )
                    current_hash = result.stdout.strip()
                    
                    if current_hash in line:
                        # 生成新密码哈希
                        result = subprocess.run(
                            ['openssl', 'passwd', '-1', new_password],
                            capture_output=True, text=True, check=True
                        )
                        new_hash = result.stdout.strip()
                        new_lines.append(f"{username}:{new_hash}\n")
                        updated = True
                    else:
                        return False  # 当前密码不正确
                else:
                    new_lines.append(line)
            
            if updated:
                # 写回文件
                with open(auth_file, 'w') as f:
                    f.writelines(new_lines)
                
                logger.info(f"用户 {username} 密码修改成功")
                return True
            else:
                return False
                
        except Exception as e:
            logger.error(f"修改密码失败: {e}")
            return False
    
    def delete_user(self, username: str) -> bool:
        """删除OpenVPN用户"""
        try:
            auth_file = os.path.join(self.auth_dir, "users")
            ccd_file = os.path.join(self.config_dir, "ccd", username)
            
            # 从认证文件中删除用户
            if os.path.exists(auth_file):
                with open(auth_file, 'r') as f:
                    lines = f.readlines()
                
                with open(auth_file, 'w') as f:
                    for line in lines:
                        if not line.startswith(f"{username}:"):
                            f.write(line)
            
            # 删除CCD文件
            if os.path.exists(ccd_file):
                os.remove(ccd_file)
            
            logger.info(f"OpenVPN用户 {username} 删除成功")
            return True
            
        except Exception as e:
            logger.error(f"删除OpenVPN用户失败: {e}")
            return False
    
    def get_service_status(self) -> Dict[str, str]:
        """获取OpenVPN服务状态"""
        try:
            result = subprocess.run(
                ['systemctl', 'is-active', 'openvpn-server@server'],
                capture_output=True, text=True
            )
            
            status = "active" if result.returncode == 0 else "inactive"
            
            # 获取连接客户端数量
            connected_clients = 0
            if status == "active":
                status_file = os.path.join(self.install_dir, "logs", "openvpn-status.log")
                if os.path.exists(status_file):
                    with open(status_file, 'r') as f:
                        for line in f:
                            if line.startswith("CLIENT_LIST"):
                                connected_clients += 1
            
            return {
                "status": status,
                "connected_clients": connected_clients
            }
            
        except Exception as e:
            logger.error(f"获取服务状态失败: {e}")
            return {"status": "error", "error": str(e)}
    
    def restart_service(self) -> bool:
        """重启OpenVPN服务"""
        try:
            subprocess.run(['systemctl', 'restart', 'openvpn-server@server'], check=True)
            logger.info("OpenVPN服务重启成功")
            return True
        except subprocess.CalledProcessError as e:
            logger.error(f"重启OpenVPN服务失败: {e}")
            return False
    
    def _get_next_ip(self) -> int:
        """获取下一个可用的IP地址"""
        ccd_dir = os.path.join(self.config_dir, "ccd")
        used_ips = set()
        
        if os.path.exists(ccd_dir):
            for filename in os.listdir(ccd_dir):
                filepath = os.path.join(ccd_dir, filename)
                if os.path.isfile(filepath):
                    with open(filepath, 'r') as f:
                        for line in f:
                            if line.startswith("ifconfig-push"):
                                ip_parts = line.split()
                                if len(ip_parts) > 1:
                                    ip = ip_parts[1].split('.')[-1]
                                    used_ips.add(int(ip))
        
        # 从50开始分配IP
        for ip in range(50, 254):
            if ip not in used_ips:
                return ip
        
        return 254  # 如果所有IP都用完了，返回最后一个