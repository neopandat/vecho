#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Vecho · 真机编译构建与一键安装脚本
遵循 AGENTS.md 规范：严格锁定目标设备仅为【我是大白】，严禁未经许可安装到其他设备
"""

import os
import sys
import time
import subprocess

PROJECT_PATH = "ios/Vecho.xcodeproj"
SCHEME_NAME = "Vecho"
DEVELOPMENT_TEAM = "35J6RJBCWB"

TARGET_DEVICE_NAME = "我是大白"
TARGET_DEVICE_ID = "90DAD265-82FA-54ED-99FA-5CC8E45CC0F7"

def main():
    start_time = time.time()
    print(f">>> 启动 Vecho 真机自动签名编译 (目标设备: {TARGET_DEVICE_NAME})...")

    build_cmd = [
        "xcodebuild",
        "-project", PROJECT_PATH,
        "-scheme", SCHEME_NAME,
        "-configuration", "Debug",
        "-destination", "generic/platform=iOS",
        "-allowProvisioningUpdates",
        f"DEVELOPMENT_TEAM={DEVELOPMENT_TEAM}",
        "build"
    ]
    res = subprocess.run(build_cmd)
    if res.returncode != 0:
        print("[错误] 编译失败！")
        sys.exit(1)

    matches = [
        os.path.expanduser("~/Library/Developer/Xcode/DerivedData/Vecho-*/Build/Products/Debug-iphoneos/Vecho.app"),
        os.path.expanduser("~/Library/Developer/Xcode/DerivedData/*/Build/Products/Debug-iphoneos/Vecho.app")
    ]
    import glob
    found = []
    for m in matches:
        found.extend(glob.glob(m))
    found = [p for p in found if os.path.isdir(p)]
    found.sort(key=os.path.getmtime, reverse=True)
    if found:
        app_path = found[0]
    else:
        print("[错误] 未找到编译产物 Vecho.app")
        sys.exit(1)

    print(f"\n✓ 编译产物校验通过: {app_path}")
    print(f">> 正在安装至目标设备 [{TARGET_DEVICE_NAME}] ({TARGET_DEVICE_ID})...")

    install_cmd = [
        "xcrun", "devicectl", "device", "install", "app",
        "--device", TARGET_DEVICE_ID,
        app_path
    ]
    sub_res = subprocess.run(install_cmd)
    if sub_res.returncode == 0:
        print(f"✓ 成功安装至 [{TARGET_DEVICE_NAME}]！")
    else:
        print(f"× 安装至 [{TARGET_DEVICE_NAME}] 失败")
        sys.exit(1)

    print(f"\n✓ 部署圆满完成，耗时: {round(time.time() - start_time, 1)} 秒。")

if __name__ == "__main__":
    main()
