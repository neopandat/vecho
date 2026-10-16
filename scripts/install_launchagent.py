#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
智能控制台 Mac 开机自启服务安装/卸载脚本 (LaunchAgent)
"""

import os
import sys
import subprocess

LABEL = "com.pandac.vecho"
PLIST_PATH = os.path.expanduser(f"~/Library/LaunchAgents/{LABEL}.plist")
OLD_PLIST_PATH = os.path.expanduser("~/Library/LaunchAgents/com.pandac.watchai.plist")
PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PYTHON_BIN = sys.executable

PLIST_TEMPLATE = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>{LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>{PYTHON_BIN}</string>
        <string>-u</string>
        <string>{PROJECT_DIR}/backend/server.py</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>WorkingDirectory</key>
    <string>{PROJECT_DIR}</string>
    <key>StandardOutPath</key>
    <string>/tmp/vecho_gateway.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/vecho_gateway.log</string>
</dict>
</plist>
"""

def get_lan_ip():
    for iface in ["en0", "en1"]:
        r = subprocess.run(["ipconfig", "getifaddr", iface], capture_output=True, text=True)
        ip = r.stdout.strip()
        if ip and not ip.startswith("198.18."):
            return ip
    return "127.0.0.1"

def install():
    if os.path.exists(OLD_PLIST_PATH):
        subprocess.run(["launchctl", "unload", OLD_PLIST_PATH], capture_output=True)
        subprocess.run(["trash", OLD_PLIST_PATH])
    os.makedirs(os.path.dirname(PLIST_PATH), exist_ok=True)
    with open(PLIST_PATH, "w", encoding="utf-8") as f:
        f.write(PLIST_TEMPLATE)
    subprocess.run(["launchctl", "unload", PLIST_PATH], capture_output=True)
    res = subprocess.run(["launchctl", "load", PLIST_PATH], capture_output=True, text=True)
    if res.returncode == 0:
        lan_ip = get_lan_ip()
        print("======================================================")
        print("[Vecho] Mac 系统自启常驻守护服务安装成功！")
        print(f"[Vecho] 配置文件: {PLIST_PATH}")
        print("======================================================")
        print("【请在手机 Vecho App 连接向导中填入】:")
        print(f"• 电脑 IP: {lan_ip}")
        print("• 服务端口: 31188")
        print("======================================================")
    else:
        print(f"[LaunchAgent] 启动失败: {res.stderr}")

def uninstall():
    if os.path.exists(PLIST_PATH):
        subprocess.run(["launchctl", "unload", PLIST_PATH], capture_output=True)
        # 遵循规范：通过 trash 回收废纸篓
        subprocess.run(["trash", PLIST_PATH])
        print("[LaunchAgent] 已成功卸载自启服务！")
    else:
        print("[LaunchAgent] 未安装自启服务。")

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "uninstall":
        uninstall()
    else:
        install()
