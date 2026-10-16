import SwiftUI

public struct SessionDrawerView: View {
    public let target: String
    public let isRunning: Bool
    public let groups: [SessionGroup]
    @Binding public var selectedSessionId: String?
    public let onClose: () -> Void
    public let onSelectSession: (String) -> Void
    public let onNewSession: (String?) -> Void
    public let onRefresh: () -> Void
    public let onLaunch: (() -> Void)?

    @State private var collapsedGroups: Set<String> = []
    @State private var showingRenameAlert: Bool = false
    @State private var renamingSession: SessionItem?
    @State private var newTitleInput: String = ""

    public init(
        target: String,
        isRunning: Bool,
        groups: [SessionGroup],
        selectedSessionId: Binding<String?>,
        onClose: @escaping () -> Void,
        onSelectSession: @escaping (String) -> Void,
        onNewSession: @escaping (String?) -> Void,
        onRefresh: @escaping () -> Void,
        onLaunch: (() -> Void)? = nil
    ) {
        self.target = target
        self.isRunning = isRunning
        self.groups = groups
        self._selectedSessionId = selectedSessionId
        self.onClose = onClose
        self.onSelectSession = onSelectSession
        self.onNewSession = onNewSession
        self.onRefresh = onRefresh
        self.onLaunch = onLaunch
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 抽屉顶栏
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        AgentIconView(target: target, size: 20)
                        Text(DesignTokens.AgentVisuals.name(for: target))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }

                    HStack(spacing: 8) {
                        Circle()
                            .fill(isRunning ? DesignTokens.Colors.success : Color(white: 0.4))
                            .frame(width: 8, height: 8)
                        Text(isRunning ? "运行中" : "未启动")
                            .font(.system(size: 12))
                            .foregroundColor(DesignTokens.Colors.textSecondary)

                        if !isRunning {
                            Button {
                                DesignTokens.Haptics.medium()
                                onLaunch?()
                            } label: {
                                Text("启动")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(DesignTokens.Colors.accent)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, DesignTokens.Spacing.md)
            .padding(.bottom, DesignTokens.Spacing.sm)

            Divider()
                .background(DesignTokens.Colors.border)

            // 抽屉最顶端：「新建聊天窗口」快捷操作卡片
            Button {
                DesignTokens.Haptics.medium()
                onNewSession(nil)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.bubble.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DesignTokens.Colors.accent)

                    Text("新建聊天窗口")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)

                    Spacer()

                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(DesignTokens.Colors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .stroke(DesignTokens.Colors.accent.opacity(0.35), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)

            // 分组列表
            List {
                ForEach(groups) { group in
                    Section {
                        let isCollapsed = collapsedGroups.contains(group.group_name)
                        if !isCollapsed {
                            ForEach(group.items) { item in
                                SessionItemRow(
                                    item: item,
                                    isSelected: selectedSessionId == item.id,
                                    onSelect: {
                                        selectedSessionId = item.id
                                        onSelectSession(item.id)
                                    },
                                    onRename: {
                                        renamingSession = item
                                        newTitleInput = item.title
                                        showingRenameAlert = true
                                    },
                                    onArchive: {
                                        Task {
                                            _ = await APIService.shared.archiveSession(target: target, sessionId: item.id)
                                            onRefresh()
                                        }
                                    },
                                    onDelete: {
                                        Task {
                                            _ = await APIService.shared.deleteSession(target: target, sessionId: item.id)
                                            onRefresh()
                                        }
                                    }
                                )
                                .listRowInsets(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if collapsedGroups.contains(group.group_name) {
                                        collapsedGroups.remove(group.group_name)
                                    } else {
                                        collapsedGroups.insert(group.group_name)
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(group.group_name)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(DesignTokens.Colors.textSecondary)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)

                            // 在项目/分组上增加专属新建窗口按钮
                            Button {
                                DesignTokens.Haptics.medium()
                                onNewSession(group.group_name)
                            } label: {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(DesignTokens.Colors.accent)
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)

                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if collapsedGroups.contains(group.group_name) {
                                        collapsedGroups.remove(group.group_name)
                                    } else {
                                        collapsedGroups.insert(group.group_name)
                                    }
                                }
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(DesignTokens.Colors.textSecondary)
                                    .rotationEffect(.degrees(collapsedGroups.contains(group.group_name) ? 0 : 90))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 6)
                    }
                }
            }
            .listStyle(.plain)
            .padding(.horizontal, 6)
            .background(Color.clear)
        }
        .frame(maxWidth: 310)
        .background(Color(red: 20/255, green: 20/255, blue: 22/255))
        .alert("修改会话名称", isPresented: $showingRenameAlert) {
            TextField("输入新标题", text: $newTitleInput)
            Button("取消", role: .cancel) {}
            Button("确定") {
                if let item = renamingSession, !newTitleInput.trimmingCharacters(in: .whitespaces).isEmpty {
                    Task {
                        _ = await APIService.shared.renameSession(target: target, sessionId: item.id, newTitle: newTitleInput)
                        onRefresh()
                    }
                }
            }
        }
    }
}
