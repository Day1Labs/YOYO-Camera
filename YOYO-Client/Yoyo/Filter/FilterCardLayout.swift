import SwiftUI

// MARK: - Filter Temperature Styling Helper

struct FilterTemperatureStyle {
    let backgroundColor: Color
    let textColor: Color
    let icon: String

    static func forText(_ text: String?) -> FilterTemperatureStyle {
        switch text?.lowercased() {
        case "warm":
            return FilterTemperatureStyle(backgroundColor: .orange, textColor: .white, icon: "sun.max.fill")
        case "cool":
            return FilterTemperatureStyle(backgroundColor: .blue, textColor: .white, icon: "snowflake")
        case "neutral":
            return FilterTemperatureStyle(backgroundColor: .gray, textColor: .white, icon: "thermometer")
        case "bw":
            return FilterTemperatureStyle(backgroundColor: .black, textColor: .white, icon: "circle.lefthalf.filled")
        default:
            return FilterTemperatureStyle(backgroundColor: .gray, textColor: .white, icon: "thermometer")
        }
    }
}

// MARK: - Filter Look Styling Helper

enum FilterLookStyle {
    static func underlineColor(for styleText: String?) -> Color {
        guard let text = styleText?.lowercased() else {
            return Color(red: 0.8, green: 0.8, blue: 0.8) // Soft gray
        }
        return Color(red: 1, green: 1, blue: 1) // Soft white instead of pure white
    }
}

struct ImageBackgroundLayout: View {
    let displayConfig: FilterDisplayConfig

    var body: some View {
        ZStack {
            // background gradient
            if !displayConfig.isFilmSimulation {
                LinearGradient(
                    gradient: Gradient(colors: [
                        displayConfig.cardStyle.backgroundColor,
                        displayConfig.cardStyle.backgroundColor.opacity(0.8),
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            // Background image (if provided)
            if let imageName = displayConfig.imageName {
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 300, height: 225)
                    .clipped()
                    .opacity(displayConfig.isFilmSimulation ? 0.8 : 1.0)
            }

            // Text content
            if !displayConfig.isFilmSimulation {
                VStack {
                    HStack {
                        // Upper left corner text
                        if let primaryText = displayConfig.primaryText {
                            VStack(alignment: .leading) {
                                Text(primaryText)
                                    .font(.system(size: 36, weight: .heavy))
                                    .foregroundColor(
                                        displayConfig.cardStyle.primaryColor
                                    )
                            }
                        }
                        Spacer()
                    }
                    .padding(.top, 16)
                    .padding(.horizontal, 16)
                    Spacer()
                    // Bottom text (if required)
                    if (displayConfig.tertiaryText != nil) || (displayConfig.secondaryText != nil) {
                        HStack {
                            if let secondaryText = displayConfig.secondaryText {
                                let underlineColor = FilterLookStyle.underlineColor(for: secondaryText)
                                Text(secondaryText)
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundColor(underlineColor)
                                    .overlay(
                                        // Enhanced underline with gradient and shadow
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(
                                                LinearGradient(
                                                    gradient: Gradient(colors: [
                                                        underlineColor,
                                                        underlineColor.opacity(0.7),
                                                    ]),
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .frame(height: 8)
                                            .shadow(color: underlineColor.opacity(0.3), radius: 2, x: 0, y: 1)
                                            .offset(y: 8),
                                        alignment: .bottom
                                    )
                                    .padding(.bottom, 8)
                            }
                            Spacer()
                            if let tertiaryText = displayConfig.tertiaryText {
                                let tempStyle = FilterTemperatureStyle.forText(tertiaryText)
                                HStack {
                                    Image(systemName: tempStyle.icon)
                                    Text(tertiaryText)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(tempStyle.backgroundColor.opacity(0.8))
                                .foregroundColor(tempStyle.textColor)
                                .font(.system(size: 20, weight: .medium, design: .monospaced))
                                .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
            }
        }
        .frame(width: 300, height: 225)
    }
}
