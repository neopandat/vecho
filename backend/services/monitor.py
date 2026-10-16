# -*- coding: utf-8 -*-
"""
智能体响应输出监控器与实时广播调度
在后台异步轮询各智能体产生的最新输出，并通过长连接全双工推送给所有连接的客户端（iOS / Web）
"""

import os
import glob
import json
import time
import asyncio
import ssl
import urllib.parse
import urllib.request
import subprocess
from datetime import datetime
from typing import Set, Dict, Any, Callable

BARK_KEY = "MgRGkwhkJaMPmLFx4qcviL"
BARK_API = f"https://api.day.app/{BARK_KEY}"

def push_bark(title: str, body: str, group: str = "AI"):
    clean_body = body[:4000]
    try:
        ctx = ssl._create_unverified_context()
        data = urllib.parse.urlencode({
            "title": title,
            "body": clean_body,
            "group": group,
            "badge": 1,
            "sound": "minuet",
            "level": "timeSensitive",
            "isArchive": "1"
        }).encode("utf-8")
        req = urllib.request.Request(BARK_API, data=data, method="POST")
        urllib.request.urlopen(req, context=ctx, timeout=8)
    except:
        pass

class MessageBroadcaster:
    def __init__(self):
        self.clients: Set[Any] = set()
        self.msg_id_seq = 0
        self.recent_messages: Dict[str, list] = {
            "antigravity": [],
            "claude": [],
            "workbuddy": [],
            "codex": []
        }

    def register(self, ws: Any):
        self.clients.add(ws)

    def unregister(self, ws: Any):
        self.clients.discard(ws)

    async def broadcast(self, payload: Dict[str, Any]):
        dead = set()
        msg_str = json.dumps(payload, ensure_ascii=False)
        for ws in self.clients:
            try:
                await ws.send_text(msg_str)
            except Exception:
                dead.add(ws)
        for ws in dead:
            self.clients.discard(ws)

    def notify(self, payload: Dict[str, Any]):
        """线程安全地向所有客户端广播消息"""
        loop = getattr(self, "loop", None)
        if loop and loop.is_running():
            asyncio.run_coroutine_threadsafe(self.broadcast(payload), loop)
        else:
            try:
                cur_loop = asyncio.get_event_loop()
                if cur_loop.is_running():
                    asyncio.create_task(self.broadcast(payload))
                else:
                    cur_loop.run_until_complete(self.broadcast(payload))
            except Exception:
                pass

broadcaster = MessageBroadcaster()

async def monitor_antigravity_loop():
    """实时监控 Antigravity transcript.jsonl 的增量输出"""
    pattern = os.path.expanduser("~/.gemini/antigravity/brain/*/.system_generated/logs/transcript.jsonl")
    # 服务启动时记录已有文件的大小，防止启动时重复广播全量历史
    initial_files = glob.glob(pattern)
    file_offsets = {f: os.path.getsize(f) for f in initial_files}
    last_pushed = {}

    while True:
        try:
            files = glob.glob(pattern)
            if files:
                # 检查最近更新的活跃文件
                sorted_files = sorted(files, key=os.path.getmtime, reverse=True)[:3]
                for fpath in sorted_files:
                    if fpath not in file_offsets:
                        # 新会话生成的新文件：从 0 开始完整读取首条模型回复，严禁跳过
                        file_offsets[fpath] = 0

                    prev_offset = file_offsets[fpath]
                    cur_size = os.path.getsize(fpath)

                    if cur_size < prev_offset:
                        prev_offset = 0

                    if cur_size > prev_offset:
                        with open(fpath, "r", encoding="utf-8", errors="ignore") as fp:
                            fp.seek(prev_offset)
                            new_lines = fp.readlines()
                            file_offsets[fpath] = fp.tell()

                    for line in new_lines:
                        line = line.strip()
                        if not line:
                            continue
                        try:
                            item = json.loads(line)
                            if item.get("source") == "MODEL" and item.get("type") == "PLANNER_RESPONSE":
                                content = item.get("content")
                                step_index = item.get("step_index")
                                if content and content.strip():
                                    if last_pushed.get(fpath) != step_index:
                                        last_pushed[fpath] = step_index
                                        clean_content = content.replace("<SYSTEM_MESSAGE>", "").replace("</SYSTEM_MESSAGE>", "").strip()
                                        
                                        # 提取该消息真实的会话 ID
                                        session_id = ""
                                        if "brain" in fpath:
                                            parts = fpath.split(os.sep)
                                            if "brain" in parts:
                                                idx = parts.index("brain")
                                                if idx + 1 < len(parts):
                                                    session_id = parts[idx + 1]

                                        broadcaster.msg_id_seq += 1
                                        msg_item = {
                                            "id": str(broadcaster.msg_id_seq),
                                            "type": "message",
                                            "target": "antigravity",
                                            "session_id": session_id,
                                            "sender": "ai",
                                            "text": clean_content,
                                            "time": datetime.now().strftime("%H:%M")
                                        }
                                        broadcaster.recent_messages["antigravity"].append(msg_item)
                                        if len(broadcaster.recent_messages["antigravity"]) > 50:
                                            broadcaster.recent_messages["antigravity"].pop(0)

                                        # 实时写入 Vecho 独立持久化存储库
                                        try:
                                            from .message_store import save_message
                                            save_message("antigravity", session_id, "ai", clean_content, msg_id=msg_item["id"])
                                        except Exception as err:
                                            print(f"[Monitor] 保存 Antigravity 回复至 message_store 异常: {err}")

                                        # 实时向所有客户端广播 WebSocket 消息
                                        await broadcaster.broadcast(msg_item)

                                        # 后台向手机/手表推送 Bark
                                        push_bark("Antigravity 的回复", clean_content, "Antigravity")
                        except Exception:
                            continue
        except Exception as e:
            pass
        await asyncio.sleep(0.6)
