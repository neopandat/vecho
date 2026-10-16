#!/bin/bash
# 智能控制台 Mac 服务端一键启动脚本
# 支持在 Finder 中直接双击运行

cd "$(dirname "$0")"

# 优先选择已装有 FastAPI 与 Uvicorn 的 Python 环境
if [ -x "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3" ]; then
    PYTHON_BIN="/Library/Frameworks/Python.framework/Versions/3.11/bin/python3"
elif [ -x "/usr/local/bin/python3" ]; then
    PYTHON_BIN="/usr/local/bin/python3"
else
    PYTHON_BIN="python3"
fi

# 获取真实物理 Wi-Fi 局域网 IP
LAN_IP=$(ipconfig getifaddr en0 2>/dev/null)
if [ -z "$LAN_IP" ]; then
    LAN_IP=$(ipconfig getifaddr en1 2>/dev/null)
fi
if [ -z "$LAN_IP" ]; then
    LAN_IP="127.0.0.1"
fi

PORT=31188
PID=$(lsof -ti :$PORT)

clear
echo "======================================================"
echo "               Vecho 控制台 Mac 服务端"
echo "======================================================"

if [ -n "$PID" ]; then
    echo "提示: 服务已在后台运行中 (PID: $PID)"
else
    echo "正在启动 Vecho 控制台网关..."
    nohup "$PYTHON_BIN" -u backend/server.py > /tmp/vecho_gateway.log 2>&1 &
    sleep 1.2
    PID=$(lsof -ti :$PORT)
fi

echo "服务状态: 正常运行"
echo "服务端口: $PORT"
echo "本机地址: http://localhost:$PORT"
echo "局域网连接: http://$LAN_IP:$PORT"
echo "======================================================"
echo "手机端（我是大白）同 Wi-Fi 填入电脑 IP: $LAN_IP"
echo "若在外网连接，请双击运行「启动外网穿透.command」获取专属公网网址"
echo "======================================================"

open "http://localhost:$PORT"

echo ""
echo "日志输出中 (按 Ctrl+C 可退出当前监控，服务仍将在后台常驻)..."
tail -f /tmp/vecho_gateway.log
