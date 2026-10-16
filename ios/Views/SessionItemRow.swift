import SwiftUI

public struct SessionItemRow: View {
    public let item: SessionItem
    public let isSelected: Bool
    public let onSelect: () -> Void
    public let onRename: () -> Void
    public let onArchive: () -> Void
    public let onDelete: () -> Void

    public init(
        item: SessionItem,
        isSelected: Bool,
        onSelect: @escaping () -> Void,
        onRename: @escaping () -> Void,
        onArchive: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.item = item
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onRename = onRename
        self.onArchive = onArchive
        self.onDelete = onDelete
    }

    public var body: some View {
        Button(action: onSelect) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Text(item.title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? DesignTokens.Colors.accent : DesignTokens.Colors.textPrimary)
                    .lineLimit(1)

                Spacer()

                Text(item.displayTime)
                    .font(.system(size: 11))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(isSelected ? DesignTokens.Colors.cardActive : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                DesignTokens.Haptics.medium()
                onDelete()
            } label: {
                Label("删除", systemImage: "trash")
            }

            Button {
                DesignTokens.Haptics.light()
                onArchive()
            } label: {
                Label("归档", systemImage: "archivebox")
            }
            .tint(.orange)

            Button {
                DesignTokens.Haptics.light()
                onRename()
            } label: {
                Label("重命名", systemImage: "pencil")
            }
            .tint(DesignTokens.Colors.accent)
        }
    }
}
