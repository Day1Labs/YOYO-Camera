import Foundation

// MARK: - Filter Category

/// Filter Category (stable, does not change frequently)
enum FilterCategory: String, CaseIterable, Codable {
    case none // no filter
    case builtin // Built-in filters
    case custom // User-defined filters
}

// MARK: - Filter Identifier

/// Filter Identifier (used to store, transfer, and uniquely identify a filter)
struct FilterIdentifier: Codable, Hashable, Identifiable {
    let category: FilterCategory
    let name: String // builtin: "dusk", custom: filter name, none: ""

    var id: String { "\(category.rawValue):\(name)" }

    // MARK: - Convenient construct

    static let none = FilterIdentifier(category: .none, name: "")

    static func builtin(_ name: String) -> FilterIdentifier {
        FilterIdentifier(category: .builtin, name: name)
    }

    static func custom(_ id: String) -> FilterIdentifier {
        FilterIdentifier(category: .custom, name: id)
    }

    // MARK: - Quick access to Film simulation filters

    /// static let vivid = FilterIdentifier.builtin("Vivid")
    static let lClassic = FilterIdentifier.builtin("LC")
    // static let hMaster = FilterIdentifier.builtin("H-Master")
    static let gr = FilterIdentifier.builtin("GR")
    static let fChrome = FilterIdentifier.builtin("FC")

    /// Collection of all film physics simulation filters
    static let filmSimulationFilters: [FilterIdentifier] = [.fChrome, .lClassic, .gr]

    /// Whether it is a film physics simulation filter
    var isFilmSimulation: Bool {
        Self.filmSimulationFilters.contains(self)
    }

    /// Whether film physics simulation or no filter
    var isFilmSimulationOrNone: Bool {
        isFilmSimulation || self == .none
    }
}

// MARK: - filter metadata

/// Color temperature type
enum FilterColorTemperature: String, CaseIterable {
    case warm = "Warm" // Warm colors
    case cool = "Cool" // cool colors
    case neutral = "Neutral" // neutral
    case blackWhite = "BW" // black and white
}

/// Filter intensity level - used for AI intelligent recommendation and filter feature classification
enum FilterIntensity: String, CaseIterable, Comparable {
    case subtle = "Subtle" // slight
    case moderate = "Moderate" // medium
    case strong = "Strong" // strong

    static func < (lhs: FilterIntensity, rhs: FilterIntensity) -> Bool {
        switch (lhs, rhs) {
        case (.subtle, .moderate), (.subtle, .strong), (.moderate, .strong):
            return true
        default:
            return false
        }
    }
}

/// Filter processing type
enum FilterProcessingType {
    case lut(String) // LUT file name
    case builtin // Built-in Core Image filter chain
    case custom // Custom filters
}

/// Filter chain steps
struct FilterChainStep {
    let filterName: String
    let parameters: [String: Any]
}

/// Filter default effect configuration (excluding physical parameters during shooting)
struct FilterDefaultFilmEffects: Codable {
    var cineToneIntensity: Float = 0
    var filmPresetID: String = FilmPreset.all.first?.id ?? ""
    var halationIntensity: Float = 0
    var bloomIntensity: Float = 0
    var fogIntensity: Float = 0
    var vignetteIntensity: Float = 0
    var grainIntensity: Float = 0
    var lightLeakIntensity: Float = 0

    static let none = FilterDefaultFilmEffects()
}

/// Filter information structure
struct FilterInfo {
    let colorTemperature: FilterColorTemperature
    let intensity: FilterIntensity
    let descriptionKey: String
    let inspired: String?
    let processingType: FilterProcessingType
    let chain: [FilterChainStep]?
    let filmEffects: FilterDefaultFilmEffects

    init(
        colorTemperature: FilterColorTemperature,
        intensity: FilterIntensity = .moderate,
        descriptionKey: String,
        inspired: String? = nil,
        processingType: FilterProcessingType? = nil,
        filterName: String? = nil,
        chain: [FilterChainStep]? = nil,
        filmEffects: FilterDefaultFilmEffects = .none
    ) {
        self.colorTemperature = colorTemperature
        self.intensity = intensity
        self.descriptionKey = descriptionKey
        self.inspired = inspired
        self.chain = chain
        self.filmEffects = filmEffects

        if let processingType {
            self.processingType = processingType
        } else {
            self.processingType = .lut(filterName ?? "")
        }
    }

    var localizedDescription: String {
        NSLocalizedString(descriptionKey, comment: "Filter description")
    }
}
