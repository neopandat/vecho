import SwiftUI

public struct IdentifiableImage: Identifiable {
    public let id = UUID()
    public let image: UIImage
}

public struct ChatView: View {
    public let messages: [ChatMessage]
    public var isLoading: Bool = false
    public var isLaunching: Bool = false
    public var isWaitingForResponse: Bool = false
    public var targetName: String = ""
    public var onDeleteMessage: ((ChatMessage) -> Void)? = nil
    public var onResendMessage: ((String) -> Void)? = nil

    @State private var previewItem: IdentifiableImage? = nil

    public init(
        messages: [ChatMessage],
        isLoading: Bool = false,
        isLaunching: Bool = false,
        isWaitingForResponse: Bool = false,
        targetName: String = "",
        onDeleteMessage: ((ChatMessage) -> Void)? = nil,
        onResendMessage: ((String) -> Void)? = nil
    ) {
        self.messages = messages
        self.isLoading = isLoading
        self.isLaunching = isLaunching
        self.isWaitingForResponse = isWaitingForResponse
        self.targetName = targetName
        self.onDeleteMessage = onDeleteMessage
        self.onResendMessage = onResendMessage
    }

    public var body: some View {
        ZStack {
            if isLaunching {
                VStack(spacing: DesignTokens.Spacing.md) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(DesignTokens.Colors.accent)
                    Text("正在唤起 \(targetName)…")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Text("正在同步会话与历史消息，请稍候")
                        .font(.system(size: 12))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isLoading && messages.isEmpty {
                VStack(spacing: DesignTokens.Spacing.sm) {
                    ProgressView()
                        .tint(DesignTokens.Colors.textSecondary)
                    Text("正在同步消息记录…")
                        .font(.system(size: 13))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if messages.isEmpty {
                VStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 32))
                        .foregroundColor(DesignTokens.Colors.textSecondary.opacity(0.5))
                    Text("已就绪，发送消息开启对话")
                        .font(.system(size: 13))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: DesignTokens.Spacing.md) {
                            ForEach(messages) { message in
                                MessageRow(
                                    message: message,
                                    onDelete: {
                                        onDeleteMessage?(message)
                                    },
                                    onResend: { txt in
                                        onResendMessage?(txt)
                                    },
                                    onTapImage: { img in
                                        DesignTokens.Haptics.light()
                                        previewItem = IdentifiableImage(image: img)
                                    }
                                )
                                .id(message.id)
                            }

                            // 思考中起伏波浪线动效
                            if isWaitingForResponse {
                                HStack {
                                    ThinkingWaveView()
                                    Spacer(minLength: 32)
                                }
                                .id("thinking_wave_anchor")
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            }

                            // 底部锚点
                            Color.clear
                                .frame(height: 1)
                                .id("chat_bottom_anchor")
                        }
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.vertical, DesignTokens.Spacing.lg)
                    }
                    .defaultScrollAnchor(.bottom)
                    .scrollDismissesKeyboard(.interactively)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            proxy.scrollTo("chat_bottom_anchor", anchor: .bottom)
                        }
                    }
                    .onChange(of: messages.count) { _, _ in
                        DispatchQueue.main.async {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("chat_bottom_anchor", anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: messages.last?.id) { _, _ in
                        DispatchQueue.main.async {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("chat_bottom_anchor", anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: isWaitingForResponse) { _, waiting in
                        if waiting {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                withAnimation(.easeOut(duration: 0.25)) {
                                    proxy.scrollTo("chat_bottom_anchor", anchor: .bottom)
                                }
                            }
                        }
                    }
                }
            }
        }
        .fullScreenCover(item: $previewItem) { item in
            FullScreenImageViewer(image: item.image, onDismiss: {
                previewItem = nil
            })
        }
    }
}

public struct FullScreenImageViewer: View {
    public let image: UIImage
    public let onDismiss: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }

            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale)
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .gesture(
                    MagnificationGesture()
                        .onChanged { val in
                            scale = max(1.0, min(lastScale * val, 4.0))
                        }
                        .onEnded { _ in
                            lastScale = scale
                            if scale < 1.05 {
                                withAnimation(.spring()) {
                                    scale = 1.0
                                    lastScale = 1.0
                                }
                            }
                        }
                )
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        withAnimation(.spring()) {
                            if scale > 1.05 {
                                scale = 1.0
                                lastScale = 1.0
                            } else {
                                scale = 2.5
                                lastScale = 2.5
                            }
                        }
                    }
                )
                .onTapGesture {
                    onDismiss()
                }

            Button {
                DesignTokens.Haptics.light()
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(Color.white.opacity(0.85))
                    .padding(20)
            }
            .buttonStyle(.plain)
            .frame(minWidth: 44, minHeight: 44)
        }
        .background(Color.black.ignoresSafeArea())
    }
}

public struct MessageRow: View {
    public let message: ChatMessage
    public var onDelete: (() -> Void)? = nil
    public var onResend: ((String) -> Void)? = nil
    public var onTapImage: ((UIImage) -> Void)? = nil

    public init(
        message: ChatMessage,
        onDelete: (() -> Void)? = nil,
        onResend: ((String) -> Void)? = nil,
        onTapImage: ((UIImage) -> Void)? = nil
    ) {
        self.message = message
        self.onDelete = onDelete
        self.onResend = onResend
        self.onTapImage = onTapImage
    }

    public var body: some View {
        HStack {
            if message.isUser {
                Spacer(minLength: 32)
            }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                // 若有图片展示图片，点击看大图
                if let b64 = message.imageBase64,
                   let data = Data(base64Encoded: b64),
                   let uiImage = UIImage(data: data) {
                    Button {
                        DesignTokens.Haptics.light()
                        onTapImage?(uiImage)
                    } label: {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 240, maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                    }
                    .buttonStyle(.plain)
                }

                if !message.text.isEmpty {
                    MarkdownContentView(text: message.text, isUser: message.isUser)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                                .fill(message.isUser ? DesignTokens.Colors.accent : DesignTokens.Colors.cardBackground)
                        )
                }

                // 正下方快捷小图标栏：复制、发送/重填、删除
                HStack(spacing: 12) {
                    if message.isUser {
                        if !message.time.isEmpty {
                            Text(message.time)
                                .font(.system(size: 10))
                                .foregroundColor(DesignTokens.Colors.textSecondary.opacity(0.6))
                        }
                    }

                    // 1. 复制按钮
                    Button {
                        DesignTokens.Haptics.light()
                        UIPasteboard.general.string = message.text
                    } label: {
                        Image(systemName: "square.on.square")
                            .font(.system(size: 12))
                            .foregroundColor(DesignTokens.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 24, height: 24)

                    // 2. 发送 / 填入输入框按钮
                    Button {
                        DesignTokens.Haptics.light()
                        onResend?(message.text)
                    } label: {
                        Image(systemName: "arrow.up.circle")
                            .font(.system(size: 13))
                            .foregroundColor(DesignTokens.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 24, height: 24)

                    // 3. 删除按钮
                    Button {
                        DesignTokens.Haptics.medium()
                        onDelete?()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(DesignTokens.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 24, height: 24)

                    if !message.isUser {
                        if !message.time.isEmpty {
                            Text(message.time)
                                .font(.system(size: 10))
                                .foregroundColor(DesignTokens.Colors.textSecondary.opacity(0.6))
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 1)
            }

            if !message.isUser {
                Spacer(minLength: 32)
            }
        }
    }
}

// MARK: - Markdown 解析与原生渲染引擎
public enum MarkdownBlock: Identifiable {
    case heading(level: Int, text: String)
    case codeBlock(lang: String, code: String)
    case divider
    case paragraph(text: String)

    public var id: String {
        switch self {
        case .heading(let l, let t): return "h_\(l)_\(t)"
        case .codeBlock(let l, let c): return "code_\(l)_\(c.hashValue)"
        case .divider: return "divider_\(UUID().uuidString)"
        case .paragraph(let t): return "p_\(t.hashValue)"
        }
    }
}

public struct MarkdownContentView: View {
    public let text: String
    public let isUser: Bool

    public init(text: String, isUser: Bool = false) {
        self.text = text
        self.isUser = isUser
    }

    public var body: some View {
        let blocks = parseMarkdownBlocks(text)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let hText):
                    renderHeading(level: level, text: hText)
                case .codeBlock(let lang, let code):
                    CodeBlockView(lang: lang, code: code)
                case .divider:
                    Rectangle()
                        .fill(Color(white: 0.25))
                        .frame(height: 1)
                        .padding(.vertical, 4)
                case .paragraph(let pText):
                    renderParagraph(text: pText)
                }
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func renderHeading(level: Int, text: String) -> some View {
        let fontSize: CGFloat = {
            switch level {
            case 1: return 18
            case 2: return 16
            case 3: return 15
            default: return 14
            }
        }()
        let weight: Font.Weight = (level <= 3) ? .bold : .semibold

        if let attr = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attr)
                .font(.system(size: fontSize, weight: weight))
                .foregroundColor(.white)
                .padding(.top, 2)
        } else {
            Text(text)
                .font(.system(size: fontSize, weight: weight))
                .foregroundColor(.white)
                .padding(.top, 2)
        }
    }

    @ViewBuilder
    private func renderParagraph(text: String) -> some View {
        if let attr = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attr)
                .font(.system(size: 15))
                .foregroundColor(.white)
                .tint(Color(red: 100/255, green: 175/255, blue: 255/255))
                .lineSpacing(3)
        } else {
            Text(text)
                .font(.system(size: 15))
                .foregroundColor(.white)
                .lineSpacing(3)
        }
    }

    private func parseMarkdownBlocks(_ raw: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = raw.components(separatedBy: "\n")
        var inCodeBlock = false
        var currentCodeLang = ""
        var currentCodeLines: [String] = []
        var currentParagraphLines: [String] = []

        func flushParagraph() {
            if !currentParagraphLines.isEmpty {
                let pText = currentParagraphLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !pText.isEmpty {
                    blocks.append(.paragraph(text: pText))
                }
                currentParagraphLines.removeAll()
            }
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCodeBlock {
                    let code = currentCodeLines.joined(separator: "\n")
                    blocks.append(.codeBlock(lang: currentCodeLang, code: code))
                    currentCodeLines.removeAll()
                    currentCodeLang = ""
                    inCodeBlock = false
                } else {
                    flushParagraph()
                    inCodeBlock = true
                    currentCodeLang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
                continue
            }

            if inCodeBlock {
                currentCodeLines.append(line)
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(.divider)
                continue
            }

            if trimmed.hasPrefix("#") {
                var level = 0
                for ch in trimmed {
                    if ch == "#" { level += 1 } else { break }
                }
                if level <= 6 && trimmed.count > level {
                    let idx = trimmed.index(trimmed.startIndex, offsetBy: level)
                    if trimmed[idx] == " " {
                        flushParagraph()
                        let hText = String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                        blocks.append(.heading(level: level, text: hText))
                        continue
                    }
                }
            }

            currentParagraphLines.append(line)
        }

        if inCodeBlock {
            let code = currentCodeLines.joined(separator: "\n")
            blocks.append(.codeBlock(lang: currentCodeLang, code: code))
        }
        flushParagraph()
        return blocks
    }
}

// MARK: - 代码块美化与一键复制卡片
public struct CodeBlockView: View {
    public let lang: String
    public let code: String

    @State private var isCopied: Bool = false

    public init(lang: String, code: String) {
        self.lang = lang
        self.code = code
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶栏：语言标签 + 复制按钮
            HStack {
                Text(lang.isEmpty ? "code" : lang.lowercased())
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(DesignTokens.Colors.textSecondary)

                Spacer()

                Button {
                    DesignTokens.Haptics.light()
                    UIPasteboard.general.string = code
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isCopied = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isCopied = false
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                        Text(isCopied ? "已复制" : "复制")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(isCopied ? DesignTokens.Colors.success : DesignTokens.Colors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(white: 0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(red: 22/255, green: 22/255, blue: 26/255))

            // 代码正文：支持横向滑动，等宽字体
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundColor(Color(red: 225/255, green: 230/255, blue: 240/255))
                    .padding(10)
            }
        }
        .background(Color(red: 13/255, green: 13/255, blue: 16/255))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(white: 0.2), lineWidth: 1)
        )
        .padding(.vertical, 4)
    }
}

// MARK: - 思考中起伏波浪线动效
public struct ThinkingWaveView: View {
    @State private var isAnimating: Bool = false

    public init() {}

    public var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<4) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [
                                DesignTokens.Colors.accent,
                                DesignTokens.Colors.accent.opacity(0.4)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3.5, height: isAnimating ? 20 : 6)
                    .animation(
                        Animation.easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.12),
                        value: isAnimating
                    )
            }

            Text("思考中…")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DesignTokens.Colors.textSecondary)
                .padding(.leading, 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DesignTokens.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(DesignTokens.Colors.border, lineWidth: 1)
        )
        .onAppear {
            isAnimating = true
        }
    }
}

