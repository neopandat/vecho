import SwiftUI

public struct AgentOption: Identifiable, Codable, Equatable {
    public let id: String
    public let name: String
    public let description: String
    public let installed: Bool
    public var isSelected: Bool

    public init(id: String, name: String, description: String, installed: Bool, isSelected: Bool) {
        self.id = id
        self.name = name
        self.description = description
        self.installed = installed
        self.isSelected = isSelected
    }
}

public struct OnboardingView: View {
    @Binding public var isPresented: Bool
    @Binding public var enabledAgentIds: [String]
    @Binding public var onlyShowAgentIcons: Bool
    @Binding public var serverHost: String
    @Binding public var serverPort: Int

    @State private var currentStep: Int = 1
    @State private var inputHost: String = ""
    @State private var inputPortString: String = "31188"
    @State private var isConnecting: Bool = false
    @State private var connectionSuccess: Bool = false
    @State private var connectionError: String? = nil
    @State private var hasCopiedPrompt: Bool = false
    @State private var showingScriptDetail: Bool = false

    private let agentPromptText: String = """
请帮我将 Vecho 智能网关配置为 Mac 系统常驻服务（端口 31188）：
1. 在终端执行一键安装启动命令：
   git clone https://github.com/neopandat/vecho.git ~/.vecho && bash ~/.vecho/install.sh
   （如果电脑本地已有 Vecho 目录，可直接执行：python3 scripts/install_launchagent.py）
2. 运行完成后获取物理 Wi-Fi 局域网 IP（ipconfig getifaddr en0）；
3. 请直接回复告知我：
   「电脑 IP 请填：<你的局域网IP>，服务端口请填：31188」，以便我在手机 Vecho App 中填入连接。
"""

    @State private var agentOptions: [AgentOption] = [
        AgentOption(id: "antigravity", name: "Antigravity", description: "Google 全能开发智能体", installed: true, isSelected: true),
        AgentOption(id: "workbuddy", name: "WorkBuddy", description: "自动化工作智能体", installed: true, isSelected: true),
        AgentOption(id: "claude", name: "Claude", description: "Anthropic 智能体", installed: true, isSelected: true),
        AgentOption(id: "chatgpt", name: "ChatGPT", description: "OpenAI 官方客户端", installed: true, isSelected: true),
        AgentOption(id: "trae", name: "Trae", description: "字节跳动 AI 原生开发工具", installed: false, isSelected: true),
        AgentOption(id: "qoder", name: "Qoder", description: "通义灵码 AI 原生开发工具", installed: false, isSelected: true),
        AgentOption(id: "deepseek", name: "DeepSeek", description: "深度求索代码与推理智能体", installed: false, isSelected: true),
        AgentOption(id: "cursor", name: "Cursor", description: "AI 辅助编程编辑器", installed: false, isSelected: false),
        AgentOption(id: "windsurf", name: "Windsurf", description: "智能编程智能体", installed: false, isSelected: false),
        AgentOption(id: "cline", name: "Cline", description: "自主编程智能体", installed: false, isSelected: false),
        AgentOption(id: "aider", name: "Aider", description: "终端结对编程智能体", installed: false, isSelected: false),
        AgentOption(id: "copilot", name: "Copilot", description: "GitHub 编程助手", installed: false, isSelected: false)
    ]

    public init(
        isPresented: Binding<Bool>,
        enabledAgentIds: Binding<[String]>,
        onlyShowAgentIcons: Binding<Bool>,
        serverHost: Binding<String>,
        serverPort: Binding<Int>
    ) {
        self._isPresented = isPresented
        self._enabledAgentIds = enabledAgentIds
        self._onlyShowAgentIcons = onlyShowAgentIcons
        self._serverHost = serverHost
        self._serverPort = serverPort
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                DesignTokens.Colors.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // 分段切换导航栏
                    Picker("", selection: $currentStep) {
                        Text("智能体与偏好").tag(2)
                        Text("连接配置").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, DesignTokens.Spacing.xl)
                    .padding(.top, DesignTokens.Spacing.md)
                    .padding(.bottom, DesignTokens.Spacing.xs)

                    if currentStep == 1 {
                        stepOneConnectView
                    } else {
                        stepTwoSelectAgentsView
                    }

                    Spacer()

                    // 底部主按钮
                    bottomActionBar
                }
            }
            .navigationTitle(currentStep == 1 ? "连接配置" : "设置与智能体")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !enabledAgentIds.isEmpty {
                        Button("关闭") {
                            isPresented = false
                        }
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                    }
                }
            }
            .onAppear {
                inputHost = serverHost.isEmpty ? "192.168.31.188" : serverHost
                inputPortString = String(serverPort)
                syncEnabledOptions()
                // 若已配置好服务器，进入设置时默认展示偏好与智能体配置
                if !serverHost.isEmpty {
                    currentStep = 2
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // 步骤一：配置与测试连接
    private var stepOneConnectView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                // 一键复制指令发给本地 Agent
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("让 Mac 智能体启动服务")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)

                        Spacer()

                        Button {
                            UIPasteboard.general.string = agentPromptText
                            hasCopiedPrompt = true
                            DesignTokens.Haptics.medium()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: hasCopiedPrompt ? "checkmark.circle.fill" : "doc.on.doc")
                                Text(hasCopiedPrompt ? "已复制" : "复制指令")
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(hasCopiedPrompt ? DesignTokens.Colors.success : DesignTokens.Colors.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(DesignTokens.Colors.cardActive)
                            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                        }
                        .buttonStyle(.plain)
                        .frame(minHeight: 44)
                    }

                    // 完整显示指令，绝不截断
                    Text(agentPromptText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(white: 0.9))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(red: 20/255, green: 20/255, blue: 22/255))
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))

                    // 守护脚本详情折叠展开
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingScriptDetail.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showingScriptDetail ? "chevron.down" : "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                            Text(showingScriptDetail ? "收起守护脚本原理" : "守护脚本在哪里？如何手动运行？")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(DesignTokens.Colors.accent)
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)

                    if showingScriptDetail {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("• 开源仓库：https://github.com/neopandat/vecho.git（新电脑终端执行 bash ~/.vecho/install.sh 即可自动部署）。")
                            Text("• 脚本位置：位于 Mac 电脑 Vecho 项目根目录下的 scripts/install_launchagent.py。")
                            Text("• 核心原理：通过 macOS 原生 launchctl 将 backend/server.py 注册为系统级后台守护（~/Library/LaunchAgents/com.pandac.vecho.plist），监听 31188 端口，实现开机自启与进程守护。")
                            Text("• 手动启动：也可以直接在 Mac 终端进入 Vecho 目录，执行 python3 backend/server.py 或双击「启动控制台.command」直接运行。")
                        }
                        .font(.system(size: 11))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                        .padding(10)
                        .background(Color(red: 24/255, green: 24/255, blue: 28/255))
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                        .transition(.opacity)
                    }
                }
                .padding(12)
                .background(DesignTokens.Colors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                .padding(.top, DesignTokens.Spacing.sm)

                // 填写指引提示卡片
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(DesignTokens.Colors.accent)
                        .padding(.top, 2)
                    Text("将上方指令发送给 Mac 智能体，智能体执行后会告诉你电脑 IP。将该 IP 填入下方，服务端口保持 31188，点击「测试连接」即可。")
                        .font(.system(size: 12))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                        .lineSpacing(2)
                }
                .padding(10)
                .background(Color(red: 18/255, green: 22/255, blue: 30/255))
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))

                // 输入区
                VStack(spacing: DesignTokens.Spacing.md) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("电脑 IP / 域名")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                            Text("填内网 IP 或公网域名")
                                .font(.system(size: 10))
                                .foregroundColor(DesignTokens.Colors.textSecondary)
                        }
                        .frame(width: 90, alignment: .leading)

                        TextField("如 192.168.31.188 或域名", text: $inputHost)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .frame(height: 42)
                            .background(Color(red: 28/255, green: 28/255, blue: 30/255))
                            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                            .foregroundColor(.white)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("服务端口")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                            Text("固定默认 31188")
                                .font(.system(size: 10))
                                .foregroundColor(DesignTokens.Colors.textSecondary)
                        }
                        .frame(width: 90, alignment: .leading)

                        TextField("默认 31188", text: $inputPortString)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .frame(height: 42)
                            .background(Color(red: 28/255, green: 28/255, blue: 30/255))
                            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                            .foregroundColor(.white)
                            .keyboardType(.numberPad)
                    }
                }
                .padding(12)
                .background(DesignTokens.Colors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))

                // 测试连接操作与状态提示
                Button {
                    testConnection()
                } label: {
                    HStack {
                        if isConnecting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: connectionSuccess ? "checkmark.circle.fill" : "network")
                        }
                        Text(connectionSuccess ? "连接成功" : "测试连接")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(connectionSuccess ? DesignTokens.Colors.success : DesignTokens.Colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                }
                .buttonStyle(.plain)

                if let err = connectionError {
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundColor(DesignTokens.Colors.danger)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .padding(.bottom, DesignTokens.Spacing.lg)
        }
    }

    // 步骤二：勾选启用的智能体
    private var stepTwoSelectAgentsView: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Toggle(isOn: $onlyShowAgentIcons) {
                Text("只显示Agent图标")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }
            .toggleStyle(SwitchToggleStyle(tint: DesignTokens.Colors.accent))
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, 10)
            .background(DesignTokens.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .padding(.top, DesignTokens.Spacing.md)

            Text("勾选需要在主控台显示的智能体")
                .font(.system(size: 14))
                .foregroundColor(DesignTokens.Colors.textSecondary)
                .padding(.horizontal, DesignTokens.Spacing.xl)
                .padding(.top, DesignTokens.Spacing.xs)

            List {
                ForEach($agentOptions) { $option in
                    Button {
                        DesignTokens.Haptics.selection()
                        option.isSelected.toggle()
                    } label: {
                        HStack(spacing: DesignTokens.Spacing.md) {
                            Image(systemName: option.isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundColor(option.isSelected ? DesignTokens.Colors.accent : DesignTokens.Colors.textSecondary)

                            AgentIconView(target: option.id, size: 24)

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(option.name)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.white)

                                    if option.installed {
                                        Text("已安装")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(DesignTokens.Colors.success)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(DesignTokens.Colors.success.opacity(0.15))
                                            .clipShape(Capsule())
                                    }
                                }

                                Text(option.description)
                                    .font(.system(size: 12))
                                    .foregroundColor(DesignTokens.Colors.textSecondary)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(DesignTokens.Colors.cardBackground)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
    }

    // 底部控制操作栏
    private var bottomActionBar: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            if currentStep > 1 {
                Button {
                    currentStep -= 1
                } label: {
                    Text("上一步")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(DesignTokens.Colors.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
                }
                .buttonStyle(.plain)
            }

            Button {
                handleNextOrFinish()
            } label: {
                Text(currentStep == 1 ? "下一步" : "开始使用")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(DesignTokens.Colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.bottom, DesignTokens.Spacing.lg)
    }

    private func syncEnabledOptions() {
        if enabledAgentIds.isEmpty {
            enabledAgentIds = ["antigravity", "workbuddy", "claude", "chatgpt", "trae", "qoder", "deepseek"]
        }
        for i in 0..<agentOptions.count {
            agentOptions[i].isSelected = enabledAgentIds.contains(agentOptions[i].id)
        }
    }

    private func testConnection() {
        let cleanHost = inputHost.trimmingCharacters(in: .whitespaces)
        let port = Int(inputPortString) ?? 31188
        guard !cleanHost.isEmpty else {
            connectionError = "请输入有效的 IP 或域名"
            return
        }

        isConnecting = true
        connectionError = nil
        connectionSuccess = false

        let urlString: String
        let trimmed = cleanHost
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            let base = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
            urlString = "\(base)/api/agent_discovery"
        } else if trimmed.contains(".") && !trimmed.contains(":") && !trimmed.allSatisfy({ $0.isNumber || $0 == "." }) {
            urlString = "https://\(trimmed)/api/agent_discovery"
        } else {
            urlString = "http://\(trimmed):\(port)/api/agent_discovery"
        }

        guard let url = URL(string: urlString) else {
            isConnecting = false
            connectionError = "URL 格式不合法"
            return
        }

        Task {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 5.0
                let (data, response) = try await URLSession.shared.data(for: request)
                if (response as? HTTPURLResponse)?.statusCode == 200 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let agentList = json["agents"] as? [[String: Any]] {
                        await MainActor.run {
                            self.serverHost = cleanHost
                            self.serverPort = port
                            self.connectionSuccess = true
                            self.isConnecting = false

                            // 更新已安装状态
                            for remote in agentList {
                                if let rid = remote["id"] as? String,
                                   let installed = remote["installed"] as? Bool {
                                    if let idx = self.agentOptions.firstIndex(where: { $0.id == rid }) {
                                        self.agentOptions[idx] = AgentOption(
                                            id: rid,
                                            name: self.agentOptions[idx].name,
                                            description: self.agentOptions[idx].description,
                                            installed: installed,
                                            isSelected: self.agentOptions[idx].isSelected
                                        )
                                    }
                                }
                            }
                        }
                        return
                    }
                }
                throw URLError(.cannotConnectToHost)
            } catch {
                await MainActor.run {
                    self.connectionError = "无法连接，请确认电脑已启动服务且处于同一 Wi-Fi"
                    self.isConnecting = false
                    self.connectionSuccess = false
                }
            }
        }
    }

    private func handleNextOrFinish() {
        if currentStep == 1 {
            let cleanHost = inputHost.trimmingCharacters(in: .whitespaces)
            let port = Int(inputPortString) ?? 31188
            serverHost = cleanHost.isEmpty ? "192.168.31.188" : cleanHost
            serverPort = port
            currentStep = 2
        } else {
            let selected = agentOptions.filter { $0.isSelected }.map { $0.id }
            enabledAgentIds = selected.isEmpty ? ["antigravity"] : selected
            isPresented = false
        }
    }
}
