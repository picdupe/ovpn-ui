import configparser
import os
import logging
from typing import Dict, Any

logger = logging.getLogger(__name__)

class ConfigParser:
    def __init__(self, config_dir: str = "/opt/ovpn-ui/config"):
        self.config_dir = config_dir
        self.openvpn_config = os.path.join(config_dir, "openvpn", "server.conf")
    
    def read_openvpn_config(self) -> Dict[str, Any]:
        """读取OpenVPN配置文件"""
        config = {}
        
        try:
            if not os.path.exists(self.openvpn_config):
                logger.warning(f"OpenVPN配置文件不存在: {self.openvpn_config}")
                return config
            
            with open(self.openvpn_config, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith('#'):
                        parts = line.split()
                        if len(parts) >= 2:
                            key = parts[0]
                            value = ' '.join(parts[1:])
                            config[key] = value
            
            logger.info("OpenVPN配置文件读取成功")
            return config
            
        except Exception as e:
            logger.error(f"读取OpenVPN配置文件失败: {e}")
            return {}
    
    def write_openvpn_config(self, config: Dict[str, Any]) -> bool:
        """写入OpenVPN配置文件"""
        try:
            # 确保目录存在
            os.makedirs(os.path.dirname(self.openvpn_config), exist_ok=True)
            
            with open(self.openvpn_config, 'w') as f:
                f.write("# OpenVPN服务器配置 - 由WebUI管理\n")
                f.write("# 不要手动修改此文件\n\n")
                
                for key, value in config.items():
                    f.write(f"{key} {value}\n")
            
            logger.info("OpenVPN配置文件写入成功")
            return True
            
        except Exception as e:
            logger.error(f"写入OpenVPN配置文件失败: {e}")
            return False
    
    def get_default_openvpn_config(self) -> Dict[str, Any]:
        """获取默认的OpenVPN配置"""
        return {
            "port": "1194",
            "proto": "udp",
            "dev": "tun",
            "ca": "/opt/ovpn-ui/config/openvpn/ca.crt",
            "cert": "/opt/ovpn-ui/config/openvpn/server.crt",
            "key": "/opt/ovpn-ui/config/openvpn/server.key",
            "dh": "/opt/ovpn-ui/config/openvpn/dh.pem",
            "server": "10.8.0.0 255.255.255.0",
            "ifconfig-pool-persist": "ipp.txt",
            "push": "redirect-gateway def1 bypass-dhcp",
            "push": "dhcp-option DNS 8.8.8.8",
            "push": "dhcp-option DNS 8.8.4.4",
            "keepalive": "10 120",
            "cipher": "AES-256-CBC",
            "user": "nobody",
            "group": "nogroup",
            "persist-key": "",
            "persist-tun": "",
            "status": "/opt/ovpn-ui/logs/openvpn-status.log",
            "verb": "3",
            "explicit-exit-notify": "1",
            "client-config-dir": "/opt/ovpn-ui/config/openvpn/ccd",
            "script-security": "2",
            "auth-user-pass-verify": "/opt/ovpn-ui/config/openvpn/auth/check_user.sh via-file",
            "username-as-common-name": "",
            "verify-client-cert": "none"
        }