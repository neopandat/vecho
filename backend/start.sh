#!/usr/bin/env bash
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

PORT="${PORT:-31188}"
echo "启动统一多智能体长连接网关 (端口: $PORT)..."

# 检查是否已运行
PID=$(pgrep -f "backend/server.py" || true)
if [ -n "$PID" ]; then
    echo "发现运行中的服务进程 (PID: $PID)，正在重启..."
    kill "$PID" || true
    sleep 1
fi

python3 server.py
