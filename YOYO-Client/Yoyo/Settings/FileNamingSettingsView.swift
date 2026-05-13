import SwiftUI

// MARK: - design constants
private enum Design {
    static let bg = Color(white: 0.04)
    static let card = Color(red: 40 / 255, green: 40 / 255, blue: 40 / 255)
    static let accent = Color.white
    static let radius: CGFloat = kCardCornerRadius
}

struct FileNamingSettingsView: View {
    @AppStorage("fileNamingFormat") private var formatRaw: String = CameraSettingsState.FileNamingFormat.standard.rawValue
    @AppStorage("customFileNamingFormat") private var customFormat: String = "{timestamp}_{type}_{uuid}"

    @State private var customInput: String = ""
    @State private var selectedIndex: Int = 0

    private let formats: [CameraSettingsState.FileNamingFormat] = [.standard, .classic, .daily, .pro, .custom]

    private var currentFormat: CameraSettingsState.FileNamingFormat {
        CameraSettingsState.FileNamingFormat(rawValue: formatRaw) ?? .standard
    }

    private var effectiveTemplate: String {
        currentFormat == .custom ? (customInput.isEmpty ? formats[0].template : customInput) : currentFormat.template
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 28) {
                // MARK: - format selector
                VStack(alignment: .leading, spacing: 10) {
                    Label(String.fileNamingFormat.localized, systemImage: "doc.text")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.gray)

                    FormatPicker(formats: formats, selected: $selectedIndex) { idx in
                        let format = formats[idx]
                        AnalyticsManager.shared.log(.settingsAction(action: "select_file_naming_\(format.rawValue)"))
                        formatRaw = format.rawValue
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }

                // MARK: - Custom template
                if currentFormat == .custom {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(String.fileNamingCustomFormat.localized, systemImage: "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.gray)

                        GlassCard(paddingValue: 16) {
                            VStack(alignment: .leading, spacing: 12) {
                                TextField("{timestamp}_{type}_{uuid}", text: $customInput, axis: .vertical)
                                    .font(.system(size: 14, design: .monospaced))
                                    .foregroundStyle(.white)
                                    .lineLimit(2 ... 4)
                                    .onChange(of: customInput) { _, v in customFormat = v }

                                Text(String.fileNamingVariables.localized)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // MARK: - Live preview
                VStack(alignment: .leading, spacing: 10) {
                    Label(String.commonPreview.localized, systemImage: "eye")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.gray)

                    PreviewCard(template: effectiveTemplate)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .background(Design.bg.ignoresSafeArea())
        .navigationTitle(String.cameraSettingsFileNaming.localized)
        .navigationBarTitleDisplayMode(.inline)
        .trackScreen(name: "FileNamingSettings")
        .onAppear {
            customInput = customFormat
            selectedIndex = formats.firstIndex(of: currentFormat) ?? 0
        }
        .animation(.easeInOut(duration: 0.25), value: currentFormat)
    }
}

// MARK: - format selector
private struct FormatPicker: View {
    let formats: [CameraSettingsState.FileNamingFormat]
    @Binding var selected: Int
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(formats.enumerated()), id: \.offset) { idx, format in
                FormatRow(format: format, isSelected: selected == idx) {
                    selected = idx
                    onSelect(idx)
                }
            }
        }
    }
}

private struct FormatRow: View {
    let format: CameraSettingsState.FileNamingFormat
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Check indicator.
                Circle()
                    .fill(isSelected ? Design.accent : .clear)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(isSelected ? Design.accent : .white.opacity(0.2), lineWidth: 1.5))

                VStack(alignment: .leading, spacing: 2) {
                    Text(format.displayName)
                        .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.7))

                    Text(format.description)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(isSelected ? Design.accent.opacity(0.12) : Design.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Design.accent.opacity(0.4) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview card
private struct PreviewCard: View {
    let template: String

    var body: some View {
        GlassCard(paddingValue: 0) {
            VStack(spacing: 0) {
                PreviewItem(icon: "photo", type: .photo, format: .heic, template: template)
                Divider().background(.white.opacity(0.08)).padding(.leading, 48)
                PreviewItem(icon: "video", type: .video, format: .mp4, template: template)
            }
        }
    }
}

private struct PreviewItem: View {
    let icon: String
    let type: FileType
    let format: FileFormat
    let template: String

    private var fileName: String {
        FileNameGenerator.shared.previewFileName(template: template, prefix: "", fileType: type, fileFormat: format)
            + ".\(format.fileExtension)"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Design.accent)
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.06), in: Circle())

            Text(fileName)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

#Preview {
    NavigationStack {
        FileNamingSettingsView()
    }
}
