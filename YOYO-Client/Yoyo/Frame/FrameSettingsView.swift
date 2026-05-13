import SwiftUI
import UIKit

struct FrameSettingsView: View {
    @ObservedObject var frameManager: FrameManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top: title and enable switch.
            HStack {
                Text(String.frameTitle.localized)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                Toggle("", isOn: $frameManager.isFrameOn)
                    .labelsHidden()
                    .scaleEffect(0.8)
                    .tint(.accentColor)
            }
            .padding(.horizontal, 16)

            // Photo frame template selection.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    // No picture frame.
                    OptionView(
                        isSelected: frameManager.currentTemplate.id == "none",
                        action: { frameManager.applyTemplate(FrameTemplate.none) }
                    ) {
                        FramePreviewNone()
                    }

                    // Polaroid photo frame.
                    OptionView(
                        isSelected: frameManager.currentTemplate.id == "polaroid",
                        action: { frameManager.applyTemplate(FrameTemplate.polaroid) }
                    ) {
                        FramePreviewPolaroid()
                    }

                    // Blur border.
                    OptionView(
                        isSelected: frameManager.currentTemplate.id == "blurred",
                        action: { frameManager.applyTemplate(FrameTemplate.blurred) }
                    ) {
                        FramePreviewBlurred()
                    }

                    // Bottom border.
                    OptionView(
                        isSelected: frameManager.currentTemplate.id == "bottomOnly",
                        action: { frameManager.applyTemplate(FrameTemplate.bottomOnly) }
                    ) {
                        FramePreviewBottomOnly()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6) // Increase vertical spacing to prevent shadows and corner markers from being obscured.
            }
            .compositingGroup() // Prevent internal layer perspective issues when translucent.
            .opacity(frameManager.isFrameOn ? 1 : 0.4)
            .saturation(frameManager.isFrameOn ? 1 : 0)
            .disabled(!frameManager.isFrameOn)

            // separate            Divider()
                .padding(.horizontal, 16)
                .opacity(0.6)

            // Multiple option information settings.
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 10) {
                // Apple Icon
                InfoItemCell(
                    title: String.frameSettingsAppleIcon.localized,
                    icon: "apple.logo",
                    isOn: Binding(get: { frameManager.showAppleIcon }, set: { frameManager.showAppleIcon = $0 }),
                    previewContent: { AppleIconPreviewContent() }
                )

                // Device model.
                InfoItemCell(
                    title: String.frameSettingsDeviceModel.localized,
                    icon: "iphone",
                    isOn: Binding(get: { frameManager.showDeviceModel }, set: { frameManager.showDeviceModel = $0 }),
                    previewContent: { DeviceModelPreviewContent() }
                )

                // EXIF information.
                InfoItemCell(
                    title: String.frameSettingsExif.localized,
                    icon: "camera.aperture",
                    isOn: Binding(get: { frameManager.showEXIFInfo }, set: { frameManager.showEXIFInfo = $0 }),
                    previewContent: { EXIFPreviewContent() }
                )

                // Shooting date.
                InfoItemCell(
                    title: String.frameSettingsDate.localized,
                    icon: "calendar",
                    isOn: Binding(get: { frameManager.showDate }, set: { frameManager.showDate = $0 }),
                    previewContent: { DatePreviewContent() }
                )

                // Shooting time.
                InfoItemCell(
                    title: String.frameSettingsTime.localized,
                    icon: "clock",
                    isOn: Binding(get: { frameManager.showTime }, set: { frameManager.showTime = $0 }),
                    previewContent: { TimePreviewContent() }
                )

                // Shooting location.
                InfoItemCell(
                    title: String.frameSettingsLocation.localized,
                    icon: "location.fill",
                    isOn: Binding(get: { frameManager.showLocation }, set: { frameManager.showLocation = $0 }),
                    previewContent: { LocationPreviewContent() }
                )

                // Copyright information.
                InfoItemCell(
                    title: String.cameraSettingsCopyright.localized,
                    icon: "c.circle",
                    isOn: Binding(get: { frameManager.showCopyright }, set: { frameManager.showCopyright = $0 }),
                    previewContent: { CopyrightPreviewContent() }
                )

                // Holiday watermark.
                InfoItemCell(
                    title: String.frameSettingsFestivalWatermark.localized,
                    icon: "party.popper.fill",
                    isOn: Binding(get: { frameManager.showFestivalWatermark }, set: { frameManager.showFestivalWatermark = $0 }),
                    previewContent: { FestivalWatermarkPreviewContent() }
                )
            }
            .padding(.horizontal, 16)
            .compositingGroup()
            .opacity(frameManager.isFrameOn ? 1 : 0.4)
            .saturation(frameManager.isFrameOn ? 1 : 0)
            .disabled(!frameManager.isFrameOn)
        }
        .padding(.top, 16)
    }
}

/// Information option cell in the grid layout.
struct InfoItemCell<PreviewContent: View>: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    let previewContent: () -> PreviewContent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // First row: icon and switch.
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.primary.opacity(0.6))
                    .frame(width: 18)

                Spacer()

                // Use a native toggle and constrain its layout footprint.
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .scaleEffect(0.65)
                    .tint(.accentColor)
                    .frame(width: 32, height: 20) // Limit the actual layout space of the Toggle.
            }
            .frame(height: 24)

            // Second row: title and preview content.
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                previewContent()
                    .opacity(isOn ? 0.8 : 0.4)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .glassCardStyle(cornerRadius: 12)
        .contentShape(Rectangle())
        .onTapGesture {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isOn.toggle()
            }
        }
    }
}

struct OptionView: View {
    let isSelected: Bool
    let previewContent: AnyView
    let action: () -> Void

    init(isSelected: Bool, action: @escaping () -> Void, @ViewBuilder previewContent: () -> some View) {
        self.isSelected = isSelected
        self.action = action
        self.previewContent = AnyView(previewContent())
    }

    var body: some View {
        ZStack {
            Button(action: {
                let selectionFeedback = UISelectionFeedbackGenerator()
                selectionFeedback.selectionChanged()
                action()
            }) {
                // Preview content.
                previewContent
                    .frame(width: 64, height: 64)
                    .glassCardStyle(cornerRadius: 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.accentColor : Color.white.opacity(0.1), lineWidth: isSelected ? 2 : 0.5)
                    )
            }

            // Check mark in the selected state.
            if isSelected {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                            .background(Color.white)
                            .clipShape(Circle())
                            .font(.system(size: 14))
                            .offset(x: 4, y: 4)
                    }
                }
                .frame(width: 64, height: 64)
                .allowsHitTesting(false)
            }
        }
    }
}

/// EXIF preview content component.
struct EXIFPreviewContent: View {
    var body: some View {
        HStack(spacing: 2) {
            Text("50mm")
                .font(.custom("AvenirNext-Medium", size: 10))
                .kerning(0.3)
                .foregroundColor(.primary.opacity(0.8))
            Text(" ")
                .font(.system(size: 10, weight: .light))
            Text("f/1.8")
                .font(.custom("AvenirNext-Medium", size: 10))
                .kerning(0.3)
                .foregroundColor(.primary.opacity(0.8))
        }
    }
}

/// Apple icon preview content component.
struct AppleIconPreviewContent: View {
    var body: some View {
        Image(systemName: "apple.logo")
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.primary.opacity(0.8))
    }
}

/// Device model preview content component.
struct DeviceModelPreviewContent: View {
    var body: some View {
        Text("iPhone")
            .font(.custom("AvenirNext-DemiBold", size: 10))
            .kerning(0.2)
            .foregroundColor(.primary.opacity(0.8))
    }
}

/// Shooting date preview content component.
struct DatePreviewContent: View {
    var body: some View {
        Text("2024/12/25")
            .font(.custom("AvenirNext-Medium", size: 10))
            .kerning(0.3)
            .foregroundColor(.primary.opacity(0.8))
    }
}

/// Shooting time preview content component.
struct TimePreviewContent: View {
    var body: some View {
        Text("14:30")
            .font(.custom("AvenirNext-Medium", size: 10))
            .kerning(0.3)
            .foregroundColor(.primary.opacity(0.8))
    }
}

/// Shooting location preview content component.
struct LocationPreviewContent: View {
    var body: some View {
        HStack(spacing: 2) {
            Text("NYC")
                .font(.custom("AvenirNext-Medium", size: 10))
                .kerning(0.3)
                .foregroundColor(.primary.opacity(0.8))
        }
    }
}

/// Copyright information preview content component.
struct CopyrightPreviewContent: View {
    var body: some View {
        Text("© YOYO")
            .font(.custom("AvenirNext-Medium", size: 10))
            .kerning(0.3)
            .foregroundColor(.primary.opacity(0.8))
    }
}

/// Holiday watermark preview content component.
struct FestivalWatermarkPreviewContent: View {
    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.primary.opacity(0.8))
    }
}

// MARK: - Photo frame preview schematic component
/// No-frame preview.
struct FramePreviewNone: View {
    var body: some View {
        ZStack {
            // Picture area.
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.gray.opacity(0.4))
                .frame(width: 36, height: 36)

            // Forbidden icon.
            Image(systemName: "nosign")
                .font(.system(size: 18, weight: .light))
                .foregroundColor(.gray.opacity(0.5))
        }
    }
}

/// Polaroid photo frame preview.
struct FramePreviewPolaroid: View {
    var body: some View {
        ZStack {
            // Background.
            Color.gray.opacity(0.08)

            // Photo frame outer frame.
            VStack(spacing: 0) {
                // Picture area.
                Rectangle()
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: 32, height: 32)

                // Bottom white area.
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 32, height: 10)
            }
            .padding(3)
            .background(Color.white)
            .cornerRadius(1)
            .shadow(color: .black.opacity(0.12), radius: 1.5, x: 0, y: 1)
            .compositingGroup()
        }
    }
}

/// Blurred border preview.
struct FramePreviewBlurred: View {
    var body: some View {
        ZStack {
            // Blurred background simulated with color blocks.
            ZStack {
                // Multi-layer blur color block simulates blur.
                Circle()
                    .fill(Color.blue.opacity(0.25))
                    .frame(width: 30, height: 30)
                    .offset(x: -12, y: -10)
                    .blur(radius: 8)

                Circle()
                    .fill(Color.orange.opacity(0.2))
                    .frame(width: 25, height: 25)
                    .offset(x: 15, y: 12)
                    .blur(radius: 6)

                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 20, height: 20)
                    .offset(x: 10, y: -8)
                    .blur(radius: 5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .compositingGroup()

            // Clear center image area.
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.gray.opacity(0.55))
                .frame(width: 36, height: 36)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.white.opacity(0.5), lineWidth: 0.5)
                )
        }
    }
}

/// Bottom border preview.
struct FramePreviewBottomOnly: View {
    var body: some View {
        ZStack {
            // Background.
            Color.gray.opacity(0.08)

            // Photo frame structure.
            VStack(spacing: 0) {
                // Picture area with no side borders.
                Rectangle()
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: 36, height: 36)

                // Bottom white border.
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 36, height: 8)
            }
            .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 0.5)
            .compositingGroup()
        }
    }
}

#Preview {
    FrameSettingsView(frameManager: FrameManager.shared)
}
