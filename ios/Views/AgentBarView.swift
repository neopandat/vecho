import SwiftUI

public struct AgentBarView: View {
    @Binding public var selectedTarget: String
    public let targets: [String]
    public let onlyShowIcons: Bool
    public let showStatsTab: Bool
    public var agentRunningMap: [String: Bool] = [:]

    public init(
        selectedTarget: Binding<String>,
        targets: [String],
        onlyShowIcons: Bool = false,
        showStatsTab: Bool = true,
        agentRunningMap: [String: Bool] = [:]
    ) {
        self._selectedTarget = selectedTarget
        self.targets = targets
        self.onlyShowIcons = onlyShowIcons
        self.showStatsTab = showStatsTab
        self.agentRunningMap = agentRunningMap
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                // 用量统计专属胶囊
                if showStatsTab {
                    let isStatsSelected = selectedTarget.lowercased() == "stats"
                    Button {
                        DesignTokens.Haptics.selection()
                        selectedTarget = "stats"
                    } label: {
                        HStack(spacing: onlyShowIcons ? 0 : 6) {
                            Image(systemName: "chart.bar.xaxis")
                                .font(.system(size: onlyShowIcons ? 16 : 14, weight: .semibold))
                            if !onlyShowIcons {
                                Text("用量统计")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                        }
                        .foregroundColor(isStatsSelected ? .white : DesignTokens.Colors.textSecondary)
                        .padding(.horizontal, onlyShowIcons ? 10 : 14)
                        .padding(.vertical, onlyShowIcons ? 6 : 8)
                        .background(
                            Capsule()
                                .fill(isStatsSelected ? DesignTokens.Colors.accent : DesignTokens.Colors.cardBackground)
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: DesignTokens.Interaction.minTouchTarget)
                    .contentShape(Rectangle())
                }

                ForEach(targets, id: \.self) { target in
                    let isSelected = selectedTarget.lowercased() == target.lowercased()
                    let isRunning = agentRunningMap[target.lowercased()] ?? false

                    Button {
                        DesignTokens.Haptics.selection()
                        selectedTarget = target
                    } label: {
                        HStack(spacing: onlyShowIcons ? 4 : 6) {
                            ZStack(alignment: .bottomTrailing) {
                                AgentIconView(target: target, size: onlyShowIcons ? 22 : 16)
                                    .saturation(isRunning ? 1.0 : 0.0)
                                    .opacity(isRunning ? 1.0 : 0.35)

                                // 未开或开启的微状态圆点
                                Circle()
                                    .fill(isRunning ? DesignTokens.Colors.success : Color(white: 0.32))
                                    .frame(width: 5, height: 5)
                                    .offset(x: 2, y: 2)
                            }

                            if !onlyShowIcons {
                                Text(DesignTokens.AgentVisuals.name(for: target))
                                    .font(.system(size: 14, weight: isRunning ? .semibold : .regular))
                                    .foregroundColor(
                                        isSelected
                                            ? (isRunning ? .white : Color(white: 0.75))
                                            : (isRunning ? DesignTokens.Colors.textSecondary : Color(white: 0.35))
                                    )
                            }
                        }
                        .padding(.horizontal, onlyShowIcons ? 10 : 14)
                        .padding(.vertical, onlyShowIcons ? 6 : 8)
                        .background(
                            Capsule()
                                .fill(
                                    isSelected
                                        ? (isRunning ? DesignTokens.Colors.accent : Color(white: 0.22))
                                        : DesignTokens.Colors.cardBackground
                                )
                        )
                        .overlay(
                            Capsule()
                                .stroke(
                                    isSelected && !isRunning ? Color(white: 0.35) : Color.clear,
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: DesignTokens.Interaction.minTouchTarget)
                    .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
        }
    }
}
