import Combine
import SwiftUI

/// A SwiftUI wrapper for hosting a HistogramOverlayView in a CameraPreviewContainerView.
struct HistogramHost: UIViewRepresentable {
    let previewRenderController: PreviewRenderController

    func makeUIView(context: Context) -> HistogramView {
        let view = HistogramView()
        view.backgroundColor = .clear
        context.coordinator.setup(previewRenderController: previewRenderController, histogramView: view)
        return view
    }

    func updateUIView(_ uiView: HistogramView, context: Context) {
        context.coordinator.setup(previewRenderController: previewRenderController, histogramView: uiView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private var cancellables = Set<AnyCancellable>()
        private weak var histogramView: HistogramView?
        private weak var currentController: PreviewRenderController?

        func setup(previewRenderController: PreviewRenderController, histogramView: HistogramView) {
            guard currentController !== previewRenderController || self.histogramView !== histogramView else { return }

            currentController = previewRenderController
            self.histogramView = histogramView

            cancellables.removeAll()
            previewRenderController.frameSubject
                .receive(on: DispatchQueue.main)
                .sink { [weak histogramView] buffer in
                    histogramView?.updateHistogram(from: buffer)
                }
                .store(in: &cancellables)
        }
    }
}
