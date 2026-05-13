import AVFoundation
import CoreML
import SwiftUI
import Vision

// MARK: - Detected object struct

struct DetectedObject {
    let label: String
    let confidence: Float
    let boundingBox: CGRect
}

// MARK: - Object detection manager

enum ObjectDetector {
    /// Cache the VNCoreMLModel instance to avoid reloading it every time
    private static let objectDetectionModel: VNCoreMLModel? = try? VNCoreMLModel(for: ObjectDetectionModel().model)

    /// Detect objects from a sample buffer
    static func detectObjects(from sampleBuffer: CMSampleBuffer) async -> [DetectedObject] {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let model = objectDetectionModel
        else {
            return []
        }

        return await withCheckedContinuation { continuation in
            let request = VNCoreMLRequest(model: model) { request, _ in
                guard let results = request.results as? [VNRecognizedObjectObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                let objects = results.compactMap { observation -> DetectedObject? in
                    guard let label = observation.labels.first else { return nil }
                    return DetectedObject(
                        label: label.identifier,
                        confidence: label.confidence,
                        boundingBox: observation.boundingBox
                    )
                }
                continuation.resume(returning: objects)
            }
            request.imageCropAndScaleOption = .centerCrop
            let handler = VNImageRequestHandler(cvPixelBuffer: imageBuffer, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    /// Detect objects from a CIImage
    static func detectObjects(from ciImage: CIImage) async -> [DetectedObject] {
        guard let model = objectDetectionModel else {
            return []
        }

        return await withCheckedContinuation { continuation in
            let request = VNCoreMLRequest(model: model) { request, _ in
                guard let results = request.results as? [VNRecognizedObjectObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                let objects = results.compactMap { observation -> DetectedObject? in
                    guard let label = observation.labels.first else { return nil }
                    return DetectedObject(
                        label: label.identifier,
                        confidence: label.confidence,
                        boundingBox: observation.boundingBox
                    )
                }
                continuation.resume(returning: objects)
            }
            request.imageCropAndScaleOption = .centerCrop
            let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    /// Get a formatted description of object detection results
    static func getObjectDetectionDescription(for objects: [DetectedObject]) -> String {
        let objectNames = objects.map(\.label)
        if objectNames.isEmpty {
            return .objectsNone.localized
        } else {
            return .objectsCount.localized(objectNames.count, objectNames.joined(separator: ", "))
        }
    }

    /// Filter out low-confidence objects
    static func filterObjects(_ objects: [DetectedObject], minConfidence: Float = 0.3) -> [DetectedObject] {
        objects.filter { $0.confidence >= minConfidence }
    }

    /// Sort objects by confidence
    static func sortObjectsByConfidence(_ objects: [DetectedObject]) -> [DetectedObject] {
        objects.sorted { $0.confidence > $1.confidence }
    }
}
