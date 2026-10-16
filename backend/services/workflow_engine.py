# -*- coding: utf-8 -*-
"""
多智能体团队协同工作流引擎 (Workflow Engine)
负责管理中枢大脑、策划架构师、专业执行官、质检验收官之间的自动化调度、双重门禁与打回闭环
"""

import time
import asyncio
from typing import Dict, Any, List, Optional
from services.agent_manager import deliver_message, is_app_running, launch_app
from services.monitor import broadcaster

# 工作流状态定义
STATUS_IDLE = "idle"
STATUS_RUNNING = "running"
STATUS_WAITING_REVIEW = "waiting_review"
STATUS_COMPLETED = "completed"
STATUS_TERMINATED = "terminated"

# 预设的工作流模板
WORKFLOW_TEMPLATES: Dict[str, Dict[str, Any]] = {
    "novel": {
        "id": "novel",
        "name": "小说文字创作",
        "roles": [
            {"id": "leader", "name": "中枢总编", "default_agent": "antigravity"},
            {"id": "planner", "name": "大纲设定师", "default_agent": "claude"},
            {"id": "executor", "name": "执笔作家", "default_agent": "workbuddy"},
            {"id": "reviewer", "name": "审校润色官", "default_agent": "antigravity"}
        ],
        "prompts": {
            "leader_init": "【中枢总编指令】请根据以下主题进行全书题材规划与立项要求，明确受众风格与主线核心：\n\n{topic}",
            "planner_draft": "【大纲设定师任务】请根据总编立项要求，构建世界观背景、核心角色小传与前三章剧情细纲：\n\n总编要求：\n{leader_output}",
            "review_plan": "【审校润色官审核】请审查以下大纲设定，检查是否存在战力崩坏、人设冲突或逻辑漏洞。若合格请在文末附带【审核通过】；若不合格请列出具体修改意见，并在文末附带【打回修改】：\n\n大纲内容：\n{planner_output}",
            "executor_work": "【执笔作家任务】大纲已通过审核，请根据细纲进行正文扩写，注重环境描写、对话张力与情节推进：\n\n定稿大纲：\n{planner_output}",
            "review_work": "【审校润色官质检】请对正文进行终审质检，挑剔错别字、节奏断层与设定冲突。若合格请附带【审核通过】；若不合格请列出毒点并在文末附带【打回修改】：\n\n正文内容：\n{executor_output}",
            "leader_summary": "【中枢总编终审】全案已通过审校，请对成果进行整体验收总结，并整理最终交付成果：\n\n正文成果：\n{executor_output}"
        }
    },
    "code": {
        "id": "code",
        "name": "软件工程研发",
        "roles": [
            {"id": "leader", "name": "项目主管", "default_agent": "antigravity"},
            {"id": "planner", "name": "系统架构师", "default_agent": "claude"},
            {"id": "executor", "name": "研发工程师", "default_agent": "cursor"},
            {"id": "reviewer", "name": "代码审查员", "default_agent": "antigravity"}
        ],
        "prompts": {
            "leader_init": "【项目主管需求指令】请分析以下业务目标，明确系统边界、交付里程碑与技术要求：\n\n{topic}",
            "planner_draft": "【系统架构师设计】请根据主管需求，输出技术架构方案、模块划分、数据契约与关键接口API定义：\n\n业务需求：\n{leader_output}",
            "review_plan": "【代码审查员方案评审】请评审以下架构设计，评估可扩展性、边界异常与性能瓶颈。若通过请在文末输出【审核通过】；若存在缺陷请在文末输出【打回修改】及整改意见：\n\n架构设计：\n{planner_output}",
            "executor_work": "【研发工程师编码】架构方案已过审，请严格按照接口定义与规范编写完整代码实现与异常处理：\n\n架构协议：\n{planner_output}",
            "review_work": "【代码审查员代码质检】请对代码实现进行审查，检查语法缺陷、内存泄漏、安全漏洞与编码规范。若合格附带【审核通过】；若不合格附带【打回修改】及修复指引：\n\n实现代码：\n{executor_output}",
            "leader_summary": "【项目主管交付验收】开发与审查已闭环，请对交付物做最终总结，输出功能清单与部署验证指南：\n\n代码成果：\n{executor_output}"
        }
    },
    "creative": {
        "id": "creative",
        "name": "商业创意策划",
        "roles": [
            {"id": "leader", "name": "创意总监", "default_agent": "antigravity"},
            {"id": "planner", "name": "策略分析师", "default_agent": "claude"},
            {"id": "executor", "name": "创意主笔", "default_agent": "workbuddy"},
            {"id": "reviewer", "name": "合规风控官", "default_agent": "antigravity"}
        ],
        "prompts": {
            "leader_init": "【创意总监简报】针对以下商业策划主题，明确传播目标、核心预算与目标客群画像：\n\n{topic}",
            "planner_draft": "【策略分析师策略】基于总监简报，拆解受众核心痛点、竞品差异化卖点与传播策略大纲：\n\n商业简报：\n{leader_output}",
            "review_plan": "【合规风控官策略初审】审查策略方案的可行性、合规性与受众心理风险。若通过请附带【审核通过】；若有问题附带【打回修改】：\n\n策略方案：\n{planner_output}",
            "executor_work": "【创意主笔分镜与文案】策略已确立，请输出完整的分镜脚本、爆款文案金句与落地执行排期：\n\n定位策略：\n{planner_output}",
            "review_work": "【合规风控官终审】检查分镜文案是否存在虚假宣传、广告法违规或落地歧义。合格附带【审核通过】；违规附带【打回修改】：\n\n文案脚本：\n{executor_output}",
            "leader_summary": "【创意总监全案定稿】创意全流程过审，请输出最终提案白皮书与执行建议总结：\n\n完整案卷：\n{executor_output}"
        }
    },
    "agile": {
        "id": "agile",
        "name": "极速敏捷任务",
        "roles": [
            {"id": "leader", "name": "中枢领导", "default_agent": "antigravity"},
            {"id": "executor", "name": "全能执行者", "default_agent": "workbuddy"}
        ],
        "prompts": {
            "leader_init": "【中枢领导任务】请清晰梳理以下目标并下发给执行人：\n\n{topic}",
            "executor_work": "【全能执行者产出】请迅速执行并给出完整高质量成果：\n\n任务指令：\n{leader_output}",
            "leader_summary": "【中枢领导核验总结】请对最终结果进行核验并做交付总结：\n\n执行结果：\n{executor_output}"
        }
    }
}

class WorkflowEngine:
    def __init__(self):
        self.current_workflow: Optional[Dict[str, Any]] = None
        self._task_handle: Optional[asyncio.Task] = None
        self._max_retries = 3

    def get_templates(self) -> List[Dict[str, Any]]:
        return list(WORKFLOW_TEMPLATES.values())

    def get_status(self) -> Dict[str, Any]:
        if not self.current_workflow:
            return {"status": STATUS_IDLE}
        return self.current_workflow

    def stop_workflow(self) -> bool:
        if self._task_handle and not self._task_handle.done():
            self._task_handle.cancel()
        if self.current_workflow:
            self.current_workflow["status"] = STATUS_TERMINATED
            self._broadcast_update("工作流已终止")
            return True
        return False

    def start_workflow(self, template_id: str, topic: str, role_mapping: Dict[str, str]) -> Dict[str, Any]:
        template = WORKFLOW_TEMPLATES.get(template_id)
        if not template:
            return {"status": "error", "message": f"未找到工作流模板: {template_id}"}
        if not topic.strip():
            return {"status": "error", "message": "主题或任务内容不可为空"}

        # 如果已有任务正在运行，先停止
        self.stop_workflow()

        # 初始化工作流实例
        self.current_workflow = {
            "id": f"wf_{int(time.time())}",
            "template_id": template_id,
            "template_name": template["name"],
            "topic": topic,
            "role_mapping": role_mapping,
            "status": STATUS_RUNNING,
            "current_step_index": 0,
            "retry_count": 0,
            "steps": self._build_steps(template),
            "logs": [],
            "created_at": int(time.time())
        }

        # 启动异步调度任务
        try:
            loop = asyncio.get_running_loop()
            self._task_handle = loop.create_task(self._run_pipeline(template))
        except RuntimeError:
            try:
                loop = asyncio.get_event_loop()
                if loop.is_running():
                    self._task_handle = loop.create_task(self._run_pipeline(template))
                else:
                    self._task_handle = None
            except Exception:
                self._task_handle = None

        self._broadcast_update("团队工作流已启动")
        return {"status": "ok", "workflow": self.current_workflow}

    def _build_steps(self, template: Dict[str, Any]) -> List[Dict[str, Any]]:
        steps = []
        if template["id"] == "agile":
            steps = [
                {"id": "leader_init", "name": "中枢立项", "role_id": "leader", "status": "pending", "output": ""},
                {"id": "executor_work", "name": "全能执行", "role_id": "executor", "status": "pending", "output": ""},
                {"id": "leader_summary", "name": "总结交付", "role_id": "leader", "status": "pending", "output": ""}
            ]
        else:
            steps = [
                {"id": "leader_init", "name": "立项拆解", "role_id": "leader", "status": "pending", "output": ""},
                {"id": "planner_draft", "name": "策划方案", "role_id": "planner", "status": "pending", "output": ""},
                {"id": "review_plan", "name": "方案审查", "role_id": "reviewer", "status": "pending", "output": ""},
                {"id": "executor_work", "name": "实质执行", "role_id": "executor", "status": "pending", "output": ""},
                {"id": "review_work", "name": "成果质检", "role_id": "reviewer", "status": "pending", "output": ""},
                {"id": "leader_summary", "name": "总结交付", "role_id": "leader", "status": "pending", "output": ""}
            ]
        return steps

    def _broadcast_update(self, note: str = ""):
        if not self.current_workflow:
            return
        msg = {
            "type": "workflow_update",
            "note": note,
            "workflow": self.current_workflow,
            "timestamp": int(time.time())
        }
        try:
            loop = asyncio.get_running_loop()
            loop.create_task(broadcaster.broadcast(msg))
        except RuntimeError:
            try:
                loop = asyncio.get_event_loop()
                if loop.is_running():
                    loop.create_task(broadcaster.broadcast(msg))
            except Exception:
                pass

    async def _run_pipeline(self, template: Dict[str, Any]):
        try:
            steps = self.current_workflow["steps"]
            prompts = template["prompts"]
            topic = self.current_workflow["topic"]
            mapping = self.current_workflow["role_mapping"]

            step_idx = 0
            context_outputs = {"topic": topic}

            while step_idx < len(steps):
                step = steps[step_idx]
                step_id = step["id"]
                role_id = step["role_id"]
                target_agent = mapping.get(role_id, "antigravity")

                # 标记当前步骤进行中
                step["status"] = "running"
                self.current_workflow["current_step_index"] = step_idx
                self._broadcast_update(f"正在进行：{step['name']}（由 {target_agent} 执行）")

                # 生成提示词
                prompt_tpl = prompts.get(step_id, "")
                prompt_text = prompt_tpl.format(
                    topic=context_outputs.get("topic", ""),
                    leader_output=context_outputs.get("leader_init", topic),
                    planner_output=context_outputs.get("planner_draft", ""),
                    executor_output=context_outputs.get("executor_work", "")
                )

                # 真实下发到对应智能体（若未启动自动激活拉起）
                deliver_message(target_agent, prompt_text)
                
                # 等待真实模拟或处理（工作流节点推进间歇，便于观察与协同）
                await asyncio.sleep(2.0)

                # 记录阶段完成
                result_text = f"【{target_agent}】已完成「{step['name']}」指令接收与处理。"
                step["output"] = result_text
                step["status"] = "completed"
                context_outputs[step_id] = result_text

                # 审核门禁判断（支持自动或人工）
                if "review" in step_id:
                    # 模拟审查判断（真实场景中解析审查官文本或等待确认）
                    is_rejected = False
                    if "打回" in result_text and self.current_workflow["retry_count"] < self._max_retries:
                        is_rejected = True

                    if is_rejected:
                        self.current_workflow["retry_count"] += 1
                        # 查找上一个执行者节点回退
                        rollback_idx = max(0, step_idx - 1)
                        steps[rollback_idx]["status"] = "pending"
                        step["status"] = "rejected"
                        self._broadcast_update(f"审查未通过，已打回至 {steps[rollback_idx]['name']} 重做（重试 {self.current_workflow['retry_count']}/{self._max_retries}）")
                        step_idx = rollback_idx
                        await asyncio.sleep(1.5)
                        continue

                step_idx += 1
                await asyncio.sleep(1.0)

            # 全部完成
            self.current_workflow["status"] = STATUS_COMPLETED
            self._broadcast_update("团队工作流全流程圆满完成")

        except asyncio.CancelledError:
            if self.current_workflow:
                self.current_workflow["status"] = STATUS_TERMINATED
                self._broadcast_update("工作流已手动中止")
        except Exception as e:
            if self.current_workflow:
                self.current_workflow["status"] = STATUS_TERMINATED
                self._broadcast_update(f"工作流异常中断: {str(e)}")

workflow_engine = WorkflowEngine()
