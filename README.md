# Vecho (维触) - 随身 AI 智能体协同控制台

Vecho 是一款专为 Mac 与移动端打造的统一 AI 智能体随身控制中心。通过本地低延迟常驻网关（WebSocket / REST），在手机端实时掌控 Mac 上运行的各大主流 AI 开发智能体。

---

## ⚡️ 极速一键安装 (macOS)

在 Mac 终端中运行以下命令，即可全自动完成源码拉取、依赖安装与系统开机自启常驻配置：

```bash
git clone https://github.com/neopandat/vecho.git ~/.vecho && bash ~/.vecho/install.sh
```

安装完成后，终端会显示你的物理局域网 IP 与端口号（默认 `31188`），直接在手机端 Vecho App 中输入即可秒级连通。

---

## 🌟 核心特性

- **多智能体统一路由**：无缝聚合调度 Antigravity、Claude、WorkBuddy、Trae、Qoder、DeepSeek 等主流智能体；
- **全双工实时推流**：基于原生 WebSocket 长连接，实现毫秒级打字机式流式消息响应；
- **远程一键唤醒**：在手机端一键唤起 Mac 端尚未运行的智能体应用，并感知其生命周期；
- **原生多模态输入**：支持高清长图、拍照与截图传输，智能体自动解析图像上下文；
- **系统级常驻守护**：基于 macOS 原生 `launchctl` 守护进程，后台静默常驻，重启不掉线；
- **原生 SwiftUI 交互**：专为 iOS 深度定制的流式界面、手势互斥与震动反馈。

---

## 🛠 手动启动与调试

若需手动调试服务端，可在进入项目目录后执行：

```bash
# 安装 Python 依赖
pip3 install -r requirements.txt

# 启动控制台网关
python3 backend/server.py
```

或双击根目录下的 `启动控制台.command` 脚本。

---

## 📄 开源许可

本项目遵循 MIT 许可证。
