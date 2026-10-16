#!/usr/bin/env python3
import asyncio
import json
import urllib.request
import websockets

BASE_HTTP = "http://127.0.0.1:31188"
BASE_WS = "ws://127.0.0.1:31188/ws"

def test_http():
    print("[Test] 1. 测试 HTTP /health...")
    with urllib.request.urlopen(f"{BASE_HTTP}/health", timeout=3) as resp:
        assert resp.status == 200
        data = json.loads(resp.read().decode())
        print(" -> 响应:", data)

    print("[Test] 2. 测试 HTTP /api/app_status...")
    with urllib.request.urlopen(f"{BASE_HTTP}/api/app_status?target=antigravity", timeout=3) as resp:
        assert resp.status == 200
        data = json.loads(resp.read().decode())
        print(" -> 响应:", data)

    print("[Test] 3. 测试 HTTP /api/sessions...")
    with urllib.request.urlopen(f"{BASE_HTTP}/api/sessions?target=antigravity", timeout=3) as resp:
        assert resp.status == 200
        data = json.loads(resp.read().decode())
        groups_count = len(data.get("groups", []))
        print(f" -> 成功获取 Antigravity 会话分组数: {groups_count}")

    print("[Test] 4. 测试 Web 首页 HTML 交付...")
    with urllib.request.urlopen(f"{BASE_HTTP}/", timeout=3) as resp:
        assert resp.status == 200
        content = resp.read().decode()
        assert "<title>控制台</title>" in content
        print(" -> 成功验证 Web 首页交付")

async def test_ws():
    print("[Test] 5. 测试 WebSocket 长连接全双工通信...")
    async with websockets.connect(BASE_WS) as ws:
        # 等待握手消息
        msg = await ws.recv()
        data = json.loads(msg)
        print(" -> 收到服务端握手:", data)
        assert data.get("type") == "connected"

        # 发送 ping
        await ws.send(json.dumps({"type": "ping"}))
        pong = await ws.recv()
        pong_data = json.loads(pong)
        print(" -> 收到心跳回复:", pong_data)
        assert pong_data.get("type") == "pong"

        # 测试状态查询
        await ws.send(json.dumps({"type": "get_status", "target": "antigravity"}))
        status_msg = await ws.recv()
        status_data = json.loads(status_msg)
        print(" -> 收到状态查询响应:", status_data)
        assert status_data.get("type") == "status"

    print("[Test] 全部测试顺利通过！")

def main():
    test_http()
    asyncio.run(test_ws())

if __name__ == "__main__":
    main()
