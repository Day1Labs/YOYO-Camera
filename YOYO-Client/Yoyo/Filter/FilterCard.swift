import SwiftUI

/// Defines the visual styling of a filter card.
struct FilterCardStyle {
    var backgroundColor: Color
    var primaryColor: Color
    var secondaryColor: Color?
    var shape: AnyShape
    var textAlignment: HorizontalAlignment = .leading
    var font: Font = .system(size: 20)
    var borderColor: Color?
}

// MARK: - Reusable FilterCard View

struct FilterCard: View {
    let displayConfig: FilterDisplayConfig

    var body: some View {
        ZStack {
            displayConfig.cardStyle.backgroundColor
            ImageBackgroundLayout(displayConfig: displayConfig)
        }
        .frame(width: 300, height: 225)
        .clipShape(displayConfig.cardStyle.shape)
    }
}

// MARK: - Preview

struct FilterCard_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("All Filter Cards")
                    .font(.largeTitle.bold())
                // Here you can use FilterConfigurationManager.shared.getAllConfigs() to Preview
                ForEach(FilterConfigManager.shared.getAllConfigs(), id: \ .display.name) { config in
                    FilterCard(displayConfig: config.display)
                        .frame(width: 300, height: 225)
                        .scaleEffect(0.5)
                }
            }
            .padding()
        }
    }
}
