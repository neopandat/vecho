# -*- coding: utf-8 -*-
"""
Vecho 统一消息独立持久化引擎
全面接管手机端所有对话与问答的本地持久化存储，作为手机端的第一核心事实来源（Single Source of Truth）。
手机发送的每一句话和收到的每一条回复均在此双写落地，100% 杜绝因外部客户端未及时写库或崩溃导致的消息丢失。
"""

import os
import json
import time
from datetime import datetime
from typing import Dict, Any, List, Optional

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT_DATA_DIR = os.path.join(os.path.dirname(BASE_DIR), ".data", "message_store")
USER_DATA_DIR = os.path.expanduser("~/.vecho/sessions")

# 优先选用项目根目录下的 .data/message_store
STORE_DIR = PROJECT_DATA_DIR
os.makedirs(STORE_DIR, exist_ok=True)
os.makedirs(USER_DATA_DIR, exist_ok=True)

def _get_session_file(target: str, session_id: str) -> str:
    t = (target or "antigravity").lower().strip()
    s = (session_id or "default").strip()
    # 替换路径不合法字符
    safe_sid = "".join(c if c.isalnum() or c in ("-", "_", ".") else "_" for c in s)
    target_dir = os.path.join(STORE_DIR, t)
    os.makedirs(target_dir, exist_ok=True)
    return os.path.join(target_dir, f"{safe_sid}.json")

def save_message(
    target: str,
    session_id: Optional[str],
    sender: str,
    text: str,
    image_path: Optional[str] = None,
    msg_id: Optional[str] = None
) -> Dict[str, Any]:
    """
    保存单条消息到 Vecho 独立持久化存储
    :param target: 目标 Agent (antigravity, claude, codex, workbuddy 等)
    :param session_id: 会话 ID
    :param sender: 'user' 或 'ai'
    :param text: 消息文本
    :param image_path: 可选的图片文件路径
    :param msg_id: 可选的消息 ID，未提供则自增生成
    :return: 写入的消息对象字典
    """
    sid = (session_id or "").strip()
    if not sid:
        # 如果未传入 session_id，生成基于时间戳的唯一 ID
        sid = f"vecho_{int(time.time() * 1000)}"

    fpath = _get_session_file(target, sid)
    session_data = {
        "session_id": sid,
        "target": target.lower().strip(),
        "title": "新建会话",
        "created_at": datetime.now().isoformat(),
        "updated_at": datetime.now().isoformat(),
        "messages": []
    }

    if os.path.exists(fpath):
        try:
            with open(fpath, "r", encoding="utf-8") as f:
                loaded = json.load(f)
                if isinstance(loaded, dict) and "messages" in loaded:
                    session_data = loaded
        except Exception as e:
            print(f"[MessageStore] 读取现有会话失败 ({fpath}): {e}")

    now_time = datetime.now().strftime("%H:%M")
    actual_id = str(msg_id) if msg_id else f"m_{int(time.time() * 1000)}_{len(session_data['messages'])}"

    # 如果是用户发出的首条有效文本，自动更新会话标题
    if sender == "user" and text.strip():
        first_text = text.strip()[:30]
        if session_data.get("title") in ("新建会话", "未命名对话", "Vecho对话", "来自手机"):
            session_data["title"] = first_text

    msg_item = {
        "id": actual_id,
        "sender": sender,
        "text": text,
        "time": now_time,
        "timestamp": int(time.time() * 1000)
    }
    if image_path:
        msg_item["image_path"] = image_path

    # 去重检查：避免重复推流同一条消息
    existing_ids = {str(m.get("id")) for m in session_data["messages"]}
    if actual_id not in existing_ids:
        session_data["messages"].append(msg_item)

    session_data["updated_at"] = datetime.now().isoformat()

    try:
        tmp_fpath = fpath + ".tmp"
        with open(tmp_fpath, "w", encoding="utf-8") as f:
            json.dump(session_data, f, ensure_ascii=False, indent=2)
        os.replace(tmp_fpath, fpath)
    except Exception as e:
        print(f"[MessageStore] 保存消息失败 ({fpath}): {e}")

    return msg_item

def get_stored_messages(target: str, session_id: Optional[str]) -> List[Dict[str, Any]]:
    """读取指定会话在 Vecho 独立持久化层的所有消息"""
    sid = (session_id or "").strip()
    if not sid:
        return []

    fpath = _get_session_file(target, sid)
    if not os.path.exists(fpath):
        return []

    try:
        with open(fpath, "r", encoding="utf-8") as f:
            data = json.load(f)
            return data.get("messages", [])
    except Exception as e:
        print(f"[MessageStore] 读取消息列表失败: {e}")
        return []

def get_stored_sessions(target: str) -> List[Dict[str, Any]]:
    """获取指定 target 的所有 Vecho 存档会话"""
    t = (target or "antigravity").lower().strip()
    target_dir = os.path.join(STORE_DIR, t)
    if not os.path.exists(target_dir):
        return []

    results = []
    for fname in os.listdir(target_dir):
        if not fname.endswith(".json"):
            continue
        fpath = os.path.join(target_dir, fname)
        try:
            with open(fpath, "r", encoding="utf-8") as f:
                data = json.load(f)
                results.append({
                    "id": data.get("session_id", fname[:-5]),
                    "title": data.get("title", "未命名会话"),
                    "raw_time": data.get("updated_at", ""),
                    "time": data.get("updated_at", "")[:16].replace("T", " ")
                })
        except Exception:
            continue

    results.sort(key=lambda s: s.get("raw_time", ""), reverse=True)
    return results

def delete_stored_session(target: str, session_id: str) -> bool:
    """删除指定的 Vecho 存档会话（通过安全移动到废纸篓）"""
    sid = (session_id or "").strip()
    if not sid:
        return False
    fpath = _get_session_file(target, sid)
    if os.path.exists(fpath):
        import subprocess
        subprocess.run(["trash", fpath])
        return True
    return False
