import SwiftUI

public struct HomeView: View {
    @Binding public var selectedTarget: String
    @Binding public var showingSettings: Bool
    public let enabledAgentIds: [String]
    public let serverHost: String
    public let serverPort: Int
    public let isConnected: Bool

    // 回调通知父级进入对话工作区
    public let onEnterChat: (String) -> Void
    // 回调通知父级进入统计大屏
    public let onEnterStats: () -> Void

    // 智能体运行状态缓存：target -> isRunning
    @State private var agentRunningMap: [String: Bool] = [:]
    @State private var isProbingStatus: Bool = false
    @State private var quickSummary: AggregatedUsageSummary? = nil

    public init(
        selectedTarget: Binding<String>,
        showingSettings: Binding<Bool>,
        enabledAgentIds: [String],
        serverHost: String,
        serverPort: Int,
        isConnected: Bool,
        onEnterChat: @escaping (String) -> Void,
        onEnterStats: @escaping () -> Void
    ) {
        self._selectedTarget = selectedTarget
        self._showingSettings = showingSettings
        self.enabledAgentIds = enabledAgentIds
        self.serverHost = serverHost
        self.serverPort = serverPort
        self.isConnected = isConnected
        self.onEnterChat = onEnterChat
        self.onEnterStats = onEnterStats
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 页面顶栏
                HStack {
                    HStack(spacing: 8) {
                        Image("logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        Text("控制中心")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    }

                    Spacer()

                    // 刷新状态与用量
                    Button {
                        DesignTokens.Haptics.light()
                        Task {
                            await probeAllAgentsStatus()
                            await loadQuickSummary()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(DesignTokens.Colors.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.top, DesignTokens.Spacing.sm)

                // 第一排：服务连接与概览卡片
                firstRowServerCard

                // 第二排：「对话」智能体调度与点亮唤醒卡片
                secondRowChatAgentsCard

                // 第三排：「用量统计」大屏入口卡片
                thirdRowStatsCard

                // 第四排：「系统设置」与智能体管理卡片
                fourthRowSettingsCard
            }
            .padding(.bottom, 32)
        }
        .background(DesignTokens.Colors.background)
        .task {
            await probeAllAgentsStatus()
            await loadQuickSummary()
        }
    }

    // MARK: - 第一排：服务连接状态卡片
    private var firstRowServerCard: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isConnected ? DesignTokens.Colors.success : DesignTokens.Colors.danger)
                .frame(width: 10, height: 10)
                .shadow(color: isConnected ? DesignTokens.Colors.success.opacity(0.6) : Color.clear, radius: 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(isConnected ? "控制台网关连接正常" : "未连接至网关服务")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)

                Text("\(serverHost):\(serverPort)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
            }

            Spacer()

            if let qs = quickSummary {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("累计消耗")
                        .font(.system(size: 9))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                    Text(AggregatedUsageSummary.formatCompactTokens(qs.total))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(DesignTokens.Colors.morandiPurple)
                }
            }
        }
        .padding(16)
        .background(DesignTokens.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .padding(.horizontal, DesignTokens.Spacing.md)
    }

    // MARK: - 第二排：「对话」智能体唤醒与入口卡片
    private var secondRowChatAgentsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 14))
                        .foregroundColor(DesignTokens.Colors.accent)
                    Text("对话")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }

                Spacer()

                Button {
                    DesignTokens.Haptics.light()
                    onEnterChat(selectedTarget)
                } label: {
                    HStack(spacing: 3) {
                        Text("进入会话")
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(DesignTokens.Colors.accent)
                }
                .buttonStyle(.plain)
            }

            // Agent 图标陈列排（高亮 = 打开；暗淡 = 未打开，点击唤醒）
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    let agents = enabledAgentIds.isEmpty ? ["antigravity", "workbuddy", "claude"] : enabledAgentIds
                    ForEach(agents, id: \.self) { agent in
                        let isRunning = agentRunningMap[agent.lowercased()] ?? false

                        Button {
                            DesignTokens.Haptics.medium()
                            handleAgentTap(agent: agent, isRunning: isRunning)
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    // 运行中的发光/圆环描边
                                    Circle()
                                        .stroke(
                                            isRunning ? DesignTokens.Colors.accent : Color(white: 0.22),
                                            lineWidth: isRunning ? 2 : 1
                                        )
                                        .frame(width: 46, height: 46)

                                    if isRunning {
                                        Circle()
                                            .fill(DesignTokens.Colors.accent.opacity(0.15))
                                            .frame(width: 44, height: 44)
                                    }

                                    AgentIconView(target: agent, size: 26)
                                        .saturation(isRunning ? 1.0 : 0.0)
                                        .opacity(isRunning ? 1.0 : 0.45)

                                    // 右下角状态微点
                                    VStack {
                                        Spacer()
                                        HStack {
                                            Spacer()
                                            Circle()
                                                .fill(isRunning ? DesignTokens.Colors.success : Color(white: 0.4))
                                                .frame(width: 8, height: 8)
                                                .overlay(
                                                    Circle()
                                                        .stroke(Color.black, lineWidth: 1.5)
                                                )
                                        }
                                    }
                                    .frame(width: 44, height: 44)
                                }

                                Text(DesignTokens.AgentVisuals.name(for: agent))
                                    .font(.system(size: 11, weight: isRunning ? .semibold : .regular))
                                    .foregroundColor(isRunning ? .white : DesignTokens.Colors.textSecondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 64)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16)
        .background(DesignTokens.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .padding(.horizontal, DesignTokens.Spacing.md)
    }

    // MARK: - 第三排：「用量统计」入口卡片
    private var thirdRowStatsCard: some View {
        Button {
            DesignTokens.Haptics.light()
            onEnterStats()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 14))
                            .foregroundColor(DesignTokens.Colors.morandiPurple)
                        Text("用量统计")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }

                    Spacer()

                    HStack(spacing: 3) {
                        Text("热力图与大屏")
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(DesignTokens.Colors.morandiPurple)
                }

                if let qs = quickSummary {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("总 Tokens")
                                .font(.system(size: 10))
                                .foregroundColor(DesignTokens.Colors.textSecondary)
                            Text(AggregatedUsageSummary.formatCompactTokens(qs.total))
                                .font(.system(size: 15, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("缓存命中率")
                                .font(.system(size: 10))
                                .foregroundColor(DesignTokens.Colors.textSecondary)
                            Text(qs.cacheHitRateString)
                                .font(.system(size: 15, weight: .bold, design: .monospaced))
                                .foregroundColor(DesignTokens.Colors.morandiPurple)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("对话轮次")
                                .font(.system(size: 10))
                                .foregroundColor(DesignTokens.Colors.textSecondary)
                            Text("\(qs.totalTurns) 轮")
                                .font(.system(size: 15, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                        }

                        Spacer()
                    }
                }
            }
            .padding(16)
            .background(DesignTokens.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DesignTokens.Spacing.md)
    }

    // MARK: - 第四排：「系统设置」入口卡片
    private var fourthRowSettingsCard: some View {
        Button {
            DesignTokens.Haptics.light()
            showingSettings = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Color(white: 0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text("设置")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
            }
            .padding(16)
            .background(DesignTokens.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DesignTokens.Spacing.md)
    }

    // MARK: - 交互操作
    private func handleAgentTap(agent: String, isRunning: Bool) {
        selectedTarget = agent
        if isRunning {
            // 已在运行中，直接进入对话
            onEnterChat(agent)
        } else {
            // 未在运行，发起唤醒拉起
            Task {
                let ok = await APIService.shared.launchApp(target: agent)
                if ok {
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    let status = try? await APIService.shared.fetchAppStatus(target: agent)
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            agentRunningMap[agent.lowercased()] = status ?? true
                        }
                    }
                }
            }
        }
    }

    private func probeAllAgentsStatus() async {
        guard !isProbingStatus else { return }
        isProbingStatus = true
        if let statusMap = try? await APIService.shared.fetchAllAppStatus() {
            await MainActor.run {
                self.agentRunningMap = statusMap
            }
        }
        isProbingStatus = false
    }

    private func loadQuickSummary() async {
        if let res = try? await APIService.shared.fetchUsageStats(force: false) {
            var s = AggregatedUsageSummary()
            for (_, t) in res.tools ?? [:] where t.available {
                s.total += t.total ?? 0
                s.totalInput += t.totalInput ?? 0
                s.totalOutput += t.totalOutput ?? 0
                s.totalCacheRead += t.totalCacheRead ?? 0
                s.totalCacheWrite += t.totalCacheWrite ?? 0
                s.totalCalls += t.totalCalls ?? 0
                s.totalTurns += t.totalTurns ?? 0
            }
            await MainActor.run {
                self.quickSummary = s
            }
        }
    }
}
