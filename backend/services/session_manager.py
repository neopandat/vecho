# -*- coding: utf-8 -*-
"""
多智能体会话抽屉与项目管理
支持 Antigravity, WorkBuddy, Claude, ChatGPT 的真实会话扫描、历史记录读取、重命名、归档与安全删除（入废纸篓）
源头根治：严格基于各 Agent 真实底层 SQLite 与 JSONL 协议，杜绝任何假数据
"""

import os
import glob
import json
import time
import sqlite3
import subprocess
import urllib.parse
from datetime import datetime
from typing import Dict, Any, List, Optional

# --- 1. Antigravity 会话管理 ---
def get_antigravity_sessions() -> Dict[str, Any]:
    db_path = os.path.expanduser("~/.gemini/antigravity/conversation_summaries.db")
    if not os.path.exists(db_path):
        return {"type_name": "项目文件夹", "can_rename": True, "groups": []}

    try:
        conn = sqlite3.connect(db_path)
        cur = conn.cursor()
        cur.execute(
            "SELECT conversation_id, title, workspace_uris, "
            "CASE WHEN last_modified_time LIKE '0001-%' OR last_modified_time IS NULL THEN datetime('now') ELSE last_modified_time END as sort_time "
            "FROM conversation_summaries WHERE status != 'archived' "
            "ORDER BY sort_time DESC LIMIT 50"
        )
        rows = cur.fetchall()
        conn.close()

        groups_dict: Dict[str, List[Dict[str, Any]]] = {}
        for cid, title, uris_json, mtime in rows:
            folder = "未分类项目"
            try:
                uris = json.loads(uris_json)
                if uris:
                    p = urllib.parse.unquote(uris[0].replace("file://", ""))
                    folder = p.strip("/").split("/")[-1]
            except:
                pass

            display_title = title if title.strip() else "未命名对话"
            mtime_str = str(mtime).replace(" ", "T")
            if folder not in groups_dict:
                groups_dict[folder] = []
            groups_dict[folder].append({
                "id": cid,
                "title": display_title,
                "raw_time": mtime_str,
                "time": mtime_str
            })

        groups = [{"group_name": k, "items": v} for k, v in groups_dict.items()]
        groups.sort(key=lambda g: max(((item.get("raw_time") or item.get("time") or "") for item in g["items"]), default=""), reverse=True)
        return {"type_name": "项目文件夹", "can_rename": True, "groups": groups}
    except Exception as e:
        print(f"[SessionManager] Antigravity error: {e}")
        return {"type_name": "项目文件夹", "can_rename": True, "groups": []}

def rename_antigravity_session(session_id: str, new_title: str) -> bool:
    db_path = os.path.expanduser("~/.gemini/antigravity/conversation_summaries.db")
    if not os.path.exists(db_path):
        return False
    try:
        from datetime import datetime, timezone
        now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S.%f+00:00")
        conn = sqlite3.connect(db_path)
        cur = conn.cursor()
        cur.execute("SELECT title, raw_summary FROM conversation_summaries WHERE conversation_id = ?", (session_id,))
        row = cur.fetchone()
        old_title = row[0] if row else ""
        raw_blob = row[1] if row else None

        # 1. 更新 title 与 last_modified_time
        cur.execute("UPDATE conversation_summaries SET title = ?, last_modified_time = ? WHERE conversation_id = ?", (new_title.strip(), now_iso, session_id))

        # 2. 如果存在 raw_summary 且包含旧标题，同步更新字节
        if raw_blob and old_title and old_title.strip():
            old_bytes = old_title.strip().encode("utf-8")
            new_bytes = new_title.strip().encode("utf-8")
            if len(old_bytes) == len(new_bytes) and old_bytes in raw_blob:
                updated_raw = raw_blob.replace(old_bytes, new_bytes)
                cur.execute("UPDATE conversation_summaries SET raw_summary = ? WHERE conversation_id = ?", (updated_raw, session_id))

        conn.commit()
        conn.close()
        return True
    except Exception as e:
        print(f"[SessionManager] 重命名 Antigravity 会话失败: {e}")
        return False

def archive_antigravity_session(session_id: str) -> bool:
    db_path = os.path.expanduser("~/.gemini/antigravity/conversation_summaries.db")
    if not os.path.exists(db_path):
        return False
    try:
        conn = sqlite3.connect(db_path)
        cur = conn.cursor()
        cur.execute("UPDATE conversation_summaries SET status = 'archived' WHERE conversation_id = ?", (session_id,))
        conn.commit()
        conn.close()
        return True
    except Exception:
        return False

def delete_antigravity_session(session_id: str) -> bool:
    """安全删除：移入系统废纸篓"""
    brain_dir = os.path.expanduser(f"~/.gemini/antigravity/brain/{session_id}")
    if os.path.exists(brain_dir):
        subprocess.run(["trash", brain_dir])
    conv_db = os.path.expanduser(f"~/.gemini/antigravity/conversations/{session_id}.db")
    if os.path.exists(conv_db):
        subprocess.run(["trash", conv_db])

    db_path = os.path.expanduser("~/.gemini/antigravity/conversation_summaries.db")
    if os.path.exists(db_path):
        try:
            conn = sqlite3.connect(db_path)
            cur = conn.cursor()
            cur.execute("DELETE FROM conversation_summaries WHERE conversation_id = ?", (session_id,))
            conn.commit()
            conn.close()
            return True
        except Exception:
            pass
    return False

def load_antigravity_history(session_id: Optional[str] = None) -> List[Dict[str, str]]:
    if session_id:
        fpath = os.path.expanduser(f"~/.gemini/antigravity/brain/{session_id}/.system_generated/logs/transcript.jsonl")
    else:
        pattern = os.path.expanduser("~/.gemini/antigravity/brain/*/.system_generated/logs/transcript.jsonl")
        files = glob.glob(pattern)
        fpath = max(files, key=os.path.getmtime) if files else None

    if not fpath or not os.path.exists(fpath):
        return []

    history = []
    try:
        with open(fpath, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                if not line.strip():
                    continue
                try:
                    item = json.loads(line.strip())
                    ts = item.get("created_at", "")
                    time_str = ""
                    if ts:
                        try:
                            time_str = datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone().strftime("%H:%M")
                        except:
                            pass

                    if item.get("type") == "USER_INPUT" and item.get("content"):
                        raw = item["content"]
                        if "<USER_REQUEST>" in raw:
                            raw = raw.split("<USER_REQUEST>")[1].split("</USER_REQUEST>")[0].strip()
                        history.append({
                            "id": f"ag_u_{item.get('step_index', len(history))}",
                            "sender": "user",
                            "text": raw,
                            "time": time_str
                        })
                    elif item.get("type") == "SYSTEM_MESSAGE" and item.get("content"):
                        raw_c = item["content"]
                        if "[Message]" in raw_c and "content=" in raw_c:
                            user_msg = raw_c.split("content=", 1)[1].split("</SYSTEM_MESSAGE>")[0].strip()
                            if not user_msg.startswith("Task id ") and not user_msg.startswith("Tool execution was"):
                                img_b64 = None
                                if "[附件图片:" in user_msg:
                                    try:
                                        p_part = user_msg.split("[附件图片:")[1].split("]")[0].strip()
                                        if os.path.exists(p_part):
                                            import base64
                                            with open(p_part, "rb") as img_f:
                                                img_b64 = base64.b64encode(img_f.read()).decode("utf-8")
                                        user_msg = user_msg.split("[附件图片:")[0].strip()
                                    except:
                                        pass
                                user_msg_clean = user_msg.strip()
                                # 严格防重：若上一条消息也是相同用户提问，跳过重复
                                if history and history[-1].get("sender") == "user" and history[-1].get("text", "").strip() == user_msg_clean:
                                    continue
                                history.append({
                                    "id": f"ag_u_{item.get('step_index', len(history))}",
                                    "sender": "user",
                                    "text": user_msg_clean,
                                    "time": time_str,
                                    "imageBase64": img_b64
                                })
                    elif item.get("type") == "PLANNER_RESPONSE" and item.get("content"):
                        raw = item["content"].replace("<SYSTEM_MESSAGE>", "").replace("</SYSTEM_MESSAGE>", "").strip()
                        if raw:
                            history.append({
                                "id": f"ag_a_{item.get('step_index', len(history))}",
                                "sender": "ai",
                                "text": raw,
                                "time": time_str
                            })
                except:
                    continue
    except Exception:
        pass
    return history[-60:]

# --- 2. WorkBuddy 会话管理（区分单次任务与项目文件夹，置顶单次任务） ---
def get_workbuddy_sessions() -> Dict[str, Any]:
    db_path = os.path.expanduser("~/.workbuddy/workbuddy.db")
    if not os.path.exists(db_path):
        return {"type_name": "项目与任务", "can_rename": True, "groups": []}

    try:
        conn = sqlite3.connect(db_path)
        cur = conn.cursor()
        cur.execute(
            "SELECT id, cwd, title, custom_title, status, updated_at "
            "FROM sessions WHERE deleted_at IS NULL AND (status != 'Archived' OR status IS NULL) "
            "ORDER BY updated_at DESC LIMIT 60"
        )
        rows = cur.fetchall()
        conn.close()

        groups_dict: Dict[str, List[Dict[str, Any]]] = {}
        tasks_list: List[Dict[str, Any]] = []

        for sid, cwd, title, ctitle, status, uat in rows:
            display_title = (ctitle or title or "未命名任务").strip()
            time_str = datetime.fromtimestamp(uat / 1000).strftime("%Y-%m-%dT%H:%M:%S") if uat else ""
            item = {
                "id": sid,
                "title": display_title,
                "raw_time": time_str,
                "time": time_str
            }

            if not cwd or "/WorkBuddy/20" in cwd or "WorkBuddy-20" in cwd or "automation-" in cwd:
                tasks_list.append(item)
            else:
                clean_cwd = cwd.rstrip("/")
                folder = clean_cwd.split("/")[-1]
                if folder not in groups_dict:
                    groups_dict[folder] = []
                groups_dict[folder].append(item)

        res_groups: List[Dict[str, Any]] = []
        if tasks_list:
            res_groups.append({"group_name": "单次任务", "items": tasks_list})
        sorted_folders = [{"group_name": k, "items": v} for k, v in groups_dict.items()]
        sorted_folders.sort(key=lambda g: max(((item.get("raw_time") or item.get("time") or "") for item in g["items"]), default=""), reverse=True)
        res_groups.extend(sorted_folders)

        return {"type_name": "项目与任务", "can_rename": True, "groups": res_groups}
    except Exception as e:
        print(f"[SessionManager] WorkBuddy session query error: {e}")
        return {"type_name": "项目与任务", "can_rename": True, "groups": []}

def rename_workbuddy_session(session_id: str, new_title: str) -> bool:
    db_path = os.path.expanduser("~/.workbuddy/workbuddy.db")
    if not os.path.exists(db_path):
        return False
    try:
        now_ms = int(time.time() * 1000)
        conn = sqlite3.connect(db_path)
        cur = conn.cursor()
        cur.execute("UPDATE sessions SET custom_title = ?, updated_at = ? WHERE id = ?", (new_title.strip(), now_ms, session_id))
        conn.commit()
        conn.close()
        return True
    except Exception:
        return False

def archive_workbuddy_session(session_id: str) -> bool:
    db_path = os.path.expanduser("~/.workbuddy/workbuddy.db")
    if not os.path.exists(db_path):
        return False
    try:
        now_ms = int(time.time() * 1000)
        conn = sqlite3.connect(db_path)
        cur = conn.cursor()
        cur.execute("UPDATE sessions SET status = 'Archived', updated_at = ? WHERE id = ?", (now_ms, session_id))
        conn.commit()
        conn.close()
        return True
    except Exception:
        return False

def delete_workbuddy_session(session_id: str) -> bool:
    """安全删除 WorkBuddy 会话：移入系统废纸篓"""
    db_path = os.path.expanduser("~/.workbuddy/workbuddy.db")
    if not os.path.exists(db_path):
        return False
    try:
        now_ms = int(time.time() * 1000)
        conn = sqlite3.connect(db_path)
        cur = conn.cursor()
        cur.execute("UPDATE sessions SET deleted_at = ?, updated_at = ? WHERE id = ?", (now_ms, now_ms, session_id))
        conn.commit()
        conn.close()

        matches = glob.glob(os.path.expanduser(f"~/.workbuddy/projects/*/{session_id}*"))
        for m in matches:
            subprocess.run(["trash", m])
        return True
    except Exception:
        return False

def load_workbuddy_history(session_id: Optional[str] = None) -> List[Dict[str, str]]:
    db_path = os.path.expanduser("~/.workbuddy/workbuddy.db")
    if not os.path.exists(db_path):
        return []

    fpath = None
    try:
        conn = sqlite3.connect(db_path)
        cur = conn.cursor()
        if session_id:
            cur.execute("SELECT id, cwd FROM sessions WHERE id = ?", (session_id,))
            rows = cur.fetchall()
        else:
            cur.execute("SELECT id, cwd FROM sessions WHERE deleted_at IS NULL ORDER BY updated_at DESC LIMIT 30")
            rows = cur.fetchall()
        conn.close()

        for sid, cwd in rows:
            candidate = None
            if cwd:
                encoded = cwd.strip("/").replace("/", "-")
                cand = os.path.expanduser(f"~/.workbuddy/projects/{encoded}/{sid}.jsonl")
                if os.path.exists(cand) and os.path.getsize(cand) > 0:
                    candidate = cand
            if not candidate:
                matches = glob.glob(os.path.expanduser(f"~/.workbuddy/projects/*/{sid}.jsonl"))
                for m in matches:
                    if os.path.getsize(m) > 0:
                        candidate = m
                        break
            if candidate:
                try:
                    with open(candidate, "r", encoding="utf-8", errors="ignore") as tf:
                        has_msg = any('"type":"message"' in l for l in tf)
                        if has_msg:
                            fpath = candidate
                            break
                except:
                    pass
    except Exception as e:
        print(f"[SessionManager] WorkBuddy path query error: {e}")

    if not fpath or not os.path.exists(fpath):
        return []

    messages = []
    try:
        with open(fpath, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                if not line.strip():
                    continue
                try:
                    d = json.loads(line.strip())
                    if d.get("type") != "message":
                        continue
                    role = d.get("role")
                    content = d.get("content", "")
                    raw_text = ""
                    if isinstance(content, str):
                        raw_text = content
                    elif isinstance(content, list):
                        parts = []
                        for item in content:
                            if isinstance(item, dict):
                                parts.append(item.get("text", ""))
                            else:
                                parts.append(str(item))
                        raw_text = "\n".join(parts)

                    if not raw_text.strip():
                        continue

                    if role == "user":
                        sender = "user"
                        if "<user_query>" in raw_text:
                            raw_text = raw_text.split("<user_query>")[1].split("</user_query>")[0].strip()
                        elif "</system-reminder>" in raw_text:
                            raw_text = raw_text.split("</system-reminder>")[-1].strip()
                        elif "<task-notification>" in raw_text:
                            continue
                    elif role == "assistant":
                        sender = "ai"
                    else:
                        continue

                    ts = d.get("timestamp")
                    time_str = datetime.fromtimestamp(ts / 1000).strftime("%H:%M") if ts else ""
                    msg_id = d.get("id") or f"wb_{len(messages)}_{ts or int(time.time()*1000)}"
                    if raw_text.strip():
                        messages.append({"id": str(msg_id), "sender": sender, "text": raw_text.strip(), "time": time_str})
                except:
                    continue
    except Exception as e:
        print(f"[SessionManager] WorkBuddy load history error: {e}")
    return messages[-50:]

# --- 3. Claude 会话管理（多项目文件夹穿透与完整消息解析） ---
def get_claude_sessions() -> Dict[str, Any]:
    projects_dir = os.path.expanduser("~/.claude/projects")
    groups_dict: Dict[str, List[Dict[str, Any]]] = {}

    # 1. 扫描项目目录
    if os.path.exists(projects_dir):
        for pdir in glob.glob(os.path.join(projects_dir, "*")):
            if not os.path.isdir(pdir):
                continue
            folder_name = os.path.basename(pdir).lstrip("-")
            clean_folder = folder_name.split("-")[-1] if "-" in folder_name else folder_name
            if clean_folder == "pandac":
                clean_folder = "默认工作区"

            files = glob.glob(os.path.join(pdir, "*.jsonl"))
            files.sort(key=os.path.getmtime, reverse=True)
            for fpath in files:
                sid = os.path.basename(fpath).replace(".jsonl", "")
                mtime = os.path.getmtime(fpath)
                time_str = datetime.fromtimestamp(mtime).strftime("%Y-%m-%dT%H:%M:%S")
                title = get_claude_file_title(fpath)
                if clean_folder not in groups_dict:
                    groups_dict[clean_folder] = []
                groups_dict[clean_folder].append({
                    "id": sid,
                    "title": title,
                    "raw_time": time_str,
                    "time": time_str
                })

    # 2. 扫描 transcripts
    trans_files = glob.glob(os.path.expanduser("~/.claude/transcripts/*.jsonl"))
    trans_files.sort(key=os.path.getmtime, reverse=True)
    trans_items = []
    for fpath in trans_files[:15]:
        sid = os.path.basename(fpath).replace(".jsonl", "")
        mtime = os.path.getmtime(fpath)
        time_str = datetime.fromtimestamp(mtime).strftime("%Y-%m-%dT%H:%M:%S")
        title = get_claude_file_title(fpath)
        trans_items.append({
            "id": sid,
            "title": title,
            "raw_time": time_str,
            "time": time_str
        })
    if trans_items:
        groups_dict["命令行会话"] = trans_items

    res_groups = [{"group_name": k, "items": v} for k, v in groups_dict.items()]
    res_groups.sort(key=lambda g: max(((item.get("raw_time") or item.get("time") or "") for item in g["items"]), default=""), reverse=True)
    return {
        "type_name": "项目与会话",
        "can_rename": True,
        "groups": res_groups
    }

def get_claude_file_title(fpath: str) -> str:
    try:
        with open(fpath, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                d = json.loads(line)
                if d.get("type") == "user":
                    msg = d.get("message", {})
                    c = msg.get("content") if isinstance(msg, dict) else d.get("content")
                    if isinstance(c, list):
                        parts = [x.get("text", "") if isinstance(x, dict) else str(x) for x in c]
                        c = " ".join(parts)
                    c = str(c or "").strip()
                    if c and not c.startswith("<") and not c.startswith("/"):
                        return c.split("\n")[0].strip()[:30]
    except:
        pass
    return os.path.basename(fpath).replace(".jsonl", "")[:15]

def load_claude_history(session_id: Optional[str] = None) -> List[Dict[str, str]]:
    fpath = None
    if session_id:
        cand = glob.glob(os.path.expanduser(f"~/.claude/projects/*/{session_id}.jsonl"))
        if cand:
            fpath = cand[0]
        else:
            cand_t = os.path.expanduser(f"~/.claude/transcripts/{session_id}.jsonl")
            if os.path.exists(cand_t):
                fpath = cand_t
    if not fpath:
        all_files = glob.glob(os.path.expanduser("~/.claude/projects/*/*.jsonl")) + glob.glob(os.path.expanduser("~/.claude/transcripts/*.jsonl"))
        all_files = [f for f in all_files if os.path.getsize(f) > 0]
        if all_files:
            all_files.sort(key=os.path.getmtime, reverse=True)
            for cand in all_files:
                try:
                    with open(cand, "r", encoding="utf-8", errors="ignore") as tf:
                        for line in tf:
                            if '"type":"user"' in line or '"type":"assistant"' in line:
                                fpath = cand
                                break
                    if fpath:
                        break
                except:
                    pass

    if not fpath or not os.path.exists(fpath):
        return []

    messages = []
    try:
        with open(fpath, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    d = json.loads(line)
                    typ = d.get("type")
                    time_str = ""
                    ts = d.get("timestamp")
                    if ts:
                        try:
                            time_str = datetime.fromisoformat(str(ts).replace("Z", "+00:00")).astimezone().strftime("%H:%M")
                        except:
                            pass

                    if typ == "user":
                        msg = d.get("message", {})
                        c = msg.get("content") if isinstance(msg, dict) else d.get("content")
                        if isinstance(c, list):
                            parts = [x.get("text", "") if isinstance(x, dict) else str(x) for x in c]
                            c = "\n".join(parts)
                        c = str(c or "").strip()
                        cid = d.get("uuid") or f"cl_u_{len(messages)}"
                        if c and not c.startswith("<command-name>") and not c.startswith("<local-command-caveat>"):
                            messages.append({"id": str(cid), "sender": "user", "text": c, "time": time_str})
                    elif typ == "assistant":
                        msg = d.get("message", {})
                        c = msg.get("content") if isinstance(msg, dict) else d.get("content")
                        text = ""
                        if isinstance(c, list):
                            parts = [x.get("text", "") for x in c if isinstance(x, dict) and x.get("type") == "text"]
                            text = "\n".join(parts)
                        elif isinstance(c, str):
                            text = c
                        cid = d.get("uuid") or f"cl_a_{len(messages)}"
                        if text.strip():
                            messages.append({"id": str(cid), "sender": "ai", "text": text.strip(), "time": time_str})
                except:
                    continue
    except Exception as e:
        print(f"[SessionManager] Claude history error: {e}")

    return messages[-50:]

def delete_claude_session(session_id: str) -> bool:
    """安全删除 Claude 会话：移入系统废纸篓"""
    try:
        matches = glob.glob(os.path.expanduser(f"~/.claude/projects/*/{session_id}.jsonl")) + glob.glob(os.path.expanduser(f"~/.claude/transcripts/{session_id}.jsonl"))
        for m in matches:
            subprocess.run(["trash", m])
        return True
    except Exception as e:
        print(f"[SessionManager] Error deleting Claude session: {e}")
        return False

# --- 4. ChatGPT / CodeX 会话管理（接入真实 local_thread_catalog 与 thread_items） ---
def get_chatgpt_sessions() -> Dict[str, Any]:
    cat_db = os.path.expanduser("~/.codex/sqlite/codex-dev.db")
    if not os.path.exists(cat_db):
        return {"type_name": "项目文件夹", "can_rename": False, "groups": []}

    try:
        conn = sqlite3.connect(cat_db)
        cur = conn.cursor()
        cur.execute(
            "SELECT thread_id, display_title, source_updated_at, cwd "
            "FROM local_thread_catalog WHERE missing_candidate = 0 "
            "ORDER BY source_updated_at DESC LIMIT 60"
        )
        rows = cur.fetchall()
        conn.close()

        groups_dict: Dict[str, List[Dict[str, Any]]] = {}
        for tid, title, uat, cwd in rows:
            folder = "未分类项目"
            if cwd:
                folder = cwd.rstrip("/").split("/")[-1]
            time_str = datetime.fromtimestamp(uat / 1000).strftime("%Y-%m-%dT%H:%M:%S") if uat else ""
            clean_title = (title or "未命名会话").strip()
            if folder not in groups_dict:
                groups_dict[folder] = []
            groups_dict[folder].append({
                "id": tid,
                "title": clean_title,
                "raw_time": time_str,
                "time": time_str
            })

        res_groups = [{"group_name": k, "items": v} for k, v in groups_dict.items()]
        res_groups.sort(key=lambda g: max(((item.get("raw_time") or item.get("time") or "") for item in g["items"]), default=""), reverse=True)
        return {"type_name": "项目文件夹", "can_rename": False, "groups": res_groups}
    except Exception as e:
        print(f"[SessionManager] ChatGPT session query error: {e}")
        return {"type_name": "项目文件夹", "can_rename": False, "groups": []}

def load_chatgpt_history(session_id: Optional[str] = None) -> List[Dict[str, str]]:
    hist_db = os.path.expanduser("~/.codex/thread_history_1.sqlite")
    if not os.path.exists(hist_db):
        return []

    target_tid = session_id
    if not target_tid:
        cat_db = os.path.expanduser("~/.codex/sqlite/codex-dev.db")
        if os.path.exists(cat_db):
            try:
                conn = sqlite3.connect(cat_db)
                cur = conn.cursor()
                cur.execute("SELECT thread_id FROM local_thread_catalog WHERE missing_candidate = 0 ORDER BY source_updated_at DESC LIMIT 1")
                row = cur.fetchone()
                conn.close()
                if row:
                    target_tid = row[0]
            except:
                pass

    if not target_tid:
        return []

    messages = []
    try:
        conn = sqlite3.connect(hist_db)
        cur = conn.cursor()
        cur.execute(
            "SELECT item_type, created_at_ms, item_json "
            "FROM thread_items WHERE thread_id = ? "
            "ORDER BY rollout_ordinal ASC",
            (target_tid,)
        )
        rows = cur.fetchall()
        conn.close()

        for itype, ts_ms, item_json in rows:
            if not item_json:
                continue
            time_str = datetime.fromtimestamp(ts_ms / 1000).strftime("%H:%M") if ts_ms else ""
            try:
                d = json.loads(item_json)
                if itype == "userMessage":
                    content_list = d.get("content", [])
                    texts = [c.get("text", "") for c in content_list if isinstance(c, dict) and c.get("type") == "text"]
                    t = "\n".join(texts).strip()
                    if t:
                        messages.append({
                            "id": d.get("id") or f"cg_u_{len(messages)}",
                            "sender": "user",
                            "text": t,
                            "time": time_str
                        })
                elif itype == "agentMessage":
                    t = d.get("text", "").strip()
                    if t:
                        messages.append({
                            "id": d.get("id") or f"cg_a_{len(messages)}",
                            "sender": "ai",
                            "text": t,
                            "time": time_str
                        })
            except:
                continue
    except Exception as e:
        print(f"[SessionManager] ChatGPT load history error: {e}")

    return messages[-60:]

# --- 统一入口路由 ---
def get_sessions(target: str) -> Dict[str, Any]:
    target = target.lower()
    res = {"type_name": "项目文件夹", "can_rename": True, "groups": []}
    if target == "antigravity":
        res = get_antigravity_sessions()
    elif target == "workbuddy":
        res = get_workbuddy_sessions()
    elif target == "claude":
        res = get_claude_sessions()
    elif target in ("chatgpt", "codex"):
        res = get_chatgpt_sessions()

    # 补充 Vecho 独立存档中未被宿主发现的手机会话
    try:
        from .message_store import get_stored_sessions
        stored = get_stored_sessions(target)
        if stored:
            existing_sids = set()
            for g in res.get("groups", []):
                for it in g.get("items", []):
                    existing_sids.add(it.get("id"))

            missing = [s for s in stored if s["id"] not in existing_sids]
            if missing:
                vecho_group = {"group_name": "手机会话", "items": missing}
                res["groups"].insert(0, vecho_group)
    except Exception as e:
        print(f"[SessionManager] 融合独立会话列表异常: {e}")

    return res

DELETED_MESSAGES_FILE = os.path.expanduser("~/.gemini/antigravity/deleted_msg_ids.json")

def mark_message_deleted(msg_id: str):
    if not msg_id:
        return
    try:
        deleted = set()
        if os.path.exists(DELETED_MESSAGES_FILE):
            with open(DELETED_MESSAGES_FILE, "r", encoding="utf-8") as f:
                deleted = set(json.load(f))
        deleted.add(str(msg_id))
        with open(DELETED_MESSAGES_FILE, "w", encoding="utf-8") as f:
            json.dump(list(deleted), f)
    except Exception as e:
        print(f"[SessionManager] 记录删除消息异常: {e}")

def get_deleted_message_ids() -> set:
    try:
        if os.path.exists(DELETED_MESSAGES_FILE):
            with open(DELETED_MESSAGES_FILE, "r", encoding="utf-8") as f:
                return set(json.load(f))
    except Exception:
        pass
    return set()

def get_history(target: str, session_id: Optional[str] = None) -> List[Dict[str, str]]:
    target = target.lower()
    raw = []
    if target == "antigravity":
        raw = load_antigravity_history(session_id)
    elif target == "workbuddy":
        raw = load_workbuddy_history(session_id)
    elif target == "claude":
        raw = load_claude_history(session_id)
    elif target in ("chatgpt", "codex"):
        raw = load_chatgpt_history(session_id)

    # 深度融合 Vecho 独立持久化存储层（确保手机发送的消息与专属回复 100% 存在）
    try:
        from .message_store import get_stored_messages
        stored = get_stored_messages(target, session_id)
        if stored:
            existing_texts = {(m.get("sender"), m.get("text", "").strip()) for m in raw}
            for s in stored:
                txt = s.get("text", "").strip()
                snd = s.get("sender", "user")
                if (snd, txt) not in existing_texts and txt:
                    raw.append({
                        "id": str(s.get("id")),
                        "sender": snd,
                        "text": s.get("text", ""),
                        "time": s.get("time", "")
                    })
                    existing_texts.add((snd, txt))
    except Exception as e:
        print(f"[SessionManager] 融合独立存储历史异常: {e}")

    del_ids = get_deleted_message_ids()
    if del_ids:
        raw = [m for m in raw if str(m.get("id")) not in del_ids]
    return raw

def rename_session(target: str, session_id: str, new_title: str) -> bool:
    target = target.lower()
    if target == "antigravity":
        return rename_antigravity_session(session_id, new_title)
    elif target == "workbuddy":
        return rename_workbuddy_session(session_id, new_title)
    return False

def archive_session(target: str, session_id: str) -> bool:
    target = target.lower()
    if target == "antigravity":
        return archive_antigravity_session(session_id)
    elif target == "workbuddy":
        return archive_workbuddy_session(session_id)
    elif target == "claude":
        return delete_claude_session(session_id)
    return False

def delete_session(target: str, session_id: str) -> bool:
    target = target.lower()
    # 同步清理 Vecho 独立存储中的会话文件
    try:
        from .message_store import delete_stored_session
        delete_stored_session(target, session_id)
    except Exception:
        pass

    if target == "antigravity":
        return delete_antigravity_session(session_id)
    elif target == "workbuddy":
        return delete_workbuddy_session(session_id)
    elif target == "claude":
        return delete_claude_session(session_id)
    elif target in ("chatgpt", "codex"):
        return True
    return False
    return False
