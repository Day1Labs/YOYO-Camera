import SwiftUI

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension View {
    func frame(size: CGSize) -> some View {
        frame(width: size.width, height: size.height)
    }

    func eraseToAny() -> AnyView {
        AnyView(self)
    }
}
