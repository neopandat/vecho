# -*- coding: utf-8 -*-
"""
统一多智能体控制台服务端 (FastAPI + WebSocket)
提供低延迟 WebSocket 长连接全双工通信、REST API、静态网页托管及后台日志推流
"""

import os
import sys
import asyncio
from typing import Optional
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Query
from fastapi.responses import JSONResponse, FileResponse
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import uvicorn

from services.agent_manager import is_app_running, launch_app, deliver_message, discover_installed_agents, get_lan_ip, trigger_new_session
from services.media_handler import process_and_deliver_media
from services.session_manager import (
    get_sessions,
    get_history,
    rename_session,
    archive_session,
    delete_session,
    mark_message_deleted
)
from services.monitor import broadcaster, monitor_antigravity_loop
from services.workflow_engine import workflow_engine
from services.usage_service import get_usage
from services.tunnel_service import tunnel_manager

app = FastAPI(title="Vecho Gateway", version="2.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WEB_DIR = os.path.join(PROJECT_ROOT, "web")

# --- 请求数据模型 ---
class MultimodalPayload(BaseModel):
    target: str = "antigravity"
    session_id: Optional[str] = None
    message: Optional[str] = ""
    text: Optional[str] = None
    image_base64: Optional[str] = None
    file_base64: Optional[str] = None
    file_name: Optional[str] = None

class ActionPayload(BaseModel):
    target: str = "antigravity"
    session_id: Optional[str] = None
    new_title: Optional[str] = None

class WorkflowStartPayload(BaseModel):
    template_id: str = "novel"
    topic: str = ""
    role_mapping: Optional[dict] = None

# --- 生命周期事件 ---
@app.on_event("startup")
async def on_startup():
    print("[Server] Gateway started. Launching monitor tasks...")
    broadcaster.loop = asyncio.get_running_loop()
    asyncio.create_task(monitor_antigravity_loop())

# --- WebSocket 端点（长连接核心通道） ---
@app.websocket("/ws")
async def websocket_endpoint(ws: WebSocket):
    await ws.accept()
    broadcaster.register(ws)
    try:
        # 发送握手成功报文与当前状态
        await ws.send_json({
            "type": "connected",
            "message": "已成功连接至控制台网关",
            "timestamp": int(asyncio.get_event_loop().time())
        })
        while True:
            data = await ws.receive_json()
            event_type = data.get("type", "ping")
            
            if event_type == "ping":
                await ws.send_json({"type": "pong"})

            elif event_type == "send":
                target = data.get("target", "antigravity")
                session_id = data.get("session_id")
                msg = data.get("message") or data.get("text") or ""
                img_b64 = data.get("image_base64")
                file_b64 = data.get("file_base64")
                file_name = data.get("file_name")

                success, result = process_and_deliver_media(
                    target=target,
                    message=msg,
                    session_id=session_id,
                    image_base64=img_b64,
                    file_base64=file_b64,
                    file_name=file_name
                )
                await ws.send_json({
                    "type": "send_ack",
                    "status": "ok" if success else "failed",
                    "detail": result
                })

            elif event_type == "get_status":
                target = data.get("target", "antigravity")
                running = is_app_running(target)
                await ws.send_json({
                    "type": "status",
                    "target": target,
                    "running": running
                })

            elif event_type == "workflow_get_status":
                await ws.send_json({
                    "type": "workflow_status_res",
                    "data": workflow_engine.get_status()
                })

            elif event_type == "workflow_start":
                tid = data.get("template_id", "novel")
                top = data.get("topic", "")
                rm = data.get("role_mapping", {})
                res = workflow_engine.start_workflow(tid, top, rm)
                await ws.send_json({
                    "type": "workflow_start_res",
                    "result": res
                })

            elif event_type == "workflow_stop":
                res = workflow_engine.stop_workflow()
                await ws.send_json({
                    "type": "workflow_stop_res",
                    "success": res
                })

            elif event_type == "get_usage":
                force = bool(data.get("force", False))
                res = get_usage(force_refresh=force)
                await ws.send_json({
                    "type": "usage_res",
                    "data": res
                })

            elif event_type == "delete_message":
                msg_id = str(data.get("message_id", ""))
                target = data.get("target", "")
                session_id = data.get("session_id", "")
                if msg_id:
                    # 1. 持久化记录到已删除黑名单，确保护照/拉取历史时彻底过滤
                    mark_message_deleted(msg_id)
                    # 2. 从内存最近列表中移除
                    for k in broadcaster.recent_messages:
                        broadcaster.recent_messages[k] = [m for m in broadcaster.recent_messages[k] if str(m.get("id")) != msg_id]
                    # 3. 向所有客户端广播同步删除事件
                    await broadcaster.broadcast({
                        "type": "message_deleted",
                        "message_id": msg_id,
                        "target": target,
                        "session_id": session_id
                    })

    except WebSocketDisconnect:
        broadcaster.unregister(ws)
    except Exception as e:
        broadcaster.unregister(ws)

# --- REST API 接口 ---
@app.get("/health")
async def health_check():
    return {"status": "ok", "service": "Vecho Gateway 2.0"}

@app.get("/api/sessions")
async def api_get_sessions(target: str = Query("antigravity")):
    return get_sessions(target)

@app.get("/api/history")
async def api_get_history(target: str = Query("antigravity"), session_id: Optional[str] = Query(None)):
    active_session_id = session_id
    if not active_session_id:
        sess_data = get_sessions(target)
        groups = sess_data.get("groups", [])
        if groups and groups[0].get("items"):
            active_session_id = groups[0]["items"][0].get("id")

    items = get_history(target, active_session_id)
    if active_session_id:
        for it in items:
            if not it.get("session_id"):
                it["session_id"] = active_session_id
    return items

@app.get("/api/agent_discovery")
async def api_agent_discovery():
    lan_ip = get_lan_ip()
    port = int(os.environ.get("PORT", 31188))
    agents = discover_installed_agents()
    tunnel_info = tunnel_manager.get_status()
    return {
        "server_ip": lan_ip,
        "server_port": port,
        "websocket_url": f"ws://{lan_ip}:{port}/ws",
        "tunnel_url": tunnel_info.get("public_url"),
        "tunnel_running": tunnel_info.get("running", False),
        "agents": agents
    }

@app.get("/api/tunnel/status")
async def api_tunnel_status():
    return tunnel_manager.get_status()

@app.post("/api/tunnel/start")
async def api_tunnel_start(token: Optional[str] = Query(None)):
    port = int(os.environ.get("PORT", 31188))
    return tunnel_manager.start_tunnel(port=port, token=token)

@app.post("/api/tunnel/stop")
async def api_tunnel_stop():
    return tunnel_manager.stop_tunnel()

@app.get("/api/app_status")
async def api_get_app_status(target: str = Query("antigravity")):
    return {"target": target, "running": is_app_running(target)}

@app.get("/api/all_app_status")
async def api_get_all_app_status():
    targets = ["antigravity", "workbuddy", "claude", "chatgpt", "trae", "qoder", "deepseek", "cursor", "windsurf"]
    return {t: is_app_running(t) for t in targets}

@app.post("/api/send")
@app.post("/api/send_multimodal")
async def api_send_multimodal(payload: MultimodalPayload):
    msg_content = payload.message or payload.text or ""
    success, detail = process_and_deliver_media(
        target=payload.target,
        message=msg_content,
        session_id=payload.session_id,
        image_base64=payload.image_base64,
        file_base64=payload.file_base64,
        file_name=payload.file_name
    )
    return JSONResponse(
        status_code=200 if success else 500,
        content={"status": "ok" if success else "failed", "detail": detail}
    )

@app.post("/api/launch_app")
async def api_launch_app(payload: ActionPayload):
    res = launch_app(payload.target)
    return {"status": "ok" if res else "failed"}

@app.post("/api/rename_session")
async def api_rename_session(payload: ActionPayload):
    if not payload.session_id or not payload.new_title:
        return JSONResponse(status_code=400, content={"status": "failed", "detail": "缺少必要参数"})
    res = rename_session(payload.target, payload.session_id, payload.new_title)
    return {"status": "ok" if res else "failed"}

@app.post("/api/archive_session")
async def api_archive_session(payload: ActionPayload):
    if not payload.session_id:
        return JSONResponse(status_code=400, content={"status": "failed", "detail": "缺少 session_id"})
    res = archive_session(payload.target, payload.session_id)
    return {"status": "ok" if res else "failed"}

@app.post("/api/delete_session")
async def api_delete_session(payload: ActionPayload):
    if not payload.session_id:
        return JSONResponse(status_code=400, content={"status": "failed", "detail": "缺少 session_id"})
    res = delete_session(payload.target, payload.session_id)
    return {"status": "ok" if res else "failed"}

class NewSessionPayload(BaseModel):
    target: str = "antigravity"
    project: Optional[str] = None

@app.post("/api/new_session")
async def api_new_session(payload: NewSessionPayload):
    res = trigger_new_session(payload.target, payload.project or "")
    return res

# --- 团队协同自动化工作流 API ---
@app.get("/api/workflow/templates")
async def api_get_workflow_templates():
    return workflow_engine.get_templates()

@app.get("/api/workflow/status")
async def api_get_workflow_status():
    return workflow_engine.get_status()

@app.post("/api/workflow/start")
async def api_start_workflow(payload: WorkflowStartPayload):
    mapping = payload.role_mapping or {}
    res = workflow_engine.start_workflow(payload.template_id, payload.topic, mapping)
    return res

@app.post("/api/workflow/stop")
async def api_stop_workflow():
    res = workflow_engine.stop_workflow()
    return {"status": "ok" if res else "failed"}

# --- AI 用量与统计 API ---
@app.get("/api/usage")
async def api_get_usage(force: bool = Query(False)):
    return get_usage(force_refresh=force)

@app.post("/api/usage/refresh")
async def api_refresh_usage():
    return get_usage(force_refresh=True)

# --- 静态资源托管（轻量 Web 控制台） ---
if os.path.exists(WEB_DIR):
    app.mount("/static", StaticFiles(directory=WEB_DIR), name="static")

@app.get("/")
async def serve_index():
    index_path = os.path.join(WEB_DIR, "index.html")
    if os.path.exists(index_path):
        return FileResponse(index_path)
    return JSONResponse(content={"message": "Web 控制台资源就绪中"})

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 31188))
    uvicorn.run("server:app", host="0.0.0.0", port=port, reload=False)
