# -*- coding: utf-8 -*-
"""
AI 编码工具用量统计服务 (Usage Service)
提供真实一手 Token 消耗、缓存命中率、分时段分布、分工具及项目 Treemap 数据
纯本地、零上传、100% 真实数据，秒级响应（内存与磁盘双重缓存 + 异步增量采集）
"""

import os
import sys
import json
import time
import threading
import subprocess
from typing import Dict, Any, Optional

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA_DIR = os.path.join(PROJECT_ROOT, ".data")
LOCAL_USAGE_DISK = os.path.join(DATA_DIR, "usage-cache.json")

# 工作台同源数据源与采集器路径
WORKBENCH_ROOT = "/Users/pandac/工作/项目/工作台"
WORKBENCH_USAGE_DISK = os.path.join(WORKBENCH_ROOT, ".data", "usage-cache.json")
WORKBENCH_COLLECTOR_SCRIPT = os.path.join(WORKBENCH_ROOT, "scripts", "usage_collector.py")

_USAGE_TTL = 60          # 60 秒内复用内存缓存
_USAGE_TIMEOUT = 180     # 采集超时限制
_usage_lock = threading.Lock()
_usage_busy = threading.Event()
_usage_cache: Dict[str, Any] = {"ts": 0.0, "data": None}


def _load_disk_cache():
    """启动时优先加载磁盘缓存，秒级冷启动，绝不阻塞用户界面"""
    global _usage_cache
    for disk_path in (LOCAL_USAGE_DISK, WORKBENCH_USAGE_DISK):
        if os.path.exists(disk_path):
            try:
                with open(disk_path, "r", encoding="utf-8") as f:
                    content = json.load(f)
                if isinstance(content, dict):
                    # 兼容结构 {"ok": true, "data": {...}, "ts": ...} 或直接是 data
                    data = content.get("data") if ("ok" in content and "data" in content) else content
                    ts = float(content.get("ts", time.time()))
                    with _usage_lock:
                        _usage_cache["data"] = {"ok": True, "data": data}
                        _usage_cache["ts"] = ts
                    return
            except Exception as e:
                print(f"[UsageService] 读取磁盘缓存失败 ({disk_path}): {e}")


def _save_disk_cache(data: Dict[str, Any], ts: float):
    """持久化缓存到当前项目的 .data/usage-cache.json"""
    try:
        os.makedirs(DATA_DIR, exist_ok=True)
        tmp_path = LOCAL_USAGE_DISK + ".tmp"
        with open(tmp_path, "w", encoding="utf-8") as f:
            json.dump({"ok": True, "data": data, "ts": ts}, f, ensure_ascii=False)
        os.replace(tmp_path, LOCAL_USAGE_DISK)
    except Exception as e:
        print(f"[UsageService] 保存磁盘缓存失败: {e}")


def _run_collector() -> Optional[Dict[str, Any]]:
    """调用本地真实用量采集器提取全量数据"""
    collector_py = sys.executable or "/usr/local/bin/python3"
    script_path = WORKBENCH_COLLECTOR_SCRIPT
    if not os.path.exists(script_path):
        # 如果未找到工作台脚本，尝试从本项目 scripts 中寻找
        alt_path = os.path.join(PROJECT_ROOT, "scripts", "usage_collector.py")
        if os.path.exists(alt_path):
            script_path = alt_path
        else:
            print(f"[UsageService] 未找到用量采集脚本: {script_path}")
            return None

    try:
        env = os.environ.copy()
        res = subprocess.run(
            [collector_py, script_path],
            capture_output=True,
            text=True,
            timeout=_USAGE_TIMEOUT,
            env=env
        )
        if res.returncode == 0 and res.stdout.strip():
            return json.loads(res.stdout)
        else:
            print(f"[UsageService] 采集脚本报错: {res.stderr[:200]}")
            return None
    except Exception as e:
        print(f"[UsageService] 执行采集异常: {e}")
        return None


def collect_usage_task():
    """后台采集工作线程"""
    if _usage_busy.is_set():
        return
    _usage_busy.set()
    try:
        data = _run_collector()
        if data:
            now = time.time()
            with _usage_lock:
                _usage_cache["data"] = {"ok": True, "data": data}
                _usage_cache["ts"] = now
            _save_disk_cache(data, now)
    finally:
        _usage_busy.clear()


def get_usage(force_refresh: bool = False) -> Dict[str, Any]:
    """
    对外提供用量数据：
    优先返回内存/磁盘好数据，过期或强制时在后台静默刷新，永远不卡住接口
    """
    with _usage_lock:
        cached = _usage_cache["data"]
        age = time.time() - _usage_cache["ts"]

    if force_refresh or age >= _USAGE_TTL:
        if not _usage_busy.is_set():
            threading.Thread(target=collect_usage_task, daemon=True).start()

    if cached is not None:
        return cached

    # 第一次没有缓存时，尝试先直接执行一次
    collect_usage_task()
    with _usage_lock:
        if _usage_cache["data"] is not None:
            return _usage_cache["data"]

    return {"ok": False, "error": "用量统计初始化中，请稍后重试"}


# 模块加载时预热磁盘缓存
_load_disk_cache()
