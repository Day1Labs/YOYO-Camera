import AVFoundation
import CoreImage
import CoreMotion
import UIKit

// MARK: - PhotoProcessorDelegate Protocol

protocol PhotoProcessorDelegate: AnyObject {
    func photoProcessor(_ processor: PhotoProcessor, didFinishProcessing result: CaptureResult)
    func photoProcessor(_ processor: PhotoProcessor, didFailWithError error: Error?)
}

// MARK: - PhotoProcessor

/// A class dedicated to photo capture and image processing
/// Responsibilities:
/// 1. implement AVCapturePhotoCaptureDelegate
/// 2. RAW and JPEG image
/// 3. coordinateshared componentscompleteimage
final class PhotoProcessor: NSObject {
    // MARK: - Singleton

    static let shared = PhotoProcessor()

    // MARK: - Properties

    weak var delegate: PhotoProcessorDelegate?

    private var aspectRatio: Double = 3.0 / 4.0

    /// Temporary storage for regular photo capture
    private var photoCaptureCompletion: ((Data?) -> Void)?

    // Shared components
    private let imageProcessor = ImageProcessor.shared
    private let metadataBuilder = MetadataBuilder.shared

    /// Parallel processing queue that supports handling multiple photos at the same time (Option B)
    private let processingQueue = DispatchQueue(label: "com.day1-labs.yoyo.photo.processing", qos: .userInitiated, attributes: .concurrent)

    // MARK: - Initialization

    override private init() {
        super.init()
    }

    // MARK: - Deinitialization

    deinit {
        print("🗑️ [PhotoProcessor] deinit called - Cleaning up resources")
        // Clean up temporary data
        photoCaptureCompletion = nil
        // Clean up shared component caches
        imageProcessor.clearCaches()
        print("✅ [PhotoProcessor] deinit complete")
    }

    // MARK: - Performance Monitoring

    /// Get current memory usage (MB)
    private func getMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                          task_flavor_t(MACH_TASK_BASIC_INFO),
                          $0,
                          &count)
            }
        }

        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / 1024.0 / 1024.0
        } else {
            return 0.0
        }
    }

    // MARK: - Public Methods

    func updateAspectRatio(_ ratio: Double) {
        aspectRatio = ratio
    }

    /// Set the photo completion callback
    func setPhotoCaptureCompletion(_ completion: @escaping (Data?) -> Void) {
        photoCaptureCompletion = completion
    }

    // MARK: - Internal Result Structure

    private struct InternalProcessedResult {
        let processedImages: ProcessedImageResult
        let metadata: [String: Any]
        let originalImageData: Data?
        let isRaw: Bool
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension PhotoProcessor: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        print("📸 [PhotoOutput] 🎯 DELEGATE METHOD CALLED! 拍照委托方法被系统调用")
        print("📸 [PhotoOutput] Photo uniqueID: \(photo.resolvedSettings.uniqueID)")
        print("📸 [PhotoOutput] Is RAW: \(photo.isRawPhoto)")

        let processStartTime = Date()
        let startMemory = getMemoryUsage()
        print("📸 [PhotoOutput] ===== 拍照处理开始 =====")
        print("📸 [PhotoOutput] 初始内存: \(String(format: "%.1f", startMemory))MB")

        // Capture completion handler
        guard let completion = photoCaptureCompletion else {
            print("⚠️ [PhotoOutput] photoCaptureCompletion is nil, early return")
            return
        }
        photoCaptureCompletion = nil

        // Handle error case
        if let error {
            print("❌ [PhotoOutput] 拍照过程中发生错误: \(error.localizedDescription)")
            completion(nil)
            delegate?.photoProcessor(self, didFailWithError: error)
            return
        }

        // Capture state for concurrent processing
        let currentAspectRatio = aspectRatio

        // [FIX] Capture device orientation AT CAPTURE TIME
        // Capture the device orientation at the moment of shooting for RAW correction. This avoids incorrect orientation if the user rotates the device while processing on a background thread.
        // Use `OrientationManager` (based on CoreMotion) instead of `UIDevice.current` to get more accurate, real-time orientation data.
        let currentOrientation = OrientationManager.shared.currentDeviceOrientation
        let currentCameraPosition = CameraDeviceManager.shared.currentCameraDeviceType == .frontWide ? AVCaptureDevice.Position.front : .back

        // Request a background task to ensure image processing can finish even if the app goes to the background or the screen locks
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        if Thread.isMainThread {
            backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "com.day1-labs.yoyo.photo.process") {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
            }
        } else {
            DispatchQueue.main.sync {
                backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "com.day1-labs.yoyo.photo.process") {
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                }
            }
        }

        if backgroundTaskID != .invalid {
            print("⏳ [PhotoProcessor] 开启后台保活任务 (ID: \(backgroundTaskID))")
        }

        // Process photo in background
        processingQueue.async { [weak self] in
            // Notify the system to end the background task after processing completes
            defer {
                if backgroundTaskID != .invalid {
                    let taskToEnd = backgroundTaskID
                    DispatchQueue.main.async {
                        UIApplication.shared.endBackgroundTask(taskToEnd)
                    }
                    backgroundTaskID = .invalid
                    print("✅ [PhotoProcessor] 后台保活任务结束")
                }
            }

            autoreleasepool {
                guard let self else { return }
                var result: InternalProcessedResult?

                let imageData = photo.fileDataRepresentation()
                print("📸 [PhotoOutput] Got image data - Size: \(imageData?.count ?? 0) bytes")

                guard let imageData else {
                    print("❌ [PhotoOutput] Failed to get image data representation")
                    DispatchQueue.main.async { [weak self] in
                        completion(nil)
                        self?.delegate?.photoProcessor(self!, didFailWithError: nil)
                    }
                    return
                }

                // Process image
                if photo.isRawPhoto == true {
                    print("🎨 [ImageProcess] 处理RAW格式图片")
                    result = self.processRAWInBackground(
                        metadata: photo.metadata,
                        originalImageData: imageData,
                        aspectRatio: currentAspectRatio,
                        applyFilter: true,
                        captureOrientation: currentOrientation,
                        cameraPosition: currentCameraPosition
                    )
                } else {
                    print("🎨 [ImageProcess] 处理JPEG格式图片")
                    result = self.processImageInBackground(
                        imageData: imageData,
                        metadata: photo.metadata,
                        aspectRatio: currentAspectRatio,
                        applyFilter: true
                    )
                }

                guard let result else {
                    print("❌ [PhotoOutput] Failed to process image")
                    DispatchQueue.main.async { [weak self] in
                        completion(nil)
                        self?.delegate?.photoProcessor(self!, didFailWithError: nil)
                    }
                    return
                }

                let totalDuration = Date().timeIntervalSince(processStartTime)
                let totalEndMemory = self.getMemoryUsage()
                print("📸 [PhotoOutput] ===== 拍照处理完成 =====")
                print("📸 [PhotoOutput] 总耗时: \(String(format: "%.3f", totalDuration))s")
                print("📸 [PhotoOutput] 总内存增长: \(String(format: "%.1f", totalEndMemory - startMemory))MB")

                // Check whether this is Live Photo mode (from `photo.resolvedSettings`)
                let isLivePhoto = photo.resolvedSettings.livePhotoMovieDimensions.width > 0 && photo.resolvedSettings.livePhotoMovieDimensions.height > 0

                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if isLivePhoto {
                        // Live Photo mode: create metadata containing `uniqueID` and return it through the delegate
                        print("🎬 [PhotoOutput] LivePhoto mode - Creating result with uniqueID")

                        var updatedMetadata = result.metadata
                        updatedMetadata["uniqueID"] = Int(photo.resolvedSettings.uniqueID)

                        let captureResult = CaptureResult(
                            originalImage: result.processedImages.originalImage,
                            filteredImage: result.processedImages.filteredImage,
                            metadata: updatedMetadata,
                            livePhotoURL: nil, // Set later by the video callback
                            originalImageData: result.originalImageData,
                            isRaw: result.isRaw
                        )

                        self.delegate?.photoProcessor(self, didFinishProcessing: captureResult)
                        // Live Photo does not need to call `completion`; `CameraCaptureService` handles it after video processing finishes
                    } else {
                        // Regular photo mode: call back directly
                        self.handleProcessedResult(result, completion: completion)
                    }

                    CameraDeviceManager.shared.setAutoWhiteBalanceContinuous()
                }
            }
        }
    }
}

// MARK: - Image Processing Methods

private extension PhotoProcessor {
    /// Process RAW images
    private func processRAWInBackground(
        metadata: [String: Any],
        originalImageData: Data,
        aspectRatio: Double,
        applyFilter: Bool,
        captureOrientation: UIDeviceOrientation,
        cameraPosition: AVCaptureDevice.Position
    ) -> InternalProcessedResult? {
        autoreleasepool {
            do {
                let type = UTType(filenameExtension: "dng")
                let rawFilter = CIRAWFilter(
                    imageData: originalImageData,
                    identifierHint: type?.identifier
                )

                guard let rawFilter else {
                    print("❌ [PhotoProcessor] processRAWInBackground: Failed to create CIRAWFilter")
                    throw NSError(domain: "com.day1-labs.yoyo", code: -1)
                }

                // [NEW] Configure RAW filter before getting outputImage

                // TODO: determine night mode
                let isNight = false

                FilterManager.shared.configureRawFilter(
                    rawFilter,
                    isNight: isNight,
                    deviceOrientation: captureOrientation,
                    cameraPosition: cameraPosition
                )

                if let outputImage = rawFilter.outputImage {
                    print("✅ [RAW] Output image created successfully")
                    print("📊 [RAW] Output extent: \(outputImage.extent)")
                    print("📊 [RAW] Output colorSpace: \(outputImage.colorSpace?.name as String? ?? "nil")")

                    return self.processCIImageWithSharedComponents(
                        outputImage,
                        metadata: metadata,
                        originalImageData: originalImageData,
                        aspectRatio: aspectRatio,
                        applyFilter: applyFilter,
                        isRaw: true,
                        // Force the orientation to `.up` because `configureRawFilter` has already corrected the pixel orientation
                        // [FIX] Force `.up` only for the front camera (because we corrected the front camera orientation in `configureRawFilter`)
                        // For the rear camera (RAW not corrected), pass `nil` so `ImageProcessor` can compute the `UIImage` orientation automatically from `OrientationManager`
                        fixedOrientation: cameraPosition == .front ? .up : nil
                    )
                } else {
                    print("❌ [PhotoProcessor] processRAWInBackground: RAW filter output image is nil")
                }
            } catch {
                print("❌ [PhotoProcessor] processRAWInBackground: CIRAWFilter creation failed with error: \(error)")
            }

            return nil
        }
    }

    /// Process JPEG images
    private func processImageInBackground(
        imageData: Data,
        metadata: [String: Any],
        aspectRatio: Double,
        applyFilter: Bool
    ) -> InternalProcessedResult {
        autoreleasepool {
            let jpegProcessStart = Date()
            print("🖼️ [JPEGProcess] 开始JPEG处理")

            let options = [CIImageOption.applyOrientationProperty: true]
            guard let ciImage = CIImage(data: imageData, options: options) else {
                print("❌ [PhotoProcessor] processImageInBackground: Failed to create CIImage from image data")
                let emptyResult = ProcessedImageResult(originalImage: UIImage(), filteredImage: UIImage())
                return InternalProcessedResult(
                    processedImages: emptyResult,
                    metadata: metadata,
                    originalImageData: imageData,
                    isRaw: false
                )
            }

            let ciImageCreateTime = Date().timeIntervalSince(jpegProcessStart)
            print("🖼️ [JPEGProcess] CIImage创建耗时: \(String(format: "%.3f", ciImageCreateTime))s")

            let result = processCIImageWithSharedComponents(
                ciImage,
                metadata: metadata,
                originalImageData: imageData,
                aspectRatio: aspectRatio,
                applyFilter: applyFilter,
                isRaw: false
            )

            let totalJpegDuration = Date().timeIntervalSince(jpegProcessStart)
            print("🖼️ [JPEGProcess] JPEG处理总耗时: \(String(format: "%.3f", totalJpegDuration))s")

            return result
        }
    }

    /// Handle image results that finished background processing (regular photos)
    private func handleProcessedResult(_ result: InternalProcessedResult, completion: @escaping (Data?) -> Void) {
        print("📸 [HandleResult] Processing regular photo result")

        let captureResult = CaptureResult(
            originalImage: result.processedImages.originalImage,
            filteredImage: result.processedImages.filteredImage,
            metadata: result.metadata,
            livePhotoURL: nil,
            originalImageData: result.originalImageData,
            isRaw: result.isRaw
        )

        delegate?.photoProcessor(self, didFinishProcessing: captureResult)
        completion(nil)
        print("✅ [HandleResult] Regular photo processing complete")
    }

    /// Process `CIImage` with shared components
    private func processCIImageWithSharedComponents(
        _ image: CIImage,
        metadata: [String: Any],
        originalImageData: Data?,
        aspectRatio: Double,
        applyFilter: Bool,
        isRaw: Bool,
        fixedOrientation: UIImage.Orientation? = nil
    ) -> InternalProcessedResult {
        let processStart = Date()
        print("🎯 [SharedProcess] 开始使用共享组件处理图像 (isRaw: \(isRaw))")

        // Use the shared image processor
        guard let processedImages = imageProcessor.processImage(
            image,
            aspectRatio: aspectRatio,
            applyFilter: applyFilter,
            fixedOrientation: fixedOrientation
        ) else {
            print("❌ [SharedProcess] 图像处理失败")
            let emptyResult = ProcessedImageResult(originalImage: UIImage(), filteredImage: UIImage())
            return InternalProcessedResult(
                processedImages: emptyResult,
                metadata: metadata,
                originalImageData: originalImageData,
                isRaw: isRaw
            )
        }

        // Use the shared metadata builder
        let finalMetadata = metadataBuilder.buildPhotoMetadata(originalMetadata: metadata)

        let processDuration = Date().timeIntervalSince(processStart)
        print("🎯 [SharedProcess] 共享组件处理完成，耗时: \(String(format: "%.3f", processDuration))s")

        return InternalProcessedResult(
            processedImages: processedImages,
            metadata: finalMetadata,
            originalImageData: originalImageData,
            isRaw: isRaw
        )
    }
}
