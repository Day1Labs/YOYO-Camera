import Combine
import Foundation
import SwiftUI

final class FilmPresetDebugManager: ObservableObject {
    static let shared = FilmPresetDebugManager()

    @Published var modifiedPresets: [Int: FilmPreset] = [:]

    private init() {}

    func getPreset(original: FilmPreset, index: Int) -> FilmPreset {
        if let modified = modifiedPresets[index] {
            return modified
        }
        return original
    }

    func updatePreset(index: Int, preset: FilmPreset) {
        modifiedPresets[index] = preset
    }

    func resetPreset(index: Int) {
        modifiedPresets.removeValue(forKey: index)
    }

    func copyConfigToClipboard(preset: FilmPreset) {
        let authorLine = preset.author.map { "author: \"\($0)\",\n                " } ?? ""
        let config = """
            FilmPreset(
                name: "\(preset.name)",
                \(authorLine)negativeExposure: \(String(format: "%.2f", preset.negativeExposure)),
                developmentGamma: \(String(format: "%.2f", preset.developmentGamma)),
                printContrast: \(String(format: "%.2f", preset.printContrast)),
                dyeDensity: \(String(format: "%.2f", preset.dyeDensity)),
                colorCrosstalk: \(String(format: "%.2f", preset.colorCrosstalk)),
                highlightRolloff: \(String(format: "%.2f", preset.highlightRolloff)),
                shadowLift: \(String(format: "%.2f", preset.shadowLift)),
                printWarmth: \(String(format: "%.2f", preset.printWarmth)),
                layerSpeeds: SIMD3<Float>(\(String(format: "%.2f", preset.layerSpeeds.x)), \(String(format: "%.2f", preset.layerSpeeds.y)), \(String(format: "%.2f", preset.layerSpeeds.z))),
                layerCrossovers: SIMD3<Float>(\(String(format: "%.2f", preset.layerCrossovers.x)), \(String(format: "%.2f", preset.layerCrossovers.y)), \(String(format: "%.2f", preset.layerCrossovers.z))),
                adjacencyStrength: \(String(format: "%.2f", preset.adjacencyStrength)),
                grainRoughness: \(String(format: "%.2f", preset.grainRoughness)),
                halationSpreadScale: \(String(format: "%.2f", preset.halationSpreadScale)),
                halationThresholdOffset: \(String(format: "%.2f", preset.halationThresholdOffset)),
                cineToneIntensity: \(String(format: "%.2f", preset.cineToneIntensity)),
                grainIntensity: \(String(format: "%.2f", preset.grainIntensity)),
                halationIntensity: \(String(format: "%.2f", preset.halationIntensity)),
                halationTintCore: SIMD3<Float>(\(String(format: "%.2f", preset.halationTintCore.x)), \(String(format: "%.2f", preset.halationTintCore.y)), \(String(format: "%.2f", preset.halationTintCore.z))),
                halationTintMid: SIMD3<Float>(\(String(format: "%.2f", preset.halationTintMid.x)), \(String(format: "%.2f", preset.halationTintMid.y)), \(String(format: "%.2f", preset.halationTintMid.z))),
                halationTintEdge: SIMD3<Float>(\(String(format: "%.2f", preset.halationTintEdge.x)), \(String(format: "%.2f", preset.halationTintEdge.y)), \(String(format: "%.2f", preset.halationTintEdge.z))),
                halationStrength: \(String(format: "%.2f", preset.halationStrength)),
                channelMixerRed: SIMD3<Float>(\(String(format: "%.2f", preset.channelMixerRed.x)), \(String(format: "%.2f", preset.channelMixerRed.y)), \(String(format: "%.2f", preset.channelMixerRed.z))),
                channelMixerGreen: SIMD3<Float>(\(String(format: "%.2f", preset.channelMixerGreen.x)), \(String(format: "%.2f", preset.channelMixerGreen.y)), \(String(format: "%.2f", preset.channelMixerGreen.z))),
                channelMixerBlue: SIMD3<Float>(\(String(format: "%.2f", preset.channelMixerBlue.x)), \(String(format: "%.2f", preset.channelMixerBlue.y)), \(String(format: "%.2f", preset.channelMixerBlue.z)))
            )
        """
        UIPasteboard.general.string = config
    }
}
