import SwiftUI
import PhotosUI

public struct InputBarView: View {
    @Binding public var text: String
    @Binding public var selectedImageBase64: String?
    public let onSend: (String, String?) -> Void

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var previewImage: UIImage?
    @State private var inputResetId: UUID = UUID()

    public init(
        text: Binding<String>,
        selectedImageBase64: Binding<String?>,
        onSend: @escaping (String, String?) -> Void
    ) {
        self._text = text
        self._selectedImageBase64 = selectedImageBase64
        self.onSend = onSend
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 图片预览栏（无废话文字，叉号严丝合缝位于图片右上角角标）
            if let img = previewImage {
                HStack {
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 54, height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))

                        Button {
                            DesignTokens.Haptics.light()
                            previewImage = nil
                            selectedImageBase64 = nil
                            selectedPhotoItem = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.white)
                                .background(Color.black.opacity(0.75))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .offset(x: 6, y: -6)
                    }
                    .padding(.top, 6)
                    .padding(.trailing, 6)

                    Spacer()
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .background(Color(red: 24/255, green: 24/255, blue: 27/255))
            }

            // 主操作行（仿 ChatGPT / Gemini 原生多行自适应输入栏）
            HStack(alignment: .bottom, spacing: DesignTokens.Spacing.sm) {
                // 相册选择器
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: "photo")
                        .font(.system(size: 17))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                        .frame(width: 38, height: 38)
                        .background(DesignTokens.Colors.cardBackground)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .frame(minWidth: DesignTokens.Interaction.minTouchTarget, minHeight: DesignTokens.Interaction.minTouchTarget)
                .padding(.bottom, 1)
                .onChange(of: selectedPhotoItem) { _, newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self),
                           let originImg = UIImage(data: data) {
                            // 用户明确要求：取消 600 像素限制，保留原图高清分辨率以便看清长文本
                            if let jpegData = originImg.jpegData(compressionQuality: 0.88) {
                                DispatchQueue.main.async {
                                    self.previewImage = originImg
                                    self.selectedImageBase64 = jpegData.base64EncodedString()
                                }
                            }
                        }
                    }
                }

                // 文本多行自适应输入框（1~8 行自适应高度，超出上下移动光标，强制挂载 inputResetId 杜绝残留）
                TextField("输入消息…", text: $text, axis: .vertical)
                    .id(inputResetId)
                    .textFieldStyle(.plain)
                    .lineLimit(1...8)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(minHeight: 38)
                    .background(DesignTokens.Colors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 19))

                // 发送按钮（底部对齐，大热区直接响应）
                Button {
                    triggerSend()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(canSend ? DesignTokens.Colors.accent : Color(white: 0.25))
                        .clipShape(Circle())
                }
                .buttonStyle(.borderless)
                .disabled(!canSend)
                .frame(minWidth: DesignTokens.Interaction.minTouchTarget, minHeight: DesignTokens.Interaction.minTouchTarget)
                .contentShape(Rectangle())
                .padding(.bottom, 1)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(Color(red: 20/255, green: 20/255, blue: 22/255))
        }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedImageBase64 != nil
    }

    private func triggerSend() {
        let textToSend = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let imgToSend = selectedImageBase64
        guard !textToSend.isEmpty || imgToSend != nil else { return }

        DesignTokens.Haptics.medium()

        // 1. 彻底清空当前输入框并强制重置底层文本组件，杜绝任何文字残留
        self.text = ""
        self.inputResetId = UUID()
        self.previewImage = nil
        self.selectedPhotoItem = nil
        self.selectedImageBase64 = nil

        DispatchQueue.main.async {
            self.text = ""
        }

        // 2. 将内容以显式参数直接传递给父级
        onSend(textToSend, imgToSend)
    }
}
