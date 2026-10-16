import SwiftUI

public enum AppViewMode {
    case home
    case chat
    case stats
}

public struct ContentView: View {
    @StateObject private var wsService = WebSocketService.shared

    // 本地持久化配置
    @AppStorage("server_host") private var serverHost: String = "192.168.31.188"
    @AppStorage("server_port") private var serverPort: Int = 31188
    @AppStorage("has_completed_onboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("only_show_agent_icons") private var onlyShowAgentIcons: Bool = false
    @AppStorage("enabled_agents_data") private var enabledAgentsData: String = "[\"antigravity\",\"workbuddy\",\"claude\",\"chatgpt\",\"trae\",\"qoder\",\"deepseek\"]"

    // 页面流转模式：默认首页
    @State private var viewMode: AppViewMode = .home

    @State private var selectedTarget: String = "antigravity"
    @State private var selectedSessionId: String? = nil
    @State private var messages: [ChatMessage] = []
    @State private var sessionGroups: [SessionGroup] = []
    @State private var isTargetRunning: Bool = false
    @State private var isLaunchingApp: Bool = false
    @State private var isLoadingHistory: Bool = false
    @State private var isWaitingForResponse: Bool = false

    @State private var inputText: String = ""
    @State private var selectedImageBase64: String? = nil
    @State private var isDrawerOpen: Bool = false
    @State private var showingSettings: Bool = false
    @State private var enabledAgentIds: [String] = []
    @State private var agentRunningMap: [String: Bool] = [:]

    public init() {}

    public var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()

            Group {
                switch viewMode {
                case .home:
                    HomeView(
                        selectedTarget: $selectedTarget,
                        showingSettings: $showingSettings,
                        enabledAgentIds: enabledAgentIds,
                        serverHost: serverHost,
                        serverPort: serverPort,
                        isConnected: wsService.isConnected,
                        onEnterChat: { target in
                            let targetChanged = (selectedTarget != target)
                            selectedTarget = target
                            if !targetChanged {
                                loadCurrentTargetData()
                            }
                            withAnimation(.easeInOut(duration: 0.25)) {
                                viewMode = .chat
                            }
                        },
                        onEnterStats: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                viewMode = .stats
                            }
                        }
                    )
                    .transition(.opacity)

                case .stats:
                    UsageStatsView(showBackButton: true, onBack: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            viewMode = .home
                        }
                    })
                    .transition(.opacity)

                case .chat:
                    chatWorkspaceView
                        .transition(.opacity)
                }
            }

            // 侧边抽屉浮层（全局浮层，在任何界面右滑均可拉出）
            if isDrawerOpen {
                // 深度毛玻璃模糊 + 高不透明度暗黑遮罩（彻底打散并遮盖底层，杜绝视觉干扰）
                ZStack {
                    Rectangle()
                        .fill(.ultraThickMaterial)
                        .ignoresSafeArea()

                    Color.black.opacity(0.85)
                        .ignoresSafeArea()
                }
                .transition(.opacity)
                .onTapGesture {
                    DesignTokens.Haptics.light()
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isDrawerOpen = false
                    }
                }

                HStack(spacing: 0) {
                    SessionDrawerView(
                        target: selectedTarget,
                        isRunning: isTargetRunning,
                        groups: sessionGroups,
                        selectedSessionId: $selectedSessionId,
                        onClose: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isDrawerOpen = false
                            }
                        },
                        onSelectSession: { sid in
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isDrawerOpen = false
                                viewMode = .chat // 若在其他界面，选出会话后自动切进对话
                            }
                            loadHistory(for: selectedTarget, sessionId: sid)
                        },
                        onNewSession: { project in
                            handleNewSession(projectName: project)
                        },
                        onRefresh: {
                            refreshDrawer()
                        },
                        onLaunch: {
                            launchSelectedTarget()
                        }
                    )
                    .transition(.move(edge: .leading))

                    Spacer()
                }
                .gesture(
                    DragGesture(minimumDistance: 20)
                        .onEnded { value in
                            // 抽屉展开状态下向左滑收起抽屉
                            if value.translation.width < -40 && abs(value.translation.height) < abs(value.translation.width) * 0.75 {
                                DesignTokens.Haptics.light()
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    isDrawerOpen = false
                                }
                            }
                        }
                )
            }
        }
        .sheet(isPresented: $showingSettings, onDismiss: {
            saveEnabledAgents()
            reconnectServices()
        }) {
            OnboardingView(
                isPresented: $showingSettings,
                enabledAgentIds: $enabledAgentIds,
                onlyShowAgentIcons: $onlyShowAgentIcons,
                serverHost: $serverHost,
                serverPort: $serverPort
            )
        }
        .onAppear {
            loadSavedAgents()
            reconnectServices()
            if !hasCompletedOnboarding {
                showingSettings = true
                hasCompletedOnboarding = true
            }
        }
        .onChange(of: selectedTarget) { _, newTarget in
            if newTarget.lowercased() == "stats" {
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewMode = .stats
                }
                return
            }
            isTargetRunning = agentRunningMap[newTarget.lowercased()] ?? false
            selectedSessionId = nil
            messages = []
            isWaitingForResponse = false
            loadCurrentTargetData()
        }
        .onReceive(wsService.$receivedMessage) { newMsg in
            guard let msg = newMsg else { return }
            // 目标必须匹配当前 Agent
            if let msgTarget = msg.target, !msgTarget.isEmpty {
                guard msgTarget.lowercased() == selectedTarget.lowercased() else { return }
            }
            // 严格会话隔离：
            if let msgSessionId = msg.sessionId, !msgSessionId.isEmpty {
                if let curSessionId = selectedSessionId, !curSessionId.isEmpty {
                    // 已绑定会话：必须严格一致，杜绝跨会话串扰
                    guard msgSessionId == curSessionId else { return }
                } else {
                    // 当前处于「新建对话」状态（selectedSessionId 为 nil）：
                    // 若正在等待首条回复，收到的首条回复即为新会话的响应，自动绑定新 session_id 并刷新抽屉
                    if isWaitingForResponse {
                        self.selectedSessionId = msgSessionId
                        refreshDrawer()
                    } else {
                        return
                    }
                }
            }
            if msg.sender == "ai" || !msg.isUser {
                self.isWaitingForResponse = false
            }
            if !messages.contains(where: { $0.id == msg.id }) {
                messages.append(msg)
            }
        }
        .onReceive(wsService.$deletedMessageId) { delId in
            guard let id = delId, !id.isEmpty else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                messages.removeAll { $0.id == id }
            }
        }
        .task {
            while !Task.isCancelled {
                if let statusMap = try? await APIService.shared.fetchAllAppStatus() {
                    await MainActor.run {
                        self.agentRunningMap = statusMap
                        if let curRunning = statusMap[selectedTarget.lowercased()] {
                            self.isTargetRunning = curRunning
                        }
                    }
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    // MARK: - 对话工作区视图
    private var chatWorkspaceView: some View {
        VStack(spacing: 0) {
            // 顶部导航栏（左侧抽屉，中间智能体横滑，右上角返回首页，无齿轮与统计图标）
            HStack(spacing: DesignTokens.Spacing.sm) {
                // 左侧：抽屉按钮
                Button {
                    DesignTokens.Haptics.light()
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isDrawerOpen.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(DesignTokens.Colors.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                }
                .buttonStyle(.plain)
                .frame(minWidth: DesignTokens.Interaction.minTouchTarget, minHeight: DesignTokens.Interaction.minTouchTarget)

                // 中间：顶部智能体横滑切换条（严格排除统计图标与总调度）
                AgentBarView(
                    selectedTarget: $selectedTarget,
                    targets: (enabledAgentIds.isEmpty ? ["antigravity"] : enabledAgentIds).filter { $0.lowercased() != "stats" && $0.lowercased() != "master" },
                    onlyShowIcons: onlyShowAgentIcons,
                    showStatsTab: false,
                    agentRunningMap: agentRunningMap
                )

                // 右上角：返回首页按钮（房子图标）
                Button {
                    DesignTokens.Haptics.light()
                    withAnimation(.easeInOut(duration: 0.25)) {
                        viewMode = .home
                    }
                } label: {
                    Image(systemName: "house")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(DesignTokens.Colors.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                }
                .buttonStyle(.plain)
                .frame(minWidth: DesignTokens.Interaction.minTouchTarget, minHeight: DesignTokens.Interaction.minTouchTarget)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(Color(red: 16/255, green: 16/255, blue: 18/255))

            // 未启动状态提示与一键打开快捷栏
            if !isTargetRunning {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(white: 0.45))
                        .frame(width: 6, height: 6)
                    Text("\(DesignTokens.AgentVisuals.name(for: selectedTarget)) 未在电脑上启动")
                        .font(.system(size: 12))
                        .foregroundColor(DesignTokens.Colors.textSecondary)

                    Spacer()

                    Button {
                        DesignTokens.Haptics.medium()
                        launchSelectedTarget()
                    } label: {
                        Text("一键打开")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(DesignTokens.Colors.accent)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, 6)
                .background(Color(red: 22/255, green: 22/255, blue: 26/255))
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // 聊天对话流（支持长按复制与删除、唤起加载与自由选词）
            ChatView(
                messages: messages,
                isLoading: isLoadingHistory,
                isLaunching: isLaunchingApp,
                isWaitingForResponse: isWaitingForResponse,
                targetName: DesignTokens.AgentVisuals.name(for: selectedTarget),
                onDeleteMessage: handleDeleteMessage,
                onResendMessage: { text in
                    self.inputText = text
                }
            )

            // 底部输入栏（仿 ChatGPT/Gemini 1~8行自适应）
            InputBarView(
                text: $inputText,
                selectedImageBase64: $selectedImageBase64,
                onSend: { text, img in
                    handleSendMessage(text: text, img: img)
                }
            )
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if !isDrawerOpen {
                        // 仅在聊天窗口右滑呼出抽屉（避开顶部操作栏，防止与横滑Agent切换冲突）
                        if value.startLocation.y > 125 && value.translation.width > 50 && abs(value.translation.height) < abs(value.translation.width) * 0.75 {
                            DesignTokens.Haptics.light()
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isDrawerOpen = true
                            }
                        }
                    }
                }
        )
    }

    private func handleDeleteMessage(_ msg: ChatMessage) {
        withAnimation(.easeInOut(duration: 0.2)) {
            messages.removeAll { $0.id == msg.id }
            // 用户删除提问时，立即终止思考中动效，杜绝假动效残留
            self.isWaitingForResponse = false
        }
        wsService.sendDeleteMessage(messageId: msg.id, target: selectedTarget, sessionId: selectedSessionId)
    }

    private func reconnectServices() {
        APIService.shared.updateEndpoint(host: serverHost, port: serverPort)
        wsService.connect(host: serverHost, port: serverPort)
        loadCurrentTargetData()
    }

    private func loadSavedAgents() {
        if let data = enabledAgentsData.data(using: .utf8),
           let list = try? JSONDecoder().decode([String].self, from: data),
           !list.isEmpty {
            self.enabledAgentIds = list.filter { $0.lowercased() != "master" }
        } else {
            self.enabledAgentIds = ["antigravity", "workbuddy", "claude", "chatgpt", "trae", "qoder", "deepseek"]
        }
        if !enabledAgentIds.contains(selectedTarget), let first = enabledAgentIds.first {
            selectedTarget = first
        }
    }

    private func saveEnabledAgents() {
        if let data = try? JSONEncoder().encode(enabledAgentIds),
           let str = String(data: data, encoding: .utf8) {
            self.enabledAgentsData = str
        }
        if !enabledAgentIds.contains(selectedTarget), let first = enabledAgentIds.first {
            selectedTarget = first
        }
    }

    private func handleNewSession(projectName: String? = nil) {
        DesignTokens.Haptics.medium()
        withAnimation(.easeInOut(duration: 0.25)) {
            isDrawerOpen = false
            viewMode = .chat
        }
        self.selectedSessionId = nil
        self.messages = []
        self.isWaitingForResponse = false

        Task {
            let (ok, newId) = await APIService.shared.newSession(target: selectedTarget, project: projectName)
            await MainActor.run {
                if ok, let sid = newId, !sid.isEmpty {
                    self.selectedSessionId = sid
                }
            }
            try? await Task.sleep(nanoseconds: 600_000_000)
            refreshDrawer()
        }
    }

    private func handleSendMessage(text: String, img: String?) {
        let textToSend = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let imgToSend = img

        // 立即同步清空本地输入状态
        self.inputText = ""
        self.selectedImageBase64 = nil

        guard !textToSend.isEmpty || imgToSend != nil else { return }

        let userMsg = ChatMessage(target: selectedTarget, sessionId: selectedSessionId, sender: "user", text: textToSend, time: "", imageBase64: imgToSend)
        messages.append(userMsg)
        isWaitingForResponse = true

        // 单通道发送：优先使用已建立的 WebSocket，未连接时走 HTTP REST，彻底根除重复投递
        if wsService.isConnected {
            wsService.sendMessage(target: selectedTarget, sessionId: selectedSessionId, text: textToSend, imageBase64: imgToSend)
        } else {
            Task {
                _ = await APIService.shared.sendMessage(target: selectedTarget, sessionId: selectedSessionId, text: textToSend, imageBase64: imgToSend)
            }
        }

        if !isTargetRunning {
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                let running = try? await APIService.shared.fetchAppStatus(target: selectedTarget)
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.isTargetRunning = running ?? false
                    }
                }
            }
        }
    }

    private func launchSelectedTarget() {
        isLaunchingApp = true
        Task {
            _ = await APIService.shared.launchApp(target: selectedTarget)

            var isReady = false
            for _ in 0..<15 { // 最长轮询约 22 秒
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                let running = (try? await APIService.shared.fetchAppStatus(target: selectedTarget)) ?? false
                if running {
                    await MainActor.run {
                        self.isTargetRunning = true
                    }
                    do {
                        let res = try await APIService.shared.fetchSessions(target: selectedTarget)
                        if !res.groups.isEmpty {
                            await MainActor.run {
                                self.sessionGroups = res.groups
                            }
                            let targetSid = self.selectedSessionId ?? res.groups.first?.items.first?.id
                            if let sid = targetSid {
                                await MainActor.run {
                                    self.selectedSessionId = sid
                                }
                                let history = try await APIService.shared.fetchHistory(target: selectedTarget, sessionId: sid)
                                await MainActor.run {
                                    self.messages = history
                                    self.isWaitingForResponse = false
                                    isReady = true
                                }
                            } else {
                                isReady = true
                            }
                            if isReady { break }
                        }
                    } catch {
                        // 继续轮询等待就绪
                    }
                }
            }

            let finalRunning = (try? await APIService.shared.fetchAppStatus(target: selectedTarget)) ?? false
            await MainActor.run {
                self.isTargetRunning = finalRunning
                self.isLaunchingApp = false
            }
            if self.messages.isEmpty && self.sessionGroups.isEmpty {
                loadCurrentTargetData()
            }
        }
    }

    private func loadCurrentTargetData() {
        guard selectedTarget.lowercased() != "stats" else { return }
        isLoadingHistory = true
        Task {
            // 1. 获取会话列表并默认选中最新活跃窗口
            var targetSessionId: String? = self.selectedSessionId
            do {
                let res = try await APIService.shared.fetchSessions(target: selectedTarget)
                await MainActor.run {
                    self.sessionGroups = res.groups
                }
                if targetSessionId == nil {
                    targetSessionId = res.groups.first?.items.first?.id
                    await MainActor.run {
                        self.selectedSessionId = targetSessionId
                    }
                }
            } catch {
                await MainActor.run {
                    self.sessionGroups = []
                }
            }

            // 2. 加载该窗口的历史记录
            loadHistory(for: selectedTarget, sessionId: targetSessionId)

            // 3. 探测运行状态
            let running = try? await APIService.shared.fetchAppStatus(target: selectedTarget)
            await MainActor.run {
                let isRun = running ?? false
                self.isTargetRunning = isRun
                self.agentRunningMap[selectedTarget.lowercased()] = isRun
            }
        }
    }

    private func refreshDrawer() {
        Task {
            do {
                let res = try await APIService.shared.fetchSessions(target: selectedTarget)
                await MainActor.run {
                    self.sessionGroups = res.groups
                }
            } catch {
                await MainActor.run {
                    self.sessionGroups = []
                }
            }
        }
    }

    private func loadHistory(for target: String, sessionId: String?) {
        isLoadingHistory = true
        Task {
            do {
                let history = try await APIService.shared.fetchHistory(target: target, sessionId: sessionId)
                await MainActor.run {
                    // 若当前正在同一 target 和 session，且本地最新一条是刚发出的提问尚未写入后端，保留在最新末尾
                    if target == self.selectedTarget && sessionId == self.selectedSessionId {
                        if let lastLocal = self.messages.last, lastLocal.sender == "user" {
                            let exists = history.contains { $0.id == lastLocal.id || ($0.text == lastLocal.text && $0.sender == "user") }
                            if !exists {
                                var merged = history
                                merged.append(lastLocal)
                                self.messages = merged
                                if history.last?.sender == "ai" {
                                    self.isWaitingForResponse = false
                                }
                                self.isLoadingHistory = false
                                return
                            }
                        }
                    }
                    self.messages = history
                    if history.last?.sender == "ai" {
                        self.isWaitingForResponse = false
                    }
                    self.isLoadingHistory = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingHistory = false
                }
            }
        }
    }
}
