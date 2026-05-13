import AVFoundation
import CoreImage
import UIKit

enum SceneClassifier {
    /// Classify scenes based on object detection results
    static func classifyScene(from ciImage: CIImage) async -> (type: SceneType, confidence: Float, identifier: String?) {
        let objects = await ObjectDetector.detectObjects(from: ciImage)
        return classifySceneFromObjects(objects)
    }

    /// Classify scenes based on object detection results (from CMSampleBuffer)
    static func classifyScene(from sampleBuffer: CMSampleBuffer) async -> (type: SceneType, confidence: Float, identifier: String?) {
        let objects = await ObjectDetector.detectObjects(from: sampleBuffer)
        return classifySceneFromObjects(objects)
    }

    /// Infer the scene type from detected objects
    static func classifySceneFromObjects(_ objects: [DetectedObject]) -> (type: SceneType, confidence: Float, identifier: String?) {
        guard !objects.isEmpty else {
            return (.general, 0.0, "no_objects")
        }

        // 1. preprocess: filter low confidence
        let validObjects = objects.filter { $0.confidence > 0.3 }
        guard !validObjects.isEmpty else {
            return (.general, 0.1, "low_confidence")
        }

        // 2. accumulate weighted scores
        // scoring formula: Score = ObjectConfidence * AreaWeight * Relevance
        var sceneScores: [SceneType: Float] = [:]

        for obj in validObjects {
            // Calculate area weight (assuming boundingBox is normalized to 0-1)
            let area = Float(obj.boundingBox.width * obj.boundingBox.height)

            // area weight strategy:
            // - tiny objects (<1%): very low weight, ignore background clutter
            // - medium objects (10%-30%): normal weight
            // - primary objects (>30%): significantly increased weight
            let areaWeight: Float
            if area < 0.01 {
                areaWeight = 0.1
            } else if area < 0.1 {
                areaWeight = 0.5
            } else {
                areaWeight = 0.5 + (area * 2.0) // up to about 2.5x weight
            }

            let (candidates, _) = mapObjectToSceneTypes(obj.label)

            for (sceneType, relevance) in candidates {
                // core formula
                let score = obj.confidence * areaWeight * relevance
                sceneScores[sceneType, default: 0] += score
            }
        }

        // 3. decision: find the highest-scoring scene
        let sortedScenes = sceneScores.sorted { $0.value > $1.value }

        guard let (bestScene, bestScore) = sortedScenes.first else {
            return (.general, 0.2, "ambiguous")
        }

        // 4. special rule adjustments

        // Rule A: crowd detection
        // if the result is Portrait but the frame contains more than 3 clearly visible people, upgrade it to Group
        if bestScene == .portrait {
            let significantPeople = validObjects.filter { $0.label == "person" && ($0.boundingBox.width * $0.boundingBox.height) > 0.02 }
            if significantPeople.count >= 3 {
                return (.group, min(bestScore, 1.0), "person_count_\(significantPeople.count)")
            }
        }

        // Rule B: threshold control
        // if the top score is still very low(meaning the frame only contains tiny, irrelevant objects), fall back to General
        // for example: a tiny car in the distant background should not cause the scene to be classified as Vehicle
        if bestScore < 0.4 {
            return (.general, 0.3, "low_score_fallback")
        }

        let finalConfidence = min(bestScore, 1.0)

        print("🎯 [DEBUG] Scene: \(bestScene.rawValue) (Conf: \(String(format: "%.2f", finalConfidence))) - Top Obj: \(validObjects.first?.label ?? "none")")

        return (bestScene, finalConfidence, "weighted_score")
    }

    /// Map object labels to possible scene types and weights
    /// Returns: (scene list, primary scene type)
    private static func mapObjectToSceneTypes(_ label: String) -> ([(SceneType, Float)], SceneType) {
        let lowercasedLabel = label.lowercased()

        switch lowercasedLabel {
        // --- people ---
        case "person":
            return ([(.portrait, 1.0), (.group, 0.6)], .portrait)

        // --- animals ---
        case "cat", "dog":
            return ([(.pet, 1.0), (.wildlife, 0.3)], .pet)

        case "bird", "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe":
            return ([(.wildlife, 1.0), (.pet, 0.2)], .wildlife)

        // --- vehicles ---
        case "bicycle", "motorcycle":
            return ([(.vehicle, 0.9), (.sports, 0.4)], .vehicle)

        case "car", "bus", "train", "truck", "boat", "airplane":
            return ([(.vehicle, 1.0), (.cityscape, 0.3)], .vehicle)

        // --- city/street ---
        case "traffic light", "fire hydrant", "stop sign", "parking meter", "bench":
            return ([(.cityscape, 1.0), (.vehicle, 0.2)], .cityscape)

        // --- sports ---
        case "frisbee", "skis", "snowboard", "sports ball", "kite", "baseball bat", "baseball glove", "skateboard", "surfboard", "tennis racket":
            return ([(.sports, 1.0)], .sports)

        // --- food ---
        case "banana", "apple", "sandwich", "orange", "broccoli", "carrot", "hot dog", "pizza", "donut", "cake":
            return ([(.food, 1.0)], .food)

        case "bottle", "wine glass", "cup", "fork", "knife", "spoon", "bowl":
            // tableware usually indicates a food scene, or a still-life scene
            return ([(.food, 0.7), (.stillLife, 0.6), (.interior, 0.3)], .food)

        // --- indoor/home ---
        case "chair", "couch", "bed", "dining table", "toilet", "sink", "refrigerator":
            return ([(.interior, 1.0)], .interior)

        case "microwave", "oven", "toaster":
            return ([(.interior, 1.0), (.food, 0.3)], .interior)

        case "clock", "vase":
            return ([(.interior, 0.8), (.stillLife, 0.6)], .interior)

        // --- plants ---
        case "potted plant":
            return ([(.plant, 1.0), (.interior, 0.5)], .plant)

        // --- technology ---
        case "tv", "laptop", "mouse", "remote", "keyboard", "cell phone":
            return ([(.technology, 1.0), (.interior, 0.5)], .technology)

        // --- still life/objects ---
        case "backpack", "umbrella", "handbag", "tie", "suitcase":
            return ([(.stillLife, 0.9), (.portrait, 0.2)], .stillLife)

        case "book", "scissors", "teddy bear", "hair drier", "toothbrush":
            return ([(.stillLife, 1.0), (.interior, 0.4)], .stillLife)

        default:
            return ([(.general, 0.5)], .general)
        }
    }
}
