import CoreImage
import SwiftUI

// MARK: - Unified filter configuration manager

final class FilterConfigManager {
    static let shared = FilterConfigManager()

    private var configurations: [String: FilterConfig] = [:] // key: FilterIdentifier.id

    private init() {
        setupConfigurations()
    }

    /// Get filter display name
    static func getFilterDisplayName(for identifier: FilterIdentifier?) -> String {
        guard let identifier else {
            return String.photoDetailUnknownFilter.localized
        }
        if let displayConfig = FilterConfigManager.shared.getDisplayConfig(for: identifier) {
            return displayConfig.name
        } else {
            return identifier.displayName
        }
    }

    // MARK: - Configuration acquisition method

    /// Get filter configuration
    func getConfig(for identifier: FilterIdentifier) -> FilterConfig? {
        configurations[identifier.id]
    }

    /// Get all filter configurations
    func getAllConfigs() -> [FilterConfig] {
        Array(configurations.values)
    }

    /// Get all built-in filter identifiers
    func getAllBuiltinIdentifiers() -> [FilterIdentifier] {
        BuiltinFilterRegistry.shared.allNames.map { FilterIdentifier.builtin($0) }
    }

    /// Search filters based on keywords (search name and description)
    func searchConfigs(by keywords: [String]) -> [FilterConfig] {
        configurations.values.filter { config in
            let searchText = (config.display.name + " " + config.display.description).lowercased()
            return keywords.allSatisfy { keyword in
                searchText.contains(keyword.lowercased())
            }
        }
    }

    /// Get the display configuration of the filter
    func getDisplayConfig(for identifier: FilterIdentifier) -> FilterDisplayConfig? {
        configurations[identifier.id]?.display
    }

    /// Get the application configuration of the filter
    func getProcessingConfig(for identifier: FilterIdentifier) -> FilterProcessingConfig? {
        configurations[identifier.id]?.processing
    }

    /// Check if it is a LUT filter
    func isLutFilter(_ identifier: FilterIdentifier) -> Bool {
        if case .lut = configurations[identifier.id]?.processing.processingType {
            return true
        }
        return false
    }

    /// Get LUT file name
    func getLutFileName(for identifier: FilterIdentifier) -> String? {
        if case let .lut(fileName) = configurations[identifier.id]?.processing.processingType {
            return fileName
        }
        return nil
    }

    /// Get filter chain
    func getFilterChain(for identifier: FilterIdentifier) -> [FilterChainStep]? {
        configurations[identifier.id]?.processing.chain
    }

    // MARK: - Configuration settings

    private func setupConfigurations() {
        // Register none filter
        let noneIdentifier = FilterIdentifier.none
        configurations[noneIdentifier.id] = noneIdentifier.config

        // Register all built-in filters
        for name in BuiltinFilterRegistry.shared.allNames {
            let identifier = FilterIdentifier.builtin(name)
            configurations[identifier.id] = identifier.config
        }
    }
}
