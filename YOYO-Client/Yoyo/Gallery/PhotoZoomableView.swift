import AVFoundation
import AVKit
import Photos
import PhotosUI
import SwiftUI
import UIKit

struct PhotoZoomableViewRepresentable: UIViewRepresentable {
    let image: UIImage?
    let livePhoto: PHLivePhoto?
    let player: AVPlayer?
    let videoControls: VideoControls?
    let livePhotoControls: LivePhotoControls?
    var isVisible: Bool = true
    var imageContentMode: PhotoZoomableView.ScaleMode = .aspectFit
    var initialOffset: PhotoZoomableView.Offset = .center
    var maxScaleFromMinScale: CGFloat = 20.0
    var onSingleTap: (() -> Void)?

    init(
        image: UIImage? = nil,
        livePhoto: PHLivePhoto? = nil,
        player: AVPlayer? = nil,
        videoControls: VideoControls? = nil,
        livePhotoControls: LivePhotoControls? = nil,
        isVisible: Bool = true,
        imageContentMode: PhotoZoomableView.ScaleMode = .aspectFit,
        initialOffset: PhotoZoomableView.Offset = .center,
        maxScaleFromMinScale: CGFloat = 20.0,
        onSingleTap: (() -> Void)? = nil
    ) {
        self.image = image
        self.livePhoto = livePhoto
        self.player = player
        self.videoControls = videoControls
        self.livePhotoControls = livePhotoControls
        self.isVisible = isVisible
        self.imageContentMode = imageContentMode
        self.initialOffset = initialOffset
        self.maxScaleFromMinScale = maxScaleFromMinScale
        self.onSingleTap = onSingleTap
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSingleTap: onSingleTap)
    }

    func makeUIView(context: Context) -> PhotoZoomableView {
        let view = PhotoZoomableView()
        view.imageContentMode = imageContentMode
        view.initialOffset = initialOffset
        view.maxScaleFromMinScale = maxScaleFromMinScale
        view.videoControls = videoControls
        view.livePhotoControls = livePhotoControls
        view.photoZoomableViewDelegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: PhotoZoomableView, context: Context) {
        uiView.imageContentMode = imageContentMode
        uiView.initialOffset = initialOffset
        uiView.maxScaleFromMinScale = maxScaleFromMinScale
        uiView.videoControls = videoControls
        uiView.livePhotoControls = livePhotoControls
        applyContent(to: uiView)
        uiView.photoZoomableViewDelegate = context.coordinator
    }

    static func dismantleUIView(_ uiView: PhotoZoomableView, coordinator _: Coordinator) {
        uiView.livePhotoView?.stopPlayback()
        uiView.videoPlayerController?.player?.pause()
    }

    /// Unify content updates and reduce branch duplication.
    private func applyContent(to uiView: PhotoZoomableView) {
        if let player, let controls = videoControls {
            if uiView.videoPlayerController?.player !== player {
                uiView.display(player: player, isPlaying: controls.isPlaying && isVisible, playbackRate: controls.playbackRate)
                player.isMuted = controls.isMuted
                uiView.setup()
            } else {
                player.isMuted = controls.isMuted
                if controls.isPlaying, isVisible {
                    player.play()
                    player.rate = controls.playbackRate
                } else {
                    player.pause()
                }
            }
            return
        }

        if let livePhoto {
            if uiView.livePhotoView?.livePhoto !== livePhoto {
                let isPlaying = (livePhotoControls?.isPlaying ?? true) && isVisible
                let isLooping = livePhotoControls?.isLooping ?? true
                uiView.display(livePhoto: livePhoto, isPlaying: isPlaying, isLooping: isLooping)
                uiView.setup()
                uiView.lastPlaybackTrigger = livePhotoControls?.playbackTrigger ?? 0
            } else {
                if !isVisible {
                    uiView.livePhotoView?.stopPlayback()
                } else if let controls = livePhotoControls {
                    if controls.playbackTrigger != uiView.lastPlaybackTrigger {
                        uiView.lastPlaybackTrigger = controls.playbackTrigger
                        uiView.livePhotoView?.stopPlayback()
                        uiView.livePhotoView?.startPlayback(with: .full)
                    } else if controls.isPlaying {
                        uiView.livePhotoView?.startPlayback(with: .full)
                    } else {
                        uiView.livePhotoView?.stopPlayback()
                    }
                }
            }
            return
        }

        if let image {
            if uiView.zoomView?.image !== image {
                uiView.display(image: image)
                uiView.setup()
            }
            return
        }

        uiView.livePhotoView?.stopPlayback()
        uiView.videoPlayerController?.player?.pause()
    }

    final class Coordinator: NSObject, PhotoZoomableViewDelegate {
        let onSingleTap: (() -> Void)?
        init(onSingleTap: (() -> Void)?) {
            self.onSingleTap = onSingleTap
        }

        func photoZoomableViewDidSingleTap(photoZoomableView _: PhotoZoomableView) {
            onSingleTap?()
        }

        func photoZoomableViewDidChangeOrientation(photoZoomableView _: PhotoZoomableView) {}
    }
}

@objc public protocol PhotoZoomableViewDelegate: UIScrollViewDelegate {
    func photoZoomableViewDidChangeOrientation(photoZoomableView: PhotoZoomableView)
    @objc optional func photoZoomableViewDidSingleTap(photoZoomableView: PhotoZoomableView)
}

open class PhotoZoomableView: UIScrollView {
    @objc public enum ScaleMode: Int {
        case aspectFill
        case aspectFit
        case widthFill
        case heightFill
    }

    @objc public enum Offset: Int {
        case begining
        case center
    }

    static let kZoomInFactorFromMinWhenDoubleTap: CGFloat = 5

    @objc open var imageContentMode: ScaleMode = .widthFill
    @objc open var initialOffset: Offset = .begining

    @objc public private(set) var zoomView: UIImageView?
    @objc public private(set) var livePhotoView: PHLivePhotoView?
    @objc public private(set) var videoPlayerController: AVPlayerViewController?

    @objc open weak var photoZoomableViewDelegate: PhotoZoomableViewDelegate?

    var imageSize: CGSize = .zero
    open var maxScaleFromMinScale: CGFloat = 10.0
    private var isDisplayingLivePhoto: Bool = false
    private var isDisplayingVideo: Bool = false
    var videoControls: VideoControls?
    var livePhotoControls: LivePhotoControls?
    var lastPlaybackTrigger: Int = 0
    private var playbackEndObserver: NSObjectProtocol?

    /// The view currently displayed inside the scroll view.
    private var contentView: UIView? {
        if isDisplayingVideo { return videoPlayerController?.view }
        if isDisplayingLivePhoto { return livePhotoView }
        return zoomView
    }

    override public init(frame: CGRect) {
        super.init(frame: frame)
        initialize()
    }

    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        initialize()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func initialize() {
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        bouncesZoom = true
        decelerationRate = .fast
        delegate = self
        bounces = false
        if #available(iOS 11.0, *) {
            contentInsetAdjustmentBehavior = .never
        }
        minimumZoomScale = 1.0
        maximumZoomScale = 1.0

        NotificationCenter.default.addObserver(self, selector: #selector(PhotoZoomableView.changeOrientationNotification), name: UIDevice.orientationDidChangeNotification, object: nil)
    }

    @objc public func adjustFrameToCenter() {
        guard let unwrappedView = contentView else {
            return
        }

        var frameToCenter = unwrappedView.frame

        // center horizontally
        if frameToCenter.size.width < bounds.width {
            frameToCenter.origin.x = (bounds.width - frameToCenter.size.width) / 2
        } else {
            frameToCenter.origin.x = 0
        }

        // center vertically
        if frameToCenter.size.height < bounds.height {
            frameToCenter.origin.y = (bounds.height - frameToCenter.size.height) / 2
        } else {
            frameToCenter.origin.y = 0
        }

        unwrappedView.frame = frameToCenter
    }

    // MARK: - Set up

    open func setup() {
        DispatchQueue.main.async {
            self.refresh()
        }
    }

    // MARK: - Display image

    open func display(image: UIImage) {
        clearCurrentDisplay()

        zoomView = UIImageView(image: image)
        zoomView!.isUserInteractionEnabled = true
        addSubview(zoomView!)
        addGestures(to: zoomView!)

        isDisplayingLivePhoto = false
        isDisplayingVideo = false
        configureImageForSize(image.size)
    }

    @objc open func display(livePhoto: PHLivePhoto, isPlaying: Bool = true, isLooping _: Bool = true) {
        clearCurrentDisplay()

        livePhotoView = PHLivePhotoView()
        livePhotoView!.livePhoto = livePhoto
        livePhotoView!.isUserInteractionEnabled = true
        addSubview(livePhotoView!)
        addGestures(to: livePhotoView!)

        isDisplayingLivePhoto = true
        isDisplayingVideo = false
        let size = livePhoto.size
        livePhotoView!.frame = CGRect(origin: .zero, size: size)
        configureImageForSize(size)

        if isPlaying {
            livePhotoView!.startPlayback(with: .full)
        } else {
            livePhotoView!.stopPlayback()
        }
    }

    @objc open func display(player: AVPlayer, isPlaying: Bool = true, playbackRate: Float = 1.0) {
        clearCurrentDisplay()

        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.allowsPictureInPicturePlayback = true
        controller.videoGravity = .resizeAspect

        // Clean up old observers first.
        if let observer = playbackEndObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        // Monitor the end of playback and loop automatically.
        playbackEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak player, weak self] _ in
            player?.seek(to: .zero)
            player?.play()
            player?.rate = self?.videoControls?.playbackRate ?? 1.0
        }

        videoPlayerController = controller
        controller.view.isUserInteractionEnabled = true

        // Add AVPlayerViewController's view to the scroll view.
        addSubview(controller.view)
        addGestures(to: controller.view)

        isDisplayingLivePhoto = false
        isDisplayingVideo = true

        // Get video size.
        if let track = player.currentItem?.asset.tracks(withMediaType: .video).first {
            let size = track.naturalSize.applying(track.preferredTransform)
            let videoSize = CGSize(width: abs(size.width), height: abs(size.height))
            controller.view.frame = CGRect(origin: .zero, size: videoSize)
            configureImageForSize(videoSize)
        } else {
            // Fall back when video size cannot be determined.
            let defaultSize = CGSize(width: bounds.width, height: bounds.height)
            controller.view.frame = CGRect(origin: .zero, size: defaultSize)
            configureImageForSize(defaultSize)
        }

        // Determine playback state.
        if isPlaying {
            player.play()
            // Keep the requested playback rate instead of the system default.
            player.rate = playbackRate
        } else {
            player.pause()
        }
    }

    private func clearCurrentDisplay() {
        if let zoomView {
            zoomView.removeFromSuperview()
            self.zoomView = nil
        }

        if let livePhotoView {
            livePhotoView.removeFromSuperview()
            self.livePhotoView = nil
        }

        if let videoPlayerController {
            videoPlayerController.player?.pause()
            if let observer = playbackEndObserver {
                NotificationCenter.default.removeObserver(observer)
                playbackEndObserver = nil
            }
            videoPlayerController.view.removeFromSuperview()
            self.videoPlayerController = nil
        }
    }

    private func addGestures(to view: UIView) {
        let doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(doubleTapGestureRecognizer(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        let singleTapGesture = UITapGestureRecognizer(target: self, action: #selector(singleTapGestureRecognizer(_:)))
        singleTapGesture.numberOfTapsRequired = 1
        singleTapGesture.require(toFail: doubleTapGesture)
        view.addGestureRecognizer(singleTapGesture)
        view.addGestureRecognizer(doubleTapGesture)
    }

    private func configureImageForSize(_ size: CGSize) {
        imageSize = size
        contentSize = imageSize
        setMaxMinZoomScalesForCurrentBounds()
        zoomScale = minimumZoomScale

        switch initialOffset {
        case .begining:
            contentOffset = .zero
        case .center:
            let xOffset = contentSize.width < bounds.width ? 0 : (contentSize.width - bounds.width) / 2
            let yOffset = contentSize.height < bounds.height ? 0 : (contentSize.height - bounds.height) / 2

            switch imageContentMode {
            case .aspectFit:
                contentOffset = .zero
            case .aspectFill:
                contentOffset = CGPoint(x: xOffset, y: yOffset)
            case .heightFill:
                contentOffset = CGPoint(x: xOffset, y: 0)
            case .widthFill:
                contentOffset = CGPoint(x: 0, y: yOffset)
            }
        }
    }

    private func setMaxMinZoomScalesForCurrentBounds() {
        guard bounds.width > 0, bounds.height > 0, imageSize.width > 0, imageSize.height > 0 else {
            return
        }

        let xScale = bounds.width / imageSize.width
        let yScale = bounds.height / imageSize.height

        var minScale: CGFloat = 1

        switch imageContentMode {
        case .aspectFill:
            minScale = max(xScale, yScale)
        case .aspectFit:
            minScale = min(xScale, yScale)
        case .widthFill:
            minScale = xScale
        case .heightFill:
            minScale = yScale
        }

        let maxScale = maxScaleFromMinScale * minScale

        if minScale > maxScale {
            minScale = maxScale
        }

        maximumZoomScale = max(maxScale, 0.0001)
        minimumZoomScale = max(minScale * 0.999, 0.0001)
    }

    // MARK: - Gesture

    @objc func doubleTapGestureRecognizer(_ gestureRecognizer: UIGestureRecognizer) {
        // zoom out if it bigger than the scale factor after double-tap scaling. Else, zoom in
        if zoomScale >= minimumZoomScale * PhotoZoomableView.kZoomInFactorFromMinWhenDoubleTap - 0.01 {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let center = gestureRecognizer.location(in: gestureRecognizer.view)
            let zoomRect = zoomRectForScale(PhotoZoomableView.kZoomInFactorFromMinWhenDoubleTap * minimumZoomScale, center: center)
            zoom(to: zoomRect, animated: true)
        }
    }

    private func zoomRectForScale(_ scale: CGFloat, center: CGPoint) -> CGRect {
        var zoomRect = CGRect.zero

        // the zoom rect is in the content view's coordinates.
        // at a zoom scale of 1.0, it would be the size of the photoZoomableView's bounds.
        // as the zoom scale decreases, so more content is visible, the size of the rect grows.
        zoomRect.size.height = frame.size.height / scale
        zoomRect.size.width = frame.size.width / scale

        // choose an origin so as to get the right center.
        zoomRect.origin.x = center.x - (zoomRect.size.width / 2.0)
        zoomRect.origin.y = center.y - (zoomRect.size.height / 2.0)

        return zoomRect
    }

    open func refresh() {
        if let player = videoPlayerController?.player {
            if let controls = videoControls {
                display(player: player, isPlaying: controls.isPlaying, playbackRate: controls.playbackRate)
                player.isMuted = controls.isMuted
            }
        } else if let image = zoomView?.image {
            display(image: image)
        } else if let livePhoto = livePhotoView?.livePhoto {
            display(livePhoto: livePhoto)
        }
    }

    override open func layoutSubviews() {
        super.layoutSubviews()
        adjustFrameToCenter()
    }

    // MARK: - Actions

    @objc func changeOrientationNotification() {
        // A weird bug that frames are not update right after orientation changed. Need delay a little bit with async.
        DispatchQueue.main.async {
            self.configureImageForSize(self.imageSize)
            self.photoZoomableViewDelegate?.photoZoomableViewDidChangeOrientation(photoZoomableView: self)
        }
    }

    @objc func singleTapGestureRecognizer(_: UIGestureRecognizer) {
        photoZoomableViewDelegate?.photoZoomableViewDidSingleTap?(photoZoomableView: self)
    }
}

extension PhotoZoomableView: UIScrollViewDelegate {
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        photoZoomableViewDelegate?.scrollViewDidScroll?(scrollView)
    }

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        photoZoomableViewDelegate?.scrollViewWillBeginDragging?(scrollView)
    }

    public func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        photoZoomableViewDelegate?.scrollViewWillEndDragging?(scrollView, withVelocity: velocity, targetContentOffset: targetContentOffset)
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        photoZoomableViewDelegate?.scrollViewDidEndDragging?(scrollView, willDecelerate: decelerate)
    }

    public func scrollViewWillBeginDecelerating(_ scrollView: UIScrollView) {
        photoZoomableViewDelegate?.scrollViewWillBeginDecelerating?(scrollView)
    }

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        photoZoomableViewDelegate?.scrollViewDidEndDecelerating?(scrollView)
    }

    public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        photoZoomableViewDelegate?.scrollViewDidEndScrollingAnimation?(scrollView)
    }

    public func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        photoZoomableViewDelegate?.scrollViewWillBeginZooming?(scrollView, with: view)
    }

    public func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        photoZoomableViewDelegate?.scrollViewDidEndZooming?(scrollView, with: view, atScale: scale)
    }

    public func scrollViewShouldScrollToTop(_: UIScrollView) -> Bool {
        false
    }

    @available(iOS 11.0, *)
    public func scrollViewDidChangeAdjustedContentInset(_ scrollView: UIScrollView) {
        photoZoomableViewDelegate?.scrollViewDidChangeAdjustedContentInset?(scrollView)
    }

    public func viewForZooming(in _: UIScrollView) -> UIView? {
        contentView
    }

    public func scrollViewDidZoom(_ scrollView: UIScrollView) {
        adjustFrameToCenter()
        photoZoomableViewDelegate?.scrollViewDidZoom?(scrollView)
    }
}
