import AVFoundation
import Combine
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit // For NSDataAsset

final class FilterManager: ObservableObject {
    /// Shared instance
    static let shared = FilterManager()

    private var cancellables = Set<AnyCancellable>()

    // Use @AppStorage directly as persistent storage
    @AppStorage("selectedFilter") var selectedFilterRawValue: String = FilterIdentifier.fChrome.id
    @Published var selectedFilter: FilterIdentifier = .fChrome {
        didSet {
            selectedFilterRawValue = selectedFilter.id
            updateBaseFilterSnapshot()

            // When switching filters, the default effect configuration of the filter is applied (customized configurations are used first)
            if let customEffects = filterCustomEffects[selectedFilter.id] {
                applyFilmEffects(customEffects)
            } else if let info = selectedFilter.info {
                applyFilmEffects(info.filmEffects)
            }
        }
    }

    @AppStorage("favoriteFilters") var favoriteFiltersRaw: String = "[]"
    @Published var favoriteFilters: [FilterIdentifier] = [] {
        didSet {
            let arr = favoriteFilters.map(\.id)
            if let data = try? JSONEncoder().encode(arr),
               let str = String(data: data, encoding: .utf8)
            {
                favoriteFiltersRaw = str
            }
        }
    }

    @AppStorage("hiddenFilters") var hiddenFiltersRaw: String = "[]"
    @Published var hiddenFilters: [FilterIdentifier] = [] {
        didSet {
            let arr = hiddenFilters.map(\.id)
            if let data = try? JSONEncoder().encode(arr),
               let str = String(data: data, encoding: .utf8)
            {
                hiddenFiltersRaw = str
            }
        }
    }

    /// Filter custom effect storage: stores the user-adjusted effect of each filter
    @AppStorage("filterCustomEffects") var filterCustomEffectsRaw: String = "{}"
    private var saveEffectsWorkItem: DispatchWorkItem?

    @Published var filterCustomEffects: [String: FilterDefaultFilmEffects] = [:] {
        didSet {
            saveEffectsWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if let data = try? JSONEncoder().encode(self.filterCustomEffects),
                   let str = String(data: data, encoding: .utf8)
                {
                    self.filterCustomEffectsRaw = str
                }
            }
            saveEffectsWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
        }
    }

    /// MARK whether the filter configuration is being applied (to prevent the save logic from being triggered when the configuration is applied)
    private var isApplyingFilterConfig = false

    /// Filter strength storage: stores custom strength values ​​for each filter
    @AppStorage("filterIntensities") var filterIntensitiesRaw: String = "{}"

    private var saveIntensitiesWorkItem: DispatchWorkItem?

    @Published var filterIntensities: [String: Float] = [:] {
        didSet {
            // Debounce persistence to avoid writing to UserDefaults on every slider change
            saveIntensitiesWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if let data = try? JSONEncoder().encode(self.filterIntensities),
                   let str = String(data: data, encoding: .utf8)
                {
                    self.filterIntensitiesRaw = str
                }
            }
            saveIntensitiesWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)

            updateBaseFilterSnapshot()
        }
    }

    @Published var selectedCustomFilter: CustomFilter? {
        didSet {
            if let filter = selectedCustomFilter {
                UserDefaults.standard.set(filter.id.uuidString, forKey: "selectedCustomFilterId")
            }

            updateBaseFilterSnapshot()
        }
    }

    // MARK: - Photo Effects

    /// Apply default effects configuration
    private func applyFilmEffects(_ defaults: FilterDefaultFilmEffects) {
        // MARK the configuration being applied to avoid triggering a save
        isApplyingFilterConfig = true

        // Use DispatchQueue.main.async to ensure correct handling during the view update cycle
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.cineToneIntensity = Double(defaults.cineToneIntensity)
            self.filmPresetID = defaults.filmPresetID
            self.halationIntensity = Double(defaults.halationIntensity)
            self.bloomIntensity = Double(defaults.bloomIntensity)
            self.fogIntensity = Double(defaults.fogIntensity)
            self.vignetteIntensity = Double(defaults.vignetteIntensity)
            self.grainIntensity = Double(defaults.grainIntensity)
            self.lightLeakIntensity = Double(defaults.lightLeakIntensity)

            // Restore markers (with a slight delay to ensure all didSets have been executed)
            DispatchQueue.main.async {
                self.isApplyingFilterConfig = false
            }
        }
    }

    /// Save current effects configuration to custom storage
    private func saveCurrentEffects() {
        guard !isApplyingFilterConfig else { return }

        // Allows saving custom effects for built-in filters and custom filters
        guard selectedFilter.category == .builtin || selectedFilter.category == .custom else { return }

        let currentEffects = FilterDefaultFilmEffects(
            cineToneIntensity: Float(cineToneIntensity),
            filmPresetID: filmPresetID,
            halationIntensity: Float(halationIntensity),
            bloomIntensity: Float(bloomIntensity),
            fogIntensity: Float(fogIntensity),
            vignetteIntensity: Float(vignetteIntensity),
            grainIntensity: Float(grainIntensity),
            lightLeakIntensity: Float(lightLeakIntensity)
        )

        // Update in-memory cache
        filterCustomEffects[selectedFilter.id] = currentEffects
    }

    /// Reset the current filter's Film effect configuration to default values
    func resetCurrentFilmEffects() {
        // 1. Remove custom configuration
        filterCustomEffects.removeValue(forKey: selectedFilter.id)

        // 2. Apply original default configuration
        if let info = selectedFilter.info {
            applyFilmEffects(info.filmEffects)
        } else {
            applyFilmEffects(.none)
        }
    }

    /// Check if the current filter has a custom Film effect
    var hasCustomFilmEffects: Bool {
        filterCustomEffects[selectedFilter.id] != nil
    }

    @AppStorage("bloomIntensity") var bloomIntensity: Double = 0.0 {
        didSet {
            updatePhotoEffectsSnapshot()
            saveCurrentEffects()
        }
    }

    @AppStorage("grainIntensity") var grainIntensity: Double = 0.0 {
        didSet {
            updatePhotoEffectsSnapshot()
            saveCurrentEffects()
        }
    }

    @AppStorage("fogIntensity") var fogIntensity: Double = 0.0 {
        didSet {
            updatePhotoEffectsSnapshot()
            saveCurrentEffects()
        }
    }

    @AppStorage("vignetteIntensity") var vignetteIntensity: Double = 0.0 {
        didSet {
            updatePhotoEffectsSnapshot()
            saveCurrentEffects()
        }
    }

    @AppStorage("lightLeakIntensity") var lightLeakIntensity: Double = 0.0 {
        didSet {
            updatePhotoEffectsSnapshot()
            saveCurrentEffects()
        }
    }

    @AppStorage("cineToneIntensity") var cineToneIntensity: Double = 0.0 {
        didSet {
            updatePhotoEffectsSnapshot()
            saveCurrentEffects()
        }
    }

    @AppStorage("filmPresetID") var filmPresetID: String = FilmPreset.all.first?.id ?? "" {
        didSet {
            updatePhotoEffectsSnapshot()
            saveCurrentEffects()
        }
    }

    @AppStorage("halationIntensity") var halationIntensity: Double = 0.0 {
        didSet {
            updatePhotoEffectsSnapshot()
            saveCurrentEffects()
        }
    }

    private struct CustomLutSnapshot: Equatable {
        let cacheKey: String
        let lutData: Data
        let lutSize: Int
    }

    private struct BaseFilterSnapshot {
        let processingConfig: FilterProcessingConfig?
        let intensity: Float
        let customLut: CustomLutSnapshot?
    }

    private let snapshotLock = NSLock()
    private var baseFilterSnapshot = BaseFilterSnapshot(processingConfig: nil, intensity: 1.0, customLut: nil)
    private var photoEffectsSnapshot = FilterManager.makeInitialPhotoEffectsSnapshot()

    private let ciContext: CIContext
    private let configManager = FilterConfigManager.shared

    // MARK: - FilmSimulation Adaptive (Scene-Aware)

    private struct FilmSimulationSceneStats {
        let avgLuma: Float // 0..1
        let avgSaturation: Float // 0..1 (HSV-ish)
        let minLuma: Float // 0..1
        let maxLuma: Float // 0..1

        var dynamicRange: Float {
            max(0, min(1, maxLuma - minLuma))
        }
    }

    func clamp(_ value: Float, _ minValue: Float, _ maxValue: Float) -> Float {
        min(max(value, minValue), maxValue)
    }

    private func sampleRGBA8(_ image: CIImage) -> (r: Float, g: Float, b: Float, a: Float)? {
        var pixel: [UInt8] = [0, 0, 0, 0]
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        ciContext.render(
            image,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: colorSpace
        )
        return (
            r: Float(pixel[0]) / 255.0,
            g: Float(pixel[1]) / 255.0,
            b: Float(pixel[2]) / 255.0,
            a: Float(pixel[3]) / 255.0
        )
    }

    private func luma709(r: Float, g: Float, b: Float) -> Float {
        0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    private func saturationApprox(r: Float, g: Float, b: Float) -> Float {
        let maxV = max(r, max(g, b))
        let minV = min(r, min(g, b))
        if maxV <= 0.0001 { return 0 }
        return (maxV - minV) / maxV
    }

    private func filmSimulationSceneStats(for ciImage: CIImage) -> FilmSimulationSceneStats? {
        let extent = ciImage.extent
        guard extent.width.isFinite, extent.height.isFinite, extent.width > 1, extent.height > 1 else {
            return nil
        }

        // Downscale for analysis to keep this lightweight in live preview.
        // (Area filters run over the full extent; analyzing a smaller image is much cheaper.)
        let target: CGFloat = 96
        let scale = min(target / extent.width, target / extent.height)
        let analysisImage: CIImage
        if scale < 1.0 {
            analysisImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        } else {
            analysisImage = ciImage
        }
        let analysisExtent = analysisImage.extent

        // Average
        if let avgFilter = CIFilter(name: "CIAreaAverage") {
            avgFilter.setValue(analysisImage, forKey: kCIInputImageKey)
            avgFilter.setValue(CIVector(cgRect: analysisExtent), forKey: kCIInputExtentKey)
            guard let avgOut = avgFilter.outputImage,
                  let avg = sampleRGBA8(avgOut)
            else {
                return nil
            }

            // Min/Max for a quick dynamic-range proxy
            var minL: Float = luma709(r: avg.r, g: avg.g, b: avg.b)
            var maxL: Float = minL

            if let minFilter = CIFilter(name: "CIAreaMinimum") {
                minFilter.setValue(analysisImage, forKey: kCIInputImageKey)
                minFilter.setValue(CIVector(cgRect: analysisExtent), forKey: kCIInputExtentKey)
                if let minOut = minFilter.outputImage,
                   let mn = sampleRGBA8(minOut)
                {
                    minL = luma709(r: mn.r, g: mn.g, b: mn.b)
                }
            }

            if let maxFilter = CIFilter(name: "CIAreaMaximum") {
                maxFilter.setValue(analysisImage, forKey: kCIInputImageKey)
                maxFilter.setValue(CIVector(cgRect: analysisExtent), forKey: kCIInputExtentKey)
                if let maxOut = maxFilter.outputImage,
                   let mx = sampleRGBA8(maxOut)
                {
                    maxL = luma709(r: mx.r, g: mx.g, b: mx.b)
                }
            }

            let avgL = luma709(r: avg.r, g: avg.g, b: avg.b)
            let avgSat = saturationApprox(r: avg.r, g: avg.g, b: avg.b)

            return FilmSimulationSceneStats(
                avgLuma: clamp(avgL, 0, 1),
                avgSaturation: clamp(avgSat, 0, 1),
                minLuma: clamp(minL, 0, 1),
                maxLuma: clamp(maxL, 0, 1)
            )
        }

        return nil
    }

    // MARK: - initialization

    private static func makeInitialPhotoEffectsSnapshot() -> FilmEmulationSnapshot {
        let userDefaults = UserDefaults.standard

        let presetID = userDefaults.string(forKey: "filmPresetID")
        let preset = presetID.flatMap { id in FilmPreset.all.first(where: { $0.id == id }) } ?? FilmPreset.all.first

        let cineToneIntensity = Float(userDefaults.object(forKey: "cineToneIntensity") as? Double ?? 0)
        let halationIntensity = Float(userDefaults.object(forKey: "halationIntensity") as? Double ?? 0)
        let bloomIntensity = Float(userDefaults.object(forKey: "bloomIntensity") as? Double ?? 0)
        let fogIntensity = Float(userDefaults.object(forKey: "fogIntensity") as? Double ?? 0)
        let vignetteIntensity = Float(userDefaults.object(forKey: "vignetteIntensity") as? Double ?? 0)
        let lightLeakIntensity = Float(userDefaults.object(forKey: "lightLeakIntensity") as? Double ?? 0)
        let grainIntensity = Float(userDefaults.object(forKey: "grainIntensity") as? Double ?? 0)

        return FilmEmulationSnapshot(
            preset: preset,
            cineToneIntensity: cineToneIntensity,
            halationIntensity: halationIntensity,
            bloomIntensity: bloomIntensity,
            fogIntensity: fogIntensity,
            vignetteIntensity: vignetteIntensity,
            lightLeakIntensity: lightLeakIntensity,
            grainIntensity: grainIntensity,
            presetID: preset?.id
        )
    }

    private init() {
        ciContext = CIContext(options: [
            .cacheIntermediates: true, // Preserve intermediate textures to reduce volatile backing warnings
            .useSoftwareRenderer: false,
        ])
        // Initialize selectedFilter
        if let parsed = Self.parseFilterIdentifier(from: selectedFilterRawValue) {
            selectedFilter = parsed
            // Migrate old persisted values (e.g. builtin:Origin) to the new canonical id.
            if selectedFilterRawValue != selectedFilter.id {
                selectedFilterRawValue = selectedFilter.id
            }
        } else {
            selectedFilter = .fChrome
            selectedFilterRawValue = selectedFilter.id
        }

        // Initialize selectedCustomFilter
        if let customIdStr = UserDefaults.standard.string(forKey: "selectedCustomFilterId"),
           let customId = UUID(uuidString: customIdStr)
        {
            selectedCustomFilter = CustomFilterManager.shared.customFilters.first(where: { $0.id == customId })
        }

        // Initialize favoriteFilters
        if let data = favoriteFiltersRaw.data(using: .utf8),
           let arr = try? JSONDecoder().decode([String].self, from: data)
        {
            favoriteFilters = arr.compactMap { Self.parseFilterIdentifier(from: $0) }
        }

        // Initialize hiddenFilters
        if let data = hiddenFiltersRaw.data(using: .utf8),
           let arr = try? JSONDecoder().decode([String].self, from: data)
        {
            hiddenFilters = arr.compactMap { Self.parseFilterIdentifier(from: $0) }
        }

        // initialize filterIntensities
        if let data = filterIntensitiesRaw.data(using: .utf8),
           let dict = try? JSONDecoder().decode([String: Float].self, from: data)
        {
            filterIntensities = dict
        }

        // initialize filterCustomEffects
        if let data = filterCustomEffectsRaw.data(using: .utf8),
           let dict = try? JSONDecoder().decode([String: FilterDefaultFilmEffects].self, from: data)
        {
            filterCustomEffects = dict
        }

        updateBaseFilterSnapshot()
        updatePhotoEffectsSnapshot()

        setupCameraParameterObservers()
    }

    private func setupCameraParameterObservers() {
        // Monitor changes in camera parameters and update Film simulation effects in real time
        // Mainly so that in Preview mode, effects such as grain can change in real time with ISO.

        // 1. ISO changes (affects grain)
        ExposureManager.shared.$currentISO
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePhotoEffectsSnapshot()
            }
            .store(in: &cancellables)

        // 2. Aperture changes (affects depth of field, vignetting)
        ExposureManager.shared.$currentAperture
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePhotoEffectsSnapshot()
            }
            .store(in: &cancellables)

        // 3. Exposure compensation changes (affects dynamic range simulation)
        ExposureManager.shared.$exposureCompensation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePhotoEffectsSnapshot()
            }
            .store(in: &cancellables)

        // 4. Changes in color temperature (affecting film color development)
        WhiteBalanceManager.shared.$currentTemperature
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePhotoEffectsSnapshot()
            }
            .store(in: &cancellables)
    }

    private func updateBaseFilterSnapshot() {
        let selected = selectedFilter
        let processingConfig: FilterProcessingConfig?
        if selected.category == .custom {
            processingConfig = FilterProcessingConfig(processingType: .custom)
        } else {
            processingConfig = configManager.getProcessingConfig(for: selected)
        }

        let intensity: Float = {
            if selected.category == .custom, let customFilter = selectedCustomFilter {
                let key = "custom_\(customFilter.id.uuidString)"
                if let val = filterIntensities[key] { return val }
                return customFilter.intensity
            }

            if let val = filterIntensities[selected.id] { return val }
            return processingConfig?.defaultIntensity ?? 1.0
        }()

        let customLut: CustomLutSnapshot? = {
            guard case .custom = processingConfig?.processingType else { return nil }
            guard let customFilter = selectedCustomFilter else { return nil }
            let (lutData, lutSize) = CustomFilterManager.shared.getLutData(for: customFilter)
            guard let lutData, lutSize > 0 else { return nil }
            return CustomLutSnapshot(cacheKey: customFilter.id.uuidString, lutData: lutData, lutSize: lutSize)
        }()

        let snapshot = BaseFilterSnapshot(processingConfig: processingConfig, intensity: intensity, customLut: customLut)
        snapshotLock.lock()
        baseFilterSnapshot = snapshot
        snapshotLock.unlock()
    }

    private func updatePhotoEffectsSnapshot() {
        // Get the actual parameters of the current camera
        let exposureManager = ExposureManager.shared
        let deviceManager = CameraDeviceManager.shared

        // ISO: If 0 (camera not initialized), use default value 400
        let currentISO = exposureManager.currentISO
        let effectiveISO = currentISO > 0 ? currentISO : 400

        // Aperture: If 0, use default value 2.8
        let currentAperture = exposureManager.currentAperture
        let effectiveAperture = currentAperture > 0 ? currentAperture : 2.8

        // Color Temperature: Obtained from White Balance Manager
        let whiteBalanceManager = WhiteBalanceManager.shared
        let currentTemperature = whiteBalanceManager.currentTemperature
        // If the color temperature is 0 or outside the reasonable range, use the default daylight color temperature of 5500K
        let effectiveTemperature = (currentTemperature >= 2000 && currentTemperature <= 10000)
            ? currentTemperature : 5500

        // exposure compensation
        let currentExposureBias = exposureManager.exposureCompensation

        // Focal length: Get the current equivalent focal length (35mm equivalent)
        let currentFocalLength = deviceManager.currentFocalLength
        let effectiveFocalLength = currentFocalLength > 0 ? Float(currentFocalLength) : 26.0

        // Camera Type: Convert to EffectsSnapshot.CameraType
        let cameraDeviceType = deviceManager.currentCameraDeviceType
        let effectiveCameraType: FilmEmulationSnapshot.CameraType
        switch cameraDeviceType {
        case .ultraWide:
            effectiveCameraType = .ultraWide
        case .backWide:
            effectiveCameraType = .wide
        case .telephoto:
            effectiveCameraType = .telephoto
        case .frontWide:
            effectiveCameraType = .front
        }

        let basePreset = FilmPreset.all.first(where: { $0.id == filmPresetID }) ?? FilmPreset.all.first ?? .kodakPortra400
        let safePresetIndex = FilmPreset.all.firstIndex(where: { $0.id == basePreset.id }) ?? 0
        #if DEBUG
            let resolvedPreset = FilmPresetDebugManager.shared.getPreset(original: basePreset, index: safePresetIndex)
        #else
            let resolvedPreset = basePreset
        #endif

        let snapshot = FilmEmulationSnapshot(
            preset: resolvedPreset,
            cineToneIntensity: Float(cineToneIntensity),
            halationIntensity: Float(halationIntensity),
            bloomIntensity: Float(bloomIntensity),
            fogIntensity: Float(fogIntensity),
            vignetteIntensity: Float(vignetteIntensity),
            lightLeakIntensity: Float(lightLeakIntensity),
            grainIntensity: Float(grainIntensity),
            captureISO: effectiveISO,
            captureAperture: effectiveAperture,
            captureColorTemperature: effectiveTemperature,
            captureExposureBias: currentExposureBias,
            captureFocalLength: effectiveFocalLength,
            captureCameraType: effectiveCameraType,
            presetID: resolvedPreset.id
        )

        snapshotLock.lock()
        photoEffectsSnapshot = snapshot
        snapshotLock.unlock()
    }

    private func currentSnapshots() -> (base: BaseFilterSnapshot, effects: FilmEmulationSnapshot) {
        snapshotLock.lock()
        let base = baseFilterSnapshot
        let effects = photoEffectsSnapshot
        snapshotLock.unlock()
        return (base: base, effects: effects)
    }

    /// Parse FilterIdentifier from stored id string
    private static func parseFilterIdentifier(from idString: String) -> FilterIdentifier? {
        // Backwards-compat: the old built-in name was "Origin".
        // Normalize it to the new canonical identifier to keep persistence and UI consistent.
        if idString == "Origin" {
            return .fChrome
        }

        let parts = idString.split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              let category = FilterCategory(rawValue: String(parts[0]))
        else {
            // Compatible with older formats: try to resolve as built-in filter name
            if BuiltinFilterRegistry.shared.contains(idString) {
                return .builtin(idString)
            }
            return nil
        }

        let name = String(parts[1])
        if category == .builtin, name == "Origin" {
            return .fChrome
        }
        return FilterIdentifier(category: category, name: name)
    }

    // MARK: - Configuration acquisition method

    /// Get filter configuration
    func getConfig(for identifier: FilterIdentifier) -> FilterConfig? {
        configManager.getConfig(for: identifier)
    }

    /// Get all filter configurations
    func getAllConfigs() -> [FilterConfig] {
        configManager.getAllConfigs()
    }

    /// Search filters based on tags
    func searchConfigs(by tags: [String]) -> [FilterConfig] {
        configManager.searchConfigs(by: tags)
    }

    /// Get filter display configuration
    func getDisplayConfig(for identifier: FilterIdentifier) -> FilterDisplayConfig? {
        configManager.getDisplayConfig(for: identifier)
    }

    /// Get filter application configuration
    func getProcessingConfig(for identifier: FilterIdentifier) -> FilterProcessingConfig? {
        configManager.getProcessingConfig(for: identifier)
    }

    /// Check if it is a LUT filter
    func isLutFilter(_ identifier: FilterIdentifier) -> Bool {
        configManager.isLutFilter(identifier)
    }

    /// Get LUT file name
    func getLutFileName(for identifier: FilterIdentifier) -> String? {
        configManager.getLutFileName(for: identifier)
    }

    /// Get filter chain
    func getFilterChain(for identifier: FilterIdentifier) -> [FilterChainStep]? {
        configManager.getFilterChain(for: identifier)
    }

    // MARK: - Filter intensity management

    /// Get the current intensity value of the filter (user-defined value is returned first, otherwise the default value is returned)
    func getIntensity(for identifier: FilterIdentifier) -> Float {
        // Film simulation and No Filter always use the default intensity and do not allow customization.
        if identifier.isFilmSimulationOrNone {
            return getProcessingConfig(for: identifier)?.defaultIntensity ?? 1.0
        }
        if identifier.category == .custom, let customFilter = selectedCustomFilter {
            let key = "custom_\(customFilter.id.uuidString)"
            if let val = filterIntensities[key] { return val }
            return customFilter.intensity
        }

        // If the user sets a custom strength, use the custom value
        if let customIntensity = filterIntensities[identifier.id] {
            return customIntensity
        }
        // Otherwise use the configured default strength
        return getProcessingConfig(for: identifier)?.defaultIntensity ?? 1.0
    }

    /// Set the intensity value of the filter
    func setIntensity(_ intensity: Float, for identifier: FilterIdentifier) {
        // Film simulation and filterless intensity are fixed, custom settings are ignored
        if identifier.isFilmSimulationOrNone {
            return
        }
        if identifier.category == .custom, let customFilter = selectedCustomFilter {
            let key = "custom_\(customFilter.id.uuidString)"
            filterIntensities[key] = intensity
            return
        }
        filterIntensities[identifier.id] = intensity
    }

    /// Reset filter strength to default
    func resetIntensity(for identifier: FilterIdentifier) {
        filterIntensities.removeValue(forKey: identifier.id)
    }

    /// Reset all filter strengths to default values
    func resetAllIntensities() {
        filterIntensities.removeAll()
    }

    /// Check if the filter has custom strength
    func hasCustomIntensity(for identifier: FilterIdentifier) -> Bool {
        filterIntensities[identifier.id] != nil
    }

    /// Get LUT data for a filter (for analysis)
    func getLutData(for identifier: FilterIdentifier) -> (Data, Int)? {
        guard let lutName = getLutFileName(for: identifier) else { return nil }
        let (data, size) = loadLutData(lutName: lutName)
        guard let validData = data else { return nil }
        return (validData, size)
    }

    // MARK: - LUT Cache

    private let cacheQueue = DispatchQueue(label: "com.day1-labs.yoyo.filter.cache", attributes: .concurrent)
    private var lutDataCache: [String: Data] = [:]
    private var lutSizeCache: [String: Int] = [:]
    private var cubeDataCache: [String: Data] = [:] // Use lutName directly for key

    /// Universal method for loading LUT data and dimensions
    func loadLutData(lutName: String) -> (Data?, Int) {
        // 1. Fast read attempt (read lock)
        var cachedData: Data?
        var cachedSize: Int?

        cacheQueue.sync {
            cachedData = lutDataCache[lutName]
            cachedSize = lutSizeCache[lutName]
        }

        if let data = cachedData, let size = cachedSize {
            return (data, size)
        }

        // 2. Load data (may be time-consuming, no locking)
        var loadedData: Data?
        var loadedSize = 33

        // Try the .cube file in the .dataset directory
        if let asset = NSDataAsset(name: lutName, bundle: Bundle.main) {
            loadedData = asset.data
            if let cubeString = String(data: asset.data, encoding: .utf8) {
                if let sizeLine = cubeString.components(separatedBy: .newlines).first(where: { $0.contains("LUT_3D_SIZE") }) {
                    let comps = sizeLine.components(separatedBy: .whitespaces).compactMap { Int($0) }
                    loadedSize = comps.last ?? 33
                }
            }
        } else if let url = Bundle.main.url(forResource: lutName, withExtension: "cube"),
                  let data = try? Data(contentsOf: url)
        {
            loadedData = data
            if let cubeString = String(data: data, encoding: .utf8) {
                if let sizeLine = cubeString.components(separatedBy: .newlines).first(where: { $0.contains("LUT_3D_SIZE") }) {
                    let comps = sizeLine.components(separatedBy: .whitespaces).compactMap { Int($0) }
                    loadedSize = comps.last ?? 33
                }
            }
        }

        guard let data = loadedData else {
            print("LUT asset not found for name: \(lutName)")
            return (nil, 0)
        }

        // 3. Write cache (write lock)
        cacheQueue.async(flags: .barrier) {
            self.lutDataCache[lutName] = data
            self.lutSizeCache[lutName] = loadedSize
        }

        return (data, loadedSize)
    }

    /// .cube file Data converted to CIColorCube data
    private func lutDataForCIColorCube(from cubeData: Data, size: Int, lutName: String? = nil) -> Data? {
        // Check cache first
        if let name = lutName {
            var cached: Data?
            cacheQueue.sync {
                cached = cubeDataCache[name]
            }
            if let cached {
                return cached
            }
        }

        // Parse .cube file to CIColorCube data (float RGBA)
        guard let cubeString = String(data: cubeData, encoding: .utf8) else {
            return nil
        }
        let lines = cubeString.components(separatedBy: .newlines)
        var cubeValues: [Float] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed
                .hasPrefix("#") || trimmed
                .hasPrefix("TITLE") || trimmed
                .hasPrefix("LUT_3D_SIZE") || trimmed
                .hasPrefix("DOMAIN_MIN") || trimmed
                .hasPrefix("DOMAIN_MAX")
            {
                continue
            }
            let parts = trimmed.split(separator: " ").compactMap { Float($0) }
            if parts.count == 3 {
                cubeValues.append(contentsOf: parts)
            }
        }
        let expectedCount = size * size * size * 3
        guard cubeValues.count == expectedCount else {
            print(
                "LUT data count mismatch: got \(cubeValues.count), expected \(expectedCount)"
            )
            return nil
        }
        // CIColorCube expects RGBA, so add alpha=1.0
        var rgba: [Float] = []
        for i in stride(from: 0, to: cubeValues.count, by: 3) {
            rgba.append(cubeValues[i])
            rgba.append(cubeValues[i + 1])
            rgba.append(cubeValues[i + 2])
            rgba.append(1.0)
        }
        let result = Data(
            buffer: UnsafeBufferPointer(start: &rgba, count: rgba.count)
        )
        // write cache
        if let name = lutName {
            cacheQueue.async(flags: .barrier) {
                self.cubeDataCache[name] = result
            }
        }
        return result
    }

    func applyLutFilter(to ciImage: CIImage, lutName: String, intensity: Float = 1.0) -> CIImage {
        let (lutData, lutSize) = loadLutData(lutName: lutName)
        guard let lutData, lutSize > 0 else { return ciImage }
        return applyLutFilter(to: ciImage, lutData: lutData, lutSize: lutSize, lutName: lutName, intensity: intensity)
    }

    func applyLutFilter(to ciImage: CIImage, lutData: Data, lutSize: Int, lutName: String? = nil, intensity: Float = 1.0) -> CIImage {
        guard let colorCubeData = lutDataForCIColorCube(from: lutData, size: lutSize, lutName: lutName) else {
            return ciImage
        }
        let filter = CIFilter.colorCubeWithColorSpace()
        filter.colorSpace = CGColorSpaceCreateDeviceRGB()
        filter.inputImage = ciImage
        filter.cubeDimension = Float(lutSize)
        filter.cubeData = colorCubeData

        guard let filteredImage = filter.outputImage else { return ciImage }

        // If the intensity is 1.0, return the filter effect directly
        if intensity >= 0.99 {
            return filteredImage
        }

        // If the intensity is 0, return to the original image
        if intensity <= 0.01 {
            return ciImage
        }

        // Use linear interpolation to blend original image and filter effect
        let blendFilter = CIFilter(name: "CIBlendWithMask")

        // Create a solid color mask to control blend ratio
        let maskImage = CIImage(color: CIColor(red: CGFloat(intensity), green: CGFloat(intensity), blue: CGFloat(intensity), alpha: 1.0))
            .cropped(to: ciImage.extent)

        blendFilter?.setValue(filteredImage, forKey: kCIInputImageKey)
        blendFilter?.setValue(ciImage, forKey: kCIInputBackgroundImageKey)
        blendFilter?.setValue(maskImage, forKey: kCIInputMaskImageKey)

        return blendFilter?.outputImage ?? filteredImage
    }

    // MARK: - Unified Filter Application

    /// Apply currently selected filter
    /// - Parameters:
    ///   - ciImage: input image
    ///   - frameSeed: frame seed, used for time domain changes of video particles (nil = static picture)
    ///   - quality: processing quality (.Preview = quick Preview, .full = full quality)
    func applyFilter(to ciImage: CIImage, frameSeed: UInt32? = nil, quality: FilmEmulationQuality = .full) -> CIImage {
        let snapshots = currentSnapshots()

        // 1/2/3. Optical -> Color Grading -> Finishing
        // - No Color Grading (Film simulation/No Filter): Go directly to FilmEmulation (allows CineTone)
        // - With Color Grading (LUT/built-in chain/custom): CineTone is mutually exclusive; FilmEmulation is split into Optical/Finishing

        if let config = snapshots.base.processingConfig {
            switch config.processingType {
            case .builtin:
                // Film simulation (builtin chain) special logic
                // 1. Apply Base Look (Vivid, etc.)
                let base = applyLook(
                    to: ciImage,
                    processingConfig: config,
                    intensity: snapshots.base.intensity,
                    customLut: snapshots.base.customLut
                )

                return FilmEmulation.apply(
                    to: base,
                    snapshot: snapshots.effects,
                    enableCineTone: true,
                    frameSeed: frameSeed,
                    quality: quality
                )

            case .lut, .custom:
                // LUT / Custom LUT: cineTone is mutually exclusive; FilmEmulation is split into Optical/Finishing to ensure the final style of Color Grading is stable
                let optical = FilmEmulation.applyOpticalStage(
                    to: ciImage,
                    snapshot: snapshots.effects,
                    frameSeed: frameSeed,
                    quality: quality
                )

                let graded = applyLook(
                    to: optical,
                    processingConfig: config,
                    intensity: snapshots.base.intensity,
                    customLut: snapshots.base.customLut
                )

                return FilmEmulation.applyFinishingStage(
                    to: graded,
                    snapshot: snapshots.effects,
                    frameSeed: frameSeed,
                    quality: quality
                )
            }
        }

        // No base filter: FilmEmulation as main style (allows CineTone)
        return FilmEmulation.apply(
            to: ciImage,
            snapshot: snapshots.effects,
            enableCineTone: true,
            frameSeed: frameSeed,
            quality: quality
        )
    }

    /// Apply specified filter configuration
    /// - Parameters:
    ///   - ciImage: input image
    ///   - processingConfig: filter processing configuration
    ///   - intensity: filter intensity
    ///   - frameSeed: frame seed, used for time domain changes of video particles (nil = static picture)
    ///   - quality: processing quality (.Preview = quick Preview, .full = full quality)
    func applyFilter(
        to ciImage: CIImage,
        processingConfig: FilterProcessingConfig,
        intensity: Float,
        frameSeed: UInt32? = nil,
        quality: FilmEmulationQuality = .full
    ) -> CIImage {
        let snapshots = currentSnapshots()
        let customLut: CustomLutSnapshot?
        if case .custom = processingConfig.processingType {
            customLut = snapshots.base.customLut
        } else {
            customLut = nil
        }

        switch processingConfig.processingType {
        case .builtin:
            let base = applyLook(
                to: ciImage,
                processingConfig: processingConfig,
                intensity: intensity,
                customLut: customLut
            )

            return FilmEmulation.apply(
                to: base,
                snapshot: snapshots.effects,
                enableCineTone: true,
                frameSeed: frameSeed,
                quality: quality
            )

        case .lut, .custom:
            let optical = FilmEmulation.applyOpticalStage(
                to: ciImage,
                snapshot: snapshots.effects,
                frameSeed: frameSeed,
                quality: quality
            )

            let graded = applyLook(
                to: optical,
                processingConfig: processingConfig,
                intensity: intensity,
                customLut: customLut
            )

            return FilmEmulation.applyFinishingStage(
                to: graded,
                snapshot: snapshots.effects,
                frameSeed: frameSeed,
                quality: quality
            )
        }
    }

    private func applyLook(
        to ciImage: CIImage,
        processingConfig: FilterProcessingConfig,
        intensity: Float,
        customLut: CustomLutSnapshot?
    ) -> CIImage {
        switch processingConfig.processingType {
        case let .lut(lutName):
            return applyLutFilter(to: ciImage, lutName: lutName, intensity: intensity)

        case .builtin:
            return applyBuiltinFilter(to: ciImage, chain: processingConfig.chain, intensity: intensity)

        case .custom:
            guard let customLut else { return ciImage }
            return applyLutFilter(
                to: ciImage,
                lutData: customLut.lutData,
                lutSize: customLut.lutSize,
                lutName: customLut.cacheKey,
                intensity: intensity
            )
        }
    }

    // MARK: - Built-in filter application

    private func applyBuiltinFilter(to ciImage: CIImage, chain: [FilterChainStep]?, intensity: Float = 1.0) -> CIImage {
        // If chain is nil or empty, return to the original image directly.
        guard let chain, !chain.isEmpty else { return ciImage }

        var currentImage = ciImage

        for step in chain {
            currentImage = applyFilterStep(to: currentImage, step: step)
        }

        // If the intensity is not 1.0, blend the original image
        if intensity < 0.99 {
            return blendImages(original: ciImage, filtered: currentImage, intensity: intensity)
        }

        return currentImage
    }

    private func applyFilterStep(to ciImage: CIImage, step: FilterChainStep) -> CIImage {
        switch step.filterName {
        case "CIColorControls":
            let filter = CIFilter.colorControls()
            filter.inputImage = ciImage
            if let saturation = step.parameters["saturation"] as? Float {
                filter.saturation = saturation
            }
            if let brightness = step.parameters["brightness"] as? Float {
                filter.brightness = brightness
            }
            if let contrast = step.parameters["contrast"] as? Float {
                filter.contrast = contrast
            }
            return filter.outputImage ?? ciImage

        case "CIVibrance":
            let filter = CIFilter.vibrance()
            filter.inputImage = ciImage
            if let amount = step.parameters["amount"] as? Float {
                filter.amount = amount
            }
            return filter.outputImage ?? ciImage

        case "CITemperatureAndTint":
            let filter = CIFilter.temperatureAndTint()
            filter.inputImage = ciImage
            let useCaptureNeutral = step.parameters["useCaptureNeutral"] as? Bool ?? false

            let providedNeutral = step.parameters["neutral"] as? CIVector
            let neutral: CIVector?
            if useCaptureNeutral {
                let wb = CameraDeviceManager.shared.getCurrentWhiteBalance()
                neutral = CIVector(x: CGFloat(wb.temperature), y: CGFloat(wb.tint))
            } else {
                neutral = providedNeutral
            }
            if let neutral {
                filter.neutral = neutral
            }

            func numberValue(_ value: Any?) -> Float? {
                if let f = value as? Float { return f }
                if let d = value as? Double { return Float(d) }
                if let i = value as? Int { return Float(i) }
                return nil
            }

            if let neutral,
               let tempDelta = numberValue(step.parameters["temperatureDelta"]),
               let tintDelta = numberValue(step.parameters["tintDelta"])
            {
                filter.targetNeutral = CIVector(x: neutral.x + CGFloat(tempDelta), y: neutral.y + CGFloat(tintDelta))
            } else if let targetNeutral = step.parameters["targetNeutral"] as? CIVector {
                filter.targetNeutral = targetNeutral
            }
            return filter.outputImage ?? ciImage

        case "CIPixellate":
            let filter = CIFilter.pixellate()
            filter.inputImage = ciImage
            if let scale = step.parameters["scale"] as? Float {
                filter.scale = scale
            }
            return filter.outputImage ?? ciImage

        case "CIVignette":
            let filter = CIFilter.vignette()
            filter.inputImage = ciImage
            if let intensity = step.parameters["intensity"] as? Float {
                filter.intensity = intensity
            }
            if let radius = step.parameters["radius"] as? Float {
                filter.radius = radius
            }
            return filter.outputImage ?? ciImage

        case "CIHighlightShadowAdjust":
            let filter = CIFilter.highlightShadowAdjust()
            filter.inputImage = ciImage
            if let shadowAmount = step.parameters["shadowAmount"] as? Float {
                filter.shadowAmount = shadowAmount
            }
            if let highlightAmount = step.parameters["highlightAmount"] as? Float {
                filter.highlightAmount = highlightAmount
            }
            return filter.outputImage ?? ciImage

        case "CIPhotoEffectInstant":
            let filter = CIFilter.photoEffectInstant()
            filter.inputImage = ciImage
            return filter.outputImage ?? ciImage

        case "CIPhotoEffectNoir":
            let filter = CIFilter.photoEffectNoir()
            filter.inputImage = ciImage
            return filter.outputImage ?? ciImage

        case "CIPhotoEffectFade":
            let filter = CIFilter.photoEffectFade()
            filter.inputImage = ciImage
            return filter.outputImage ?? ciImage

        case "CIPhotoEffectChrome":
            let filter = CIFilter.photoEffectChrome()
            filter.inputImage = ciImage
            return filter.outputImage ?? ciImage

        case "CIColorMonochrome":
            let filter = CIFilter.colorMonochrome()
            filter.inputImage = ciImage
            if let color = step.parameters["color"] as? CIColor {
                filter.color = color
            }
            if let intensity = step.parameters["intensity"] as? Float {
                filter.intensity = intensity
            }
            return filter.outputImage ?? ciImage

        case "CIUnsharpMask":
            let filter = CIFilter.unsharpMask()
            filter.inputImage = ciImage
            if let intensity = step.parameters["intensity"] as? Float {
                filter.intensity = intensity
            }
            if let radius = step.parameters["radius"] as? Float {
                filter.radius = radius
            }
            return filter.outputImage ?? ciImage

        case "CIToneCurve":
            let filter = CIFilter.toneCurve()
            filter.inputImage = ciImage
            if let point0 = step.parameters["point0"] as? CGPoint {
                filter.point0 = point0
            }
            if let point1 = step.parameters["point1"] as? CGPoint {
                filter.point1 = point1
            }
            if let point2 = step.parameters["point2"] as? CGPoint {
                filter.point2 = point2
            }
            if let point3 = step.parameters["point3"] as? CGPoint {
                filter.point3 = point3
            }
            if let point4 = step.parameters["point4"] as? CGPoint {
                filter.point4 = point4
            }
            return filter.outputImage ?? ciImage

        case "CINoiseReduction":
            let filter = CIFilter(name: "CINoiseReduction")
            filter?.setValue(ciImage, forKey: kCIInputImageKey)
            if let noiseLevel = step.parameters["noiseLevel"] as? Float {
                filter?.setValue(noiseLevel, forKey: "inputNoiseLevel")
            }
            if let sharpness = step.parameters["sharpness"] as? Float {
                filter?.setValue(sharpness, forKey: "inputSharpness")
            }
            return filter?.outputImage ?? ciImage

        default:
            print("Unknown filter: \(step.filterName)")
            return ciImage
        }
    }

    // MARK: - Custom filter application

    private func applyCustomFilter(to ciImage: CIImage, chain _: [FilterChainStep]?, intensity: Float = 1.0) -> CIImage {
        guard let customFilter = selectedCustomFilter else { return ciImage }
        let (lutData, lutSize) = CustomFilterManager.shared.getLutData(for: customFilter)
        guard let lutData, lutSize > 0 else { return ciImage }

        // Use UUID as cache key for LUT data
        return applyLutFilter(to: ciImage, lutData: lutData, lutSize: lutSize, lutName: customFilter.id.uuidString, intensity: intensity)
    }

    // MARK: - Image blending auxiliary method

    func blendImages(original: CIImage, filtered: CIImage, intensity: Float) -> CIImage {
        if intensity >= 0.99 {
            return filtered
        }

        if intensity <= 0.01 {
            return original
        }

        let blendFilter = CIFilter(name: "CIBlendWithMask")

        let maskImage = CIImage(color: CIColor(red: CGFloat(intensity), green: CGFloat(intensity), blue: CGFloat(intensity), alpha: 1.0))
            .cropped(to: original.extent)

        blendFilter?.setValue(filtered, forKey: kCIInputImageKey)
        blendFilter?.setValue(original, forKey: kCIInputBackgroundImageKey)
        blendFilter?.setValue(maskImage, forKey: kCIInputMaskImageKey)

        return blendFilter?.outputImage ?? filtered
    }

    // MARK: - Collection related

    func toggleFavorite(_ filter: FilterIdentifier) {
        if let idx = favoriteFilters.firstIndex(of: filter) {
            favoriteFilters.remove(at: idx)
        } else {
            favoriteFilters.append(filter)
        }
    }

    func isFavorite(_ filter: FilterIdentifier) -> Bool {
        favoriteFilters.contains(filter)
    }

    // MARK: - Related to filter display settings

    func toggleFilterVisibility(_ filter: FilterIdentifier) {
        if let idx = hiddenFilters.firstIndex(of: filter) {
            hiddenFilters.remove(at: idx)
        } else {
            hiddenFilters.append(filter)
        }
    }

    func isFilterVisible(_ filter: FilterIdentifier) -> Bool {
        !hiddenFilters.contains(filter)
    }

    /// Get all visible built-in filters
    var allVisibleFilters: [FilterIdentifier] {
        configManager.getAllBuiltinIdentifiers().filter { isFilterVisible($0) }
    }

    /// Get the list of visible favorite filters
    var visibleFavoriteFilters: [FilterIdentifier] {
        favoriteFilters.filter { isFilterVisible($0) && $0.category != .custom }
    }

    /// Get the list of visible filters consistent with the order in FilterGalleryView
    /// Sequence: 1. Favorite filters 2. Other filters (exclude already collected ones)
    func getOrderedVisibleFilters() -> [FilterIdentifier] {
        var orderedFilters: [FilterIdentifier] = []

        // 1. Add favorite filters
        let visibleFavorites = visibleFavoriteFilters
        orderedFilters.append(contentsOf: visibleFavorites)

        // 2. Add other filters (excluding favorites)
        let favoriteSet = Set(visibleFavorites)
        let otherFilters = allVisibleFilters.filter { !favoriteSet.contains($0) }
        orderedFilters.append(contentsOf: otherFilters)

        return orderedFilters
    }

    // MARK: - Filter Navigation

    private enum SelectableFilter: Equatable {
        case standard(FilterIdentifier)
        case custom(CustomFilter)

        var displayName: String {
            switch self {
            case let .standard(id): return id.displayName
            case let .custom(filter): return filter.name
            }
        }

        static func == (lhs: SelectableFilter, rhs: SelectableFilter) -> Bool {
            switch (lhs, rhs) {
            case let (.standard(l), .standard(r)):
                return l == r
            case let (.custom(l), .custom(r)):
                return l.id == r.id
            default:
                return false
            }
        }
    }

    private func getFullOrderedSelectableFilters() -> [SelectableFilter] {
        let customFilterManager = CustomFilterManager.shared

        // 1. Collection of built-in filters (excluding Film simulation)
        let favStandard = visibleFavoriteFilters.filter { !$0.isFilmSimulationOrNone }

        // 2. Collection of custom filters
        let favCustom = customFilterManager.customFilters.filter(\.isFavorite)

        // 3. Film simulation filters
        let originals = FilterIdentifier.filmSimulationFilters.filter { isFilterVisible($0) }

        // 4. Other built-in filters (not collection, not Film simulation)
        let favoriteSet = Set(visibleFavoriteFilters)
        let otherStandard = allVisibleFilters.filter { !favoriteSet.contains($0) && !$0.isFilmSimulationOrNone }

        // 5. Other custom filters (not favorites)
        let otherCustom = customFilterManager.customFilters.filter { !$0.isFavorite }

        var result: [SelectableFilter] = []
        result.append(contentsOf: favStandard.map { .standard($0) })
        result.append(contentsOf: favCustom.map { .custom($0) })
        result.append(contentsOf: originals.map { .standard($0) })
        result.append(contentsOf: otherStandard.map { .standard($0) })
        result.append(contentsOf: otherCustom.map { .custom($0) })

        return result
    }

    /// Selects the next filter in the sequence following the visual order in FilterGalleryView
    @discardableResult
    func selectNextFilter() -> String {
        let allFilters = getFullOrderedSelectableFilters()
        guard !allFilters.isEmpty else { return "" }

        let current: SelectableFilter
        if selectedFilter.category == .custom, let custom = selectedCustomFilter {
            current = .custom(custom)
        } else {
            current = .standard(selectedFilter)
        }

        let nextIndex: Int
        if let currentIndex = allFilters.firstIndex(of: current) {
            nextIndex = (currentIndex + 1) % allFilters.count
        } else {
            nextIndex = 0
        }

        let nextFilter = allFilters[nextIndex]
        applySelectableFilter(nextFilter)
        return nextFilter.displayName
    }

    /// Selects the previous filter in the sequence following the visual order in FilterGalleryView
    @discardableResult
    func selectPreviousFilter() -> String {
        let allFilters = getFullOrderedSelectableFilters()
        guard !allFilters.isEmpty else { return "" }

        let current: SelectableFilter
        if selectedFilter.category == .custom, let custom = selectedCustomFilter {
            current = .custom(custom)
        } else {
            current = .standard(selectedFilter)
        }

        let prevIndex: Int
        if let currentIndex = allFilters.firstIndex(of: current) {
            prevIndex = (currentIndex - 1 + allFilters.count) % allFilters.count
        } else {
            prevIndex = allFilters.count - 1
        }

        let prevFilter = allFilters[prevIndex]
        applySelectableFilter(prevFilter)
        return prevFilter.displayName
    }

    private func applySelectableFilter(_ selectable: SelectableFilter) {
        switch selectable {
        case let .standard(id):
            selectedFilter = id
            // If we switch to a standard filter, we should probably clear or keep the custom filter state?
            // Usually, selectedFilter's category will tell us if it's custom.
            // But let's be safe and keep selectedCustomFilter if it was already set,
            // though selectedFilter being .builtin will override it during application.
            if id.category != .custom {
                // We don't strictly need to nil it, but it's cleaner if we want to know we are NOT in custom mode.
                // However, the existing code keeps it. Let's look at applyFilter.
            }
        case let .custom(filter):
            selectCustomFilter(filter)
        }
    }

    // MARK: - Select a custom filter

    func selectCustomFilter(_ customFilter: CustomFilter) {
        selectedCustomFilter = customFilter
        selectedFilter = .custom(customFilter.name)
        print("已选择自定义滤镜: \(customFilter.name)")
    }

    // MARK: - Filter switching prompt copy

    /// Unified generation of filter switching prompt text and icons
    /// - Parameters:
    ///   - filter: target filter
    ///   - intensity: optional intensity override value; if not passed, read the current filter intensity
    /// - Returns: `(message, icon)`
    func makeFilterSwitchToastContent(for filter: FilterIdentifier, intensity: Float? = nil) -> (message: String, icon: String) {
        if filter.isFilmSimulation {
            return (filter.displayName, "film")
        }

        let currentIntensity = intensity ?? getIntensity(for: filter)
        let percentage = Int(currentIntensity * 100)
        return (.cameraFilterIntensityFormat.localized(filter.displayName, percentage), "camera.filters")
    }

    // MARK: - Raw processing entry

    /// Working with Raw filter pipeline (Integrated Raw development + Film simulation)
    /// This is the recommended entry point for processing RAW formats, which prioritizes high-quality CIRAWFilter-based decoding configurations.
    func processRawFilter(
        _ rawFilter: CIRAWFilter,
        isNight: Bool = false,
        deviceOrientation: UIDeviceOrientation? = nil,
        cameraPosition: AVCaptureDevice.Position? = nil,
        frameSeed: UInt32? = nil,
        quality: FilmEmulationQuality = .full
    ) -> CIImage? {
        // 1. Configure Raw decoding parameters (using the logic in FilterManager+Raw.swift)
        configureRawFilter(
            rawFilter,
            isNight: isNight,
            deviceOrientation: deviceOrientation,
            cameraPosition: cameraPosition
        )

        // 2. Get the decoded image
        guard let developedImage = rawFilter.outputImage else {
            print("Error: CIRAWFilter outputImage is nil")
            return nil
        }

        // 3. Apply subsequent Film simulation chain
        // Note: isRaw passes false. Because configureRawFilter has completed Raw development (Tone Mapping, Boost, etc.),
        // At this time, developedImage is already an image with normal color and does not need to go through the applyRawDevelopment (Gamma correction) step inside applyFilter.
        return applyFilter(
            to: developedImage,
            frameSeed: frameSeed,
            quality: quality
        )
    }
}
