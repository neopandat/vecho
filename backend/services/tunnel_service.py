# -*- coding: utf-8 -*-
"""
Cloudflare Tunnel 外网穿透服务
支持免账号快速临时隧道 (trycloudflare.com) 与固定 Token 隧道
"""

import os
import re
import signal
import subprocess
import threading
import time
from typing import Dict, Any, Optional

TUNNEL_LOG_PATH = "/tmp/vecho_tunnel.log"

class TunnelManager:
    _instance = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(TunnelManager, cls).__new__(cls)
            cls._instance._init_manager()
        return cls._instance

    def _init_manager(self):
        self.process: Optional[subprocess.Popen] = None
        self.public_url: Optional[str] = None
        self.is_running: bool = False
        self.error_message: Optional[str] = None
        self.monitor_thread: Optional[threading.Thread] = None

    def is_installed(self) -> bool:
        """检查系统是否安装了 cloudflared"""
        for path in ["/usr/local/bin/cloudflared", "/opt/homebrew/bin/cloudflared"]:
            if os.path.exists(path) and os.access(path, os.X_OK):
                return True
        res = subprocess.run(["which", "cloudflared"], capture_output=True, text=True)
        return res.returncode == 0

    def get_binary_path(self) -> str:
        for path in ["/usr/local/bin/cloudflared", "/opt/homebrew/bin/cloudflared"]:
            if os.path.exists(path) and os.access(path, os.X_OK):
                return path
        return "cloudflared"

    def start_tunnel(self, port: int = 31188, token: Optional[str] = None) -> Dict[str, Any]:
        """启动外网穿透隧道"""
        if self.is_running and self.process and self.process.poll() is None:
            return self.get_status()

        if not self.is_installed():
            self.error_message = "系统未安装 cloudflared"
            return {"success": False, "error": self.error_message}

        bin_path = self.get_binary_path()
        self.public_url = None
        self.error_message = None
        self.is_running = True

        if token:
            cmd = [bin_path, "tunnel", "run", "--token", token]
        else:
            cmd = [bin_path, "tunnel", "--url", f"http://localhost:{port}"]

        log_file = open(TUNNEL_LOG_PATH, "w")
        try:
            self.process = subprocess.Popen(
                cmd,
                stdout=log_file,
                stderr=subprocess.STDOUT,
                text=True,
                preexec_fn=os.setsid
            )
        except Exception as e:
            self.is_running = False
            self.error_message = str(e)
            return {"success": False, "error": self.error_message}

        # 启动线程监控日志提取 public_url
        self.monitor_thread = threading.Thread(target=self._monitor_log, daemon=True)
        self.monitor_thread.start()

        # 等待最多 8 秒获取分配到的域名
        start_wait = time.time()
        while time.time() - start_wait < 8.0:
            if self.public_url:
                break
            if self.process.poll() is not None:
                self.is_running = False
                self.error_message = "隧道进程异常退出"
                break
            time.sleep(0.5)

        return self.get_status()

    def _monitor_log(self):
        url_pattern = re.compile(r"https://[a-zA-Z0-9-]+\.trycloudflare\.com")
        for _ in range(60):
            if not self.is_running:
                break
            if os.path.exists(TUNNEL_LOG_PATH):
                try:
                    with open(TUNNEL_LOG_PATH, "r") as f:
                        content = f.read()
                        matches = url_pattern.findall(content)
                        if matches:
                            self.public_url = matches[0]
                            break
                except Exception:
                    pass
            time.sleep(0.5)

    def stop_tunnel(self) -> Dict[str, Any]:
        """停止外网穿透隧道"""
        self.is_running = False
        if self.process:
            try:
                os.killpg(os.getpgid(self.process.pid), signal.SIGTERM)
            except Exception:
                try:
                    self.process.terminate()
                except Exception:
                    pass
            self.process = None

        self.public_url = None
        return {"success": True, "message": "隧道已停止"}

    def get_status(self) -> Dict[str, Any]:
        running = bool(self.process and self.process.poll() is None)
        if not running and self.is_running:
            self.is_running = False

        return {
            "installed": self.is_installed(),
            "running": running,
            "public_url": self.public_url,
            "error": self.error_message
        }

tunnel_manager = TunnelManager()
