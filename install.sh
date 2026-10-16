#!/usr/bin/env bash
# Vecho 智能网关一键极速安装脚本 (macOS)
set -e

REPO_URL="https://github.com/neopandat/vecho.git"
INSTALL_DIR="$HOME/.vecho"

echo "=================================================="
echo "          Vecho 智能网关一键安装程序              "
echo "=================================================="

# 1. 克隆或拉取仓库
if [ -d "$INSTALL_DIR/.git" ]; then
    echo "[1/4] 检查并更新仓库..."
    cd "$INSTALL_DIR" && git pull --rebase origin main || true
else
    echo "[1/4] 克隆 Vecho 仓库到 $INSTALL_DIR..."
    git clone "$REPO_URL" "$INSTALL_DIR"
fi

cd "$INSTALL_DIR"

# 2. 检查安装依赖
echo "[2/4] 安装 Python 运行依赖..."
python3 -m pip install -q -r requirements.txt 2>/dev/null || pip3 install -q -r requirements.txt

# 3. 注册并拉起常驻守护服务
echo "[3/4] 注册并拉起系统自启服务 (LaunchAgent)..."
python3 scripts/install_launchagent.py

# 4. 获取物理局域网 IP
LAN_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "127.0.0.1")

echo "=================================================="
echo "          ✅ Vecho 服务已永久常驻在线！           "
echo "=================================================="
echo "【在手机端 Vecho App 连接向导中填入】："
echo "• 电脑 IP:  $LAN_IP"
echo "• 服务端口: 31188"
echo "=================================================="
