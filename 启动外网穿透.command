#!/bin/bash
# Vecho 外网穿透一键启动脚本 (Cloudflare Tunnel)
# 无需公网 IP，不占 iOS 虚拟网卡，手机外网秒连 Mac

cd "$(dirname "$0")"

clear
echo "======================================================"
echo "          Vecho 外网穿透 (Cloudflare Tunnel)"
echo "======================================================"

# 检查服务端口
PORT=31188
PID=$(lsof -ti :$PORT)

if [ -z "$PID" ]; then
    echo "提示: 检测到本地网关未启动，正在自动启动网关..."
    if [ -x "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3" ]; then
        PYTHON_BIN="/Library/Frameworks/Python.framework/Versions/3.11/bin/python3"
    elif [ -x "/usr/local/bin/python3" ]; then
        PYTHON_BIN="/usr/local/bin/python3"
    else
        PYTHON_BIN="python3"
    fi
    nohup "$PYTHON_BIN" -u backend/server.py > /tmp/vecho_gateway.log 2>&1 &
    sleep 1.5
fi

# 检查 cloudflared 路径
CLOUDFLARED_BIN=""
if [ -x "/usr/local/bin/cloudflared" ]; then
    CLOUDFLARED_BIN="/usr/local/bin/cloudflared"
elif [ -x "/opt/homebrew/bin/cloudflared" ]; then
    CLOUDFLARED_BIN="/opt/homebrew/bin/cloudflared"
elif command -v cloudflared >/dev/null 2>&1; then
    CLOUDFLARED_BIN="cloudflared"
else
    echo "错误: 未找到 cloudflared 工具，请执行 brew install cloudflared"
    exit 1
fi

LOG_FILE="/tmp/vecho_tunnel.log"
> "$LOG_FILE"

echo "正在建立全球安全加密隧道..."
"$CLOUDFLARED_BIN" tunnel --url "http://localhost:$PORT" > "$LOG_FILE" 2>&1 &
TUNNEL_PID=$!

trap "echo ''; echo '正在关闭外网隧道...'; kill $TUNNEL_PID 2>/dev/null; exit 0" INT TERM EXIT

# 等待解析分配的公网 URL
FOUND_URL=""
for i in {1..30}; do
    FOUND_URL=$(grep -oE "https://[a-zA-Z0-9-]+\.trycloudflare\.com" "$LOG_FILE" | head -n 1)
    if [ -n "$FOUND_URL" ]; then
        break
    fi
    sleep 0.5
done

if [ -n "$FOUND_URL" ]; then
    echo "======================================================"
    echo "✅ 外网隧道启动成功！"
    echo ""
    echo "   公网访问地址: $FOUND_URL"
    echo ""
    echo "手机端（我是大白）配置方法："
    echo "在「连接配置」的「电脑 IP / 域名」中，直接填入："
    echo "$FOUND_URL"
    echo "（端口项无需修改，可保持 31188）"
    echo "======================================================"
    echo "提示: 当前窗口保持开启即可保持外网连通。按 Ctrl+C 可关闭隧道。"
else
    echo "⚠️ 未能即时捕获公网网址，请查看日志:"
    cat "$LOG_FILE"
fi

wait $TUNNEL_PID
