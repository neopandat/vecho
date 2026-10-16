import SwiftUI

/// 系统统一设计变量与交互规范
public enum DesignTokens {
    public enum Colors {
        public static let background = Color.black
        public static let cardBackground = Color(red: 28/255, green: 28/255, blue: 30/255)
        public static let cardActive = Color(red: 44/255, green: 44/255, blue: 46/255)
        public static let accent = Color(red: 10/255, green: 132/255, blue: 255/255)
        public static let textPrimary = Color.white
        public static let textSecondary = Color(red: 142/255, green: 142/255, blue: 147/255)
        public static let border = Color(red: 44/255, green: 44/255, blue: 46/255)
        public static let danger = Color(red: 255/255, green: 69/255, blue: 58/255)
        public static let success = Color(red: 48/255, green: 209/255, blue: 88/255)

        // 莫兰迪热力图与统计色阶
        public static let heat0 = Color(red: 25/255, green: 27/255, blue: 36/255)
        public static let heat1 = Color(red: 158/255, green: 142/255, blue: 196/255).opacity(0.22)
        public static let heat2 = Color(red: 158/255, green: 142/255, blue: 196/255).opacity(0.50)
        public static let heat3 = Color(red: 158/255, green: 142/255, blue: 196/255)
        public static let heat4 = Color(red: 196/255, green: 162/255, blue: 117/255)
        public static let heat5 = Color(red: 192/255, green: 126/255, blue: 104/255)
        public static let heat6 = Color(red: 184/255, green: 93/255, blue: 86/255)
        public static let heat7 = Color(red: 140/255, green: 51/255, blue: 45/255)

        // 莫兰迪项目与工具色系
        public static let morandiPurple = Color(red: 158/255, green: 142/255, blue: 196/255)
        public static let morandiGreen = Color(red: 122/255, green: 154/255, blue: 139/255)
        public static let morandiBlue = Color(red: 115/255, green: 143/255, blue: 167/255)
        public static let morandiGold = Color(red: 196/255, green: 162/255, blue: 117/255)
        public static let morandiRose = Color(red: 189/255, green: 128/255, blue: 138/255)
        public static let morandiMauve = Color(red: 138/255, green: 123/255, blue: 150/255)
        public static let morandiGray = Color(red: 122/255, green: 128/255, blue: 137/255)
    }

    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 20
    }

    public enum Radius {
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 18
        public static let full: CGFloat = 999
    }

    public enum Interaction {
        /// 苹果原生触控热区绝对死线（≥ 44pt）
        public static let minTouchTarget: CGFloat = 44.0
    }

    /// 触觉反馈标准收敛
    public enum Haptics {
        public static func light() {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        }

        public static func medium() {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
        }

        public static func selection() {
            #if os(iOS)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
        }
    }

    /// 智能体统一视觉映射
    public enum AgentVisuals {
        public static func symbol(for target: String) -> String {
            switch target.lowercased() {
            case "antigravity": return "sparkles"
            case "workbuddy": return "briefcase.fill"
            case "claude": return "brain.head.profile"
            case "chatgpt", "codex": return "bubble.left.and.bubble.right.fill"
            case "trae": return "chevron.left.forwardslash.chevron.right"
            case "qoder": return "curlybraces"
            case "deepseek": return "waveform.path.ecg"
            case "cursor": return "cursorarrow.rays"
            case "windsurf": return "wind"
            case "cline": return "cpu.fill"
            case "aider": return "terminal.fill"
            case "copilot": return "airplane"
            case "master": return "slider.horizontal.3"
            case "stats": return "chart.bar.xaxis"
            default: return "cpu"
            }
        }

        public static func name(for target: String) -> String {
            switch target.lowercased() {
            case "antigravity": return "Antigravity"
            case "workbuddy": return "WorkBuddy"
            case "claude": return "Claude"
            case "chatgpt": return "ChatGPT"
            case "trae": return "Trae"
            case "qoder": return "Qoder"
            case "deepseek": return "DeepSeek"
            case "cursor": return "Cursor"
            case "windsurf": return "Windsurf"
            case "cline": return "Cline"
            case "aider": return "Aider"
            case "copilot": return "Copilot"
            case "master": return "总调度"
            case "stats": return "用量统计"
            default: return target
            }
        }
    }
}

/// 智能体官方图标渲染视图
public struct AgentIconView: View {
    public let target: String
    public let size: CGFloat

    public init(target: String, size: CGFloat = 18) {
        self.target = target
        self.size = size
    }

    public var body: some View {
        Group {
            if let _ = UIImage(named: "Agent_\(target.lowercased())") {
                Image("Agent_\(target.lowercased())")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: DesignTokens.AgentVisuals.symbol(for: target))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(DesignTokens.Colors.textSecondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(3, size * 0.22)))
    }
}
