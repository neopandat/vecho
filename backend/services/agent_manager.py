# -*- coding: utf-8 -*-
"""
智能体进程管理与系统级调度
覆盖主流 Agent：Antigravity, WorkBuddy, Claude, ChatGPT, Cursor, Windsurf, 总调度
支持探测已安装状态、运行状态、远程拉起及消息注入
"""

import os
import subprocess
import time
import socket
from typing import Dict, Any, List, Optional

APP_MAP = {
    "antigravity": "Antigravity",
    "workbuddy": "WorkBuddy",
    "claude": "Claude",
    "chatgpt": "ChatGPT",
    "cursor": "Cursor",
    "windsurf": "Windsurf",
    "trae": "Trae",
    "qoder": "Qoder",
    "deepseek": "DeepSeek",
    "cline": "Cline",
    "aider": "Aider",
    "copilot": "Copilot",
    "current": ""
}

AGENT_METADATA = [
    {
        "id": "antigravity",
        "name": "Antigravity",
        "app_name": "Antigravity",
        "description": "Google 全能开发智能体",
        "default_enabled": True
    },
    {
        "id": "workbuddy",
        "name": "WorkBuddy",
        "app_name": "WorkBuddy",
        "description": "自动化工作智能体",
        "default_enabled": True
    },
    {
        "id": "claude",
        "name": "Claude",
        "app_name": "Claude",
        "description": "Anthropic 编程与对话智能体",
        "default_enabled": True
    },
    {
        "id": "chatgpt",
        "name": "ChatGPT",
        "app_name": "ChatGPT",
        "description": "OpenAI 官方客户端",
        "default_enabled": True
    },
    {
        "id": "trae",
        "name": "Trae",
        "app_name": "Trae",
        "description": "字节跳动 AI 原生开发工具",
        "default_enabled": True
    },
    {
        "id": "qoder",
        "name": "Qoder",
        "app_name": "Qoder",
        "description": "通义灵码 AI 原生开发工具",
        "default_enabled": True
    },
    {
        "id": "deepseek",
        "name": "DeepSeek",
        "app_name": "DeepSeek",
        "description": "深度求索代码与推理智能体",
        "default_enabled": True
    },
    {
        "id": "cursor",
        "name": "Cursor",
        "app_name": "Cursor",
        "description": "AI 辅助编程编辑器",
        "default_enabled": False
    },
    {
        "id": "windsurf",
        "name": "Windsurf",
        "app_name": "Windsurf",
        "description": "智能编程智能体",
        "default_enabled": False
    },
    {
        "id": "cline",
        "name": "Cline",
        "app_name": "Cline",
        "description": "自主编程智能体",
        "default_enabled": False
    },
    {
        "id": "aider",
        "name": "Aider",
        "app_name": "Aider",
        "description": "终端结对编程智能体",
        "default_enabled": False
    },
    {
        "id": "copilot",
        "name": "Copilot",
        "app_name": "GitHub Copilot",
        "description": "GitHub 编程助手",
        "default_enabled": False
    }
]

def get_lan_ip() -> str:
    """获取 Mac 电脑真实的 Wi-Fi 局域网 IP 地址"""
    # 优先通过 en0 / en1 探测物理 Wi-Fi 局域网 IP
    for iface in ["en0", "en1"]:
        res = subprocess.run(["ipconfig", "getifaddr", iface], capture_output=True, text=True)
        ip = res.stdout.strip()
        if ip and not ip.startswith("198.18."):
            return ip

    # 备用方案：路由探测
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(('223.5.5.5', 80))
        ip = s.getsockname()[0]
        if not ip.startswith("198.18."):
            return ip
    except Exception:
        pass
    finally:
        s.close()

    return "127.0.0.1"

APP_CANDIDATES: Dict[str, List[str]] = {
    "antigravity": ["Antigravity", "/Applications/Antigravity.app"],
    "workbuddy": ["WorkBuddy", "/Applications/WorkBuddy.app"],
    "claude": ["Claude", "/Applications/Claude.app"],
    "chatgpt": ["ChatGPT", "Codex", "/Applications/ChatGPT.app"],
    "deepseek": ["DeepSeek Harness", "DeepSeek", os.path.expanduser("~/Applications/Chrome Apps.localized/DeepSeek Harness.app"), "/Applications/DeepSeek.app"],
    "trae": ["Trae", "/Applications/Trae.app"],
    "qoder": ["Qoder", "/Applications/Qoder.app"],
    "cursor": ["Cursor", "/Applications/Cursor.app"],
    "windsurf": ["Windsurf", "/Applications/Windsurf.app"],
    "cline": ["Cline"],
    "aider": ["Aider"],
    "copilot": ["GitHub Copilot", "Copilot"],
}

def get_app_name(target: str) -> str:
    return APP_MAP.get(target.lower().strip(), target)

def is_app_installed(target: str) -> bool:
    candidates = APP_CANDIDATES.get(target.lower().strip(), [get_app_name(target)])
    for c in candidates:
        if c.endswith(".app") and os.path.exists(c):
            return True
        p1 = f"/Applications/{c}.app"
        p2 = os.path.expanduser(f"~/Applications/{c}.app")
        p3 = os.path.expanduser(f"~/Applications/Chrome Apps.localized/{c}.app")
        if any(os.path.exists(p) for p in [p1, p2, p3]):
            return True
        import shutil
        if shutil.which(c.lower()):
            return True
    return False

def is_app_running(target: str) -> bool:
    candidates = APP_CANDIDATES.get(target.lower().strip(), [get_app_name(target)])
    for c in candidates:
        name = os.path.basename(c).replace(".app", "")
        res = subprocess.run(["pgrep", "-f", name], capture_output=True, text=True)
        if res.returncode == 0:
            return True
    return False

def launch_app(target: str) -> bool:
    candidates = APP_CANDIDATES.get(target.lower().strip(), [get_app_name(target)])
    for c in candidates:
        if c.endswith(".app") and os.path.exists(c):
            res = subprocess.run(["open", c], capture_output=True)
            if res.returncode == 0:
                return True
        p1 = f"/Applications/{c}.app"
        p2 = os.path.expanduser(f"~/Applications/{c}.app")
        p3 = os.path.expanduser(f"~/Applications/Chrome Apps.localized/{c}.app")
        for p in [p1, p2, p3]:
            if os.path.exists(p):
                res = subprocess.run(["open", p], capture_output=True)
                if res.returncode == 0:
                    return True
        res = subprocess.run(["open", "-a", c], capture_output=True)
        if res.returncode == 0:
            return True
    return False

def discover_installed_agents() -> List[Dict[str, Any]]:
    """扫描系统，输出所有智能体的安装状态与运行状态"""
    results = []
    for meta in AGENT_METADATA:
        agent_id = meta["id"]
        installed = is_app_installed(agent_id)
        running = is_app_running(agent_id)
        results.append({
            "id": agent_id,
            "name": meta["name"],
            "description": meta["description"],
            "installed": installed,
            "running": running,
            "default_enabled": meta["default_enabled"]
        })
    return results

APP_BUNDLE_IDS: Dict[str, str] = {
    "workbuddy": "com.tencent.workbuddy.mac",
    "antigravity": "com.google.antigravity",
    "claude": "com.anthropic.claude-desktop",
    "chatgpt": "com.openai.chat",
    "cursor": "com.todesktop.230313mzl4w4u92",
    "windsurf": "com.exafunction.windsurf",
    "trae": "com.trae.app",
    "qoder": "com.alibaba.qoder",
    "deepseek": "com.deepseek.app"
}

def activate_app_by_target(target: str) -> bool:
    """优先使用 Bundle ID 精准唤醒目标应用，根治 WorkBuddy (Electron) 等进程失焦或找不到的问题"""
    t = target.lower().strip()
    bundle_id = APP_BUNDLE_IDS.get(t)
    if bundle_id:
        res = subprocess.run(["open", "-b", bundle_id], capture_output=True)
        if res.returncode == 0:
            return True
    app_name = get_app_name(target)
    if app_name:
        res = subprocess.run(["open", "-a", app_name], capture_output=True)
        return res.returncode == 0
    return False

def deliver_message(target: str, message: str) -> bool:
    """统一通过无感纯后台系统管道投递消息，100% 杜绝剪贴板与窗口弹窗"""
    from .media_handler import process_and_deliver_media
    ok, _ = process_and_deliver_media(target=target, message=message)
    return ok

def create_antigravity_new_session(project: str = "") -> Optional[str]:
    """通过 agentapi 纯官方接口真实创建新会话，默认名称为 'Vecho对话'，并置顶更新时间"""
    from .media_handler import AGENTAPI_PATH, discover_antigravity_ls_env
    if not os.path.exists(AGENTAPI_PATH):
        return None
    try:
        ls_addr, csrf_token = discover_antigravity_ls_env()
        env = os.environ.copy()
        if ls_addr and csrf_token:
            env["ANTIGRAVITY_LS_ADDRESS"] = ls_addr
            env["ANTIGRAVITY_CSRF_TOKEN"] = csrf_token

        cmd = [AGENTAPI_PATH, "new-conversation", "--title=Vecho对话", "已通过 Vecho 开启新对话"]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=12, env=env)
        if res.returncode == 0:
            import json
            data = json.loads(res.stdout)
            new_cid = data.get("response", {}).get("newConversation", {}).get("conversationId")
            if new_cid:
                db_path = os.path.expanduser("~/.gemini/antigravity/conversation_summaries.db")
                if os.path.exists(db_path):
                    import sqlite3
                    from datetime import datetime, timezone
                    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S.%f+00:00")
                    for _ in range(5):
                        time.sleep(0.15)
                        try:
                            conn = sqlite3.connect(db_path)
                            cur = conn.cursor()
                            cur.execute(
                                "UPDATE conversation_summaries SET last_modified_time = ?, title = 'Vecho对话' WHERE conversation_id = ?",
                                (now_iso, new_cid)
                            )
                            updated = cur.rowcount
                            conn.commit()
                            conn.close()
                            if updated > 0:
                                break
                        except Exception:
                            pass
                return new_cid
    except Exception as e:
        print(f"[AgentManager] create_antigravity_new_session 异常: {e}")
    return None

def trigger_new_session(target: str, project: str = "") -> Dict[str, Any]:
    """唤起并开辟新会话窗口，返回真实的 session_id（全量纯后台调度，零弹窗、零按键、零剪贴板）"""
    import uuid
    t = target.lower().strip()
    if t == "antigravity":
        new_sid = create_antigravity_new_session(project=project)
        return {
            "status": "ok" if new_sid else "failed",
            "target": target,
            "session_id": new_sid
        }

    # Claude, WorkBuddy, Codex/ChatGPT 全面走纯后台原生 CLI / API 管道，直接开辟新会话 UUID
    if t in ("claude", "workbuddy", "chatgpt", "codex"):
        new_sid = str(uuid.uuid4())
        return {
            "status": "ok",
            "target": target,
            "session_id": new_sid
        }

    # 其它未适配纯后台的客户端兜底保持空会话
    return {
        "status": "ok",
        "target": target,
        "session_id": None
    }


