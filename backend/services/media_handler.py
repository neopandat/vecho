# -*- coding: utf-8 -*-
"""
多模态资源处理器与纯后台直接通信引擎
全面废除任何剪贴板（the clipboard）与窗口抢占，全链路采用官方原生 RPC / CLI 进程管道直接通信。
1. Antigravity: 官方 agentapi 原生 RPC 接口
2. Claude: 官方 /usr/local/bin/claude CLI 纯后台管道
3. WorkBuddy: 内置官方 codebuddy CLI 纯后台管道
4. ChatGPT / Codex: 官方 codex exec CLI 纯后台管道
5. 手机端全量消息独立持久化：即时双写落地 message_store，确保会话与记录 100% 完整复原
"""

import os
import time
import base64
import threading
import subprocess
from datetime import datetime
from typing import Optional, Tuple
from .message_store import save_message
from .monitor import broadcaster, push_bark

UPLOAD_DIR = "/Users/pandac/Scripts/uploads"
AGENTAPI_PATH = os.path.expanduser("~/.gemini/antigravity/bin/agentapi")
CLAUDE_CLI = "/usr/local/bin/claude"
WORKBUDDY_CLI = "/usr/local/bin/codebuddy"
if not os.path.exists(WORKBUDDY_CLI):
    WORKBUDDY_CLI = "/Applications/WorkBuddy.app/Contents/Resources/app.asar.unpacked/cli/bin/codebuddy"
CODEX_CLI = "/usr/local/bin/codex"
if not os.path.exists(CODEX_CLI):
    CODEX_CLI = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"

os.makedirs(UPLOAD_DIR, exist_ok=True)

# 构造后台安全环境变量，确保包含 node、cli 二进制路径
SAFE_ENV = os.environ.copy()
_extra_bins = ["/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin", os.path.expanduser("~/.local/bin")]
SAFE_ENV["PATH"] = ":".join([p for p in _extra_bins if os.path.exists(p)]) + ":" + SAFE_ENV.get("PATH", "")

def get_latest_antigravity_session_id() -> Optional[str]:
    """获取最新活跃的 Antigravity 会话 ID"""
    db_path = os.path.expanduser("~/.gemini/antigravity/conversation_summaries.db")
    if not os.path.exists(db_path):
        return None
    try:
        import sqlite3
        conn = sqlite3.connect(db_path)
        cur = conn.cursor()
        cur.execute("SELECT conversation_id FROM conversation_summaries WHERE status != 'archived' ORDER BY last_modified_time DESC LIMIT 1")
        row = cur.fetchone()
        conn.close()
        if row and row[0]:
            return row[0]
    except Exception as e:
        print(f"[MediaHandler] 读取最新会话错误: {e}")
    return None

def discover_antigravity_ls_env() -> Tuple[Optional[str], Optional[str]]:
    """动态探测当前运行的 Antigravity language_server 的地址和 CSRF Token"""
    try:
        ps_res = subprocess.run(["ps", "-A", "-o", "pid,command"], capture_output=True, text=True)
        for line in ps_res.stdout.split("\n"):
            if "language_server" in line and "--csrf_token" in line:
                parts = line.strip().split()
                pid = parts[0]
                token_parts = line.split("--csrf_token")
                token = token_parts[1].strip().split()[0].replace("=", "").strip()
                lsof_res = subprocess.run(["lsof", "-nP", "-p", pid], capture_output=True, text=True)
                ports = []
                for l in lsof_res.stdout.split("\n"):
                    if "LISTEN" in l and "TCP" in l:
                        for t in l.split():
                            if ":" in t and t.split(":")[-1].isdigit():
                                ports.append(t.split(":")[-1])
                ports.sort(key=lambda x: int(x), reverse=True)
                if ports:
                    return f"localhost:{ports[0]}", token
    except Exception as e:
        print(f"[MediaHandler] 嗅探 Language Server 异常: {e}")
    return None, None

def deliver_antigravity_direct(message: str, session_id: Optional[str] = None) -> Tuple[bool, str]:
    """通过官方原生 agentapi 纯后台无感投递，杜绝任何窗口弹窗与按键拦截"""
    if os.path.exists(AGENTAPI_PATH):
        try:
            target_sid = session_id.strip() if session_id and session_id.strip() else None

            ls_addr, csrf_token = discover_antigravity_ls_env()
            env = os.environ.copy()
            if ls_addr and csrf_token:
                env["ANTIGRAVITY_LS_ADDRESS"] = ls_addr
                env["ANTIGRAVITY_CSRF_TOKEN"] = csrf_token

            default_title = "Vecho对话"
            if target_sid:
                cmd = [AGENTAPI_PATH, "send-message", f"--title={default_title}", target_sid, message]
            else:
                cmd = [AGENTAPI_PATH, "new-conversation", f"--title={default_title}", message]

            print(f"[MediaHandler] Antigravity 原生投递: cmd={' '.join(cmd[:3])}, target_sid={target_sid}, 长度={len(message)}")
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=15, env=env)
            if res.returncode == 0:
                return True, "原生后台投递成功"
            else:
                return False, res.stderr or res.stdout or "agentapi 执行失败"
        except Exception as e:
            print(f"[MediaHandler] agentapi 执行异常: {e}")
            return False, str(e)
    return False, "未找到 agentapi 原生工具"

def deliver_claude_direct(message: str, session_id: Optional[str] = None) -> Tuple[bool, str]:
    """通过官方 Claude Code CLI 纯后台异步执行，问答自动广播并持久化"""
    if not os.path.exists(CLAUDE_CLI):
        return False, "未找到 /usr/local/bin/claude 工具"

    cmd = [CLAUDE_CLI, "-p", message]
    if session_id and len(session_id) == 36 and "-" in session_id:
        cmd = [CLAUDE_CLI, "--session-id", session_id, "-p", message]

    def run_claude_async():
        try:
            print(f"[MediaHandler] Claude CLI 异步开始执行: session_id={session_id}")
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=90, env=SAFE_ENV)
            if res.returncode == 0 and res.stdout.strip():
                reply_text = res.stdout.strip()
                # 1. 独立持久化存储
                save_message("claude", session_id, "ai", reply_text)
                # 2. 线程安全 WebSocket 广播
                broadcaster.notify({
                    "id": str(int(time.time() * 1000)),
                    "type": "message",
                    "target": "claude",
                    "session_id": session_id or "",
                    "sender": "ai",
                    "text": reply_text,
                    "time": datetime.now().strftime("%H:%M")
                })
                push_bark("Claude 的回复", reply_text, "Claude")
            else:
                print(f"[MediaHandler] Claude CLI 执行无有效输出: code={res.returncode}, err={res.stderr}")
        except Exception as e:
            print(f"[MediaHandler] Claude CLI 异步异常: {e}")

    threading.Thread(target=run_claude_async, daemon=True).start()
    return True, "已作为原生指令提交至 Claude 命令行管道"

def deliver_workbuddy_direct(message: str, session_id: Optional[str] = None) -> Tuple[bool, str]:
    """通过内置官方 WorkBuddy codebuddy CLI 纯后台异步执行，问答自动广播并持久化"""
    if not os.path.exists(WORKBUDDY_CLI):
        return False, "未找到 codebuddy CLI 工具"

    cmd = [WORKBUDDY_CLI, "-p", message]
    if session_id and len(session_id) == 36 and "-" in session_id:
        cmd = [WORKBUDDY_CLI, "--session-id", session_id, "-p", message]

    def run_wb_async():
        try:
            print(f"[MediaHandler] WorkBuddy CLI 异步开始执行: session_id={session_id}")
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=90, env=SAFE_ENV)
            if res.returncode == 0 and res.stdout.strip():
                reply_text = res.stdout.strip()
                save_message("workbuddy", session_id, "ai", reply_text)
                broadcaster.notify({
                    "id": str(int(time.time() * 1000)),
                    "type": "message",
                    "target": "workbuddy",
                    "session_id": session_id or "",
                    "sender": "ai",
                    "text": reply_text,
                    "time": datetime.now().strftime("%H:%M")
                })
                push_bark("WorkBuddy 的回复", reply_text, "WorkBuddy")
            else:
                print(f"[MediaHandler] WorkBuddy CLI 执行无有效输出: code={res.returncode}, err={res.stderr}")
        except Exception as e:
            print(f"[MediaHandler] WorkBuddy CLI 异步异常: {e}")

    threading.Thread(target=run_wb_async, daemon=True).start()
    return True, "已作为原生指令提交至 WorkBuddy 命令行管道"

def deliver_codex_direct(message: str, session_id: Optional[str] = None) -> Tuple[bool, str]:
    """通过官方 Codex CLI 纯系统命令管道异步执行，问答自动广播并持久化"""
    if not os.path.exists(CODEX_CLI):
        return False, "未找到 codex CLI 工具"

    cmd = [CODEX_CLI, "exec", "--skip-git-repo-check", message]

    def run_codex_async():
        try:
            print(f"[MediaHandler] Codex CLI 异步开始执行: session_id={session_id}")
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=90, env=SAFE_ENV)
            if res.returncode == 0 and res.stdout.strip():
                reply_text = res.stdout.strip()
                if "--------\n" in reply_text:
                    reply_text = reply_text.split("--------\n")[-1].strip()
                save_message("chatgpt", session_id, "ai", reply_text)
                save_message("codex", session_id, "ai", reply_text)
                broadcaster.notify({
                    "id": str(int(time.time() * 1000)),
                    "type": "message",
                    "target": "chatgpt",
                    "session_id": session_id or "",
                    "sender": "ai",
                    "text": reply_text,
                    "time": datetime.now().strftime("%H:%M")
                })
                push_bark("Codex 的回复", reply_text, "Codex")
            else:
                print(f"[MediaHandler] Codex CLI 执行无有效输出: code={res.returncode}, err={res.stderr}")
        except Exception as e:
            print(f"[MediaHandler] Codex CLI 异步异常: {e}")

    threading.Thread(target=run_codex_async, daemon=True).start()
    return True, "已作为原生指令提交至 Codex 命令行管道"

def process_and_deliver_media(
    target: str,
    message: str = "",
    session_id: Optional[str] = None,
    image_base64: Optional[str] = None,
    file_base64: Optional[str] = None,
    file_name: Optional[str] = None
) -> Tuple[bool, str]:
    """
    处理多模态载荷并走纯后台原生系统级管道投递
    100% 杜绝剪贴板访问（零剪贴板历史污染，零弹窗干扰）
    手机发送消息第一时间独立持久化至 message_store
    """
    try:
        t = (target or "antigravity").lower().strip()
        print(f"[MediaHandler] 收到消息请求: target={t}, session_id={session_id}, msg_len={len(message)}, has_img={image_base64 is not None}")

        # 1. 处理图片（保留原图高清分辨率）
        img_path = None
        if image_base64:
            if "," in image_base64:
                image_base64 = image_base64.split(",", 1)[1]
            img_bytes = base64.b64decode(image_base64)
            img_path = os.path.join(UPLOAD_DIR, f"img_{int(time.time() * 1000)}.jpg")
            with open(img_path, "wb") as f:
                f.write(img_bytes)

        # 2. 处理文件
        file_path = None
        if file_base64:
            if "," in file_base64:
                file_base64 = file_base64.split(",", 1)[1]
            f_bytes = base64.b64decode(file_base64)
            safe_name = file_name or f"file_{int(time.time() * 1000)}"
            file_path = os.path.join(UPLOAD_DIR, safe_name)
            with open(file_path, "wb") as f:
                f.write(f_bytes)

        # 组合消息载荷
        full_message = message
        if img_path:
            full_message = f"{full_message}\n[附件图片: {img_path}]" if full_message else f"[附件图片: {img_path}]"
        if file_path:
            full_message = f"{full_message}\n[附件文件: {file_path}]" if full_message else f"[附件文件: {file_path}]"

        # 3. 手机端发送的每一条消息，第一时间写入 Vecho 独立持久化存储库！
        try:
            save_message(
                target=t,
                session_id=session_id,
                sender="user",
                text=full_message,
                image_path=img_path
            )
        except Exception as e:
            print(f"[MediaHandler] 保存用户消息到 message_store 异常: {e}")

        # 4. 纯后台系统级无感管道派发（零剪贴板触碰）
        if t in ("antigravity", ""):
            return deliver_antigravity_direct(full_message, session_id=session_id)

        if t == "claude":
            return deliver_claude_direct(full_message, session_id=session_id)

        if t == "workbuddy":
            return deliver_workbuddy_direct(full_message, session_id=session_id)

        if t in ("chatgpt", "codex"):
            return deliver_codex_direct(full_message, session_id=session_id)

        return False, f"目标智能体 {t} 未配置纯系统后台通道"

    except Exception as e:
        return False, str(e)
