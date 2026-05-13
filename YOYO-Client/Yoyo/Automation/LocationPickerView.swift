import MapKit
import SwiftUI

// MARK: - Location Picker

struct LocationPickerView: View {
    let onSelect: (AutomationCondition) -> Void
    @Environment(\.dismiss) private var dismiss

    init(onSelect: @escaping (AutomationCondition) -> Void) {
        self.onSelect = onSelect
    }

    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    private var locationManager = LocationManager.shared
    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var radius: Double = 100
    @State private var hasSetInitialLocation = false

    private let radiusOptions = AutomationFormatters.radiusOptions

    var body: some View {
        ZStack(alignment: .bottom) {
            // Map Layer
            MapView(region: $region, selectedCoordinate: $selectedCoordinate, onTapCoordinate: { selectedCoordinate = $0 })
                .ignoresSafeArea()

            // Center Pin Indicator (Only if no specific coordinate selected)
            if selectedCoordinate == nil {
                VStack(spacing: 0) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                        .background(Circle().fill(.white))
                        .shadow(radius: 4)
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.caption)
                        .foregroundColor(.white)
                        .offset(y: -5)
                }
                .offset(y: -20)
                .allowsHitTesting(false)
            }

            // Top Search Bar
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    // Close Button (Toolbar Icon Style)
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.black.opacity(0.65))
                            .clipShape(Circle())
                    }

                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white.opacity(0.8))
                        TextField(String.automationSearchLocation.localized, text: $searchText)
                            .foregroundColor(.white)
                            .submitLabel(.search)
                            .onSubmit { searchLocation() }
                        if !searchText.isEmpty {
                            Button(action: { searchText = ""; searchResults = [] }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.black.opacity(0.65))
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 8)

                if !searchResults.isEmpty {
                    List(searchResults, id: \.self) { item in
                        Button(action: { selectSearchResult(item) }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name ?? String.automationUnknownLocation.localized)
                                    .foregroundColor(.white)
                                if let title = item.placemark.title {
                                    Text(title).font(.caption).foregroundColor(.white.opacity(0.7))
                                }
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .frame(maxHeight: 250)
                    .background(Color.black.opacity(0.65))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    .shadow(radius: 10)
                }

                Spacer()
            }

            // Bottom Control Panel
            VStack(spacing: 20) {
                // Location Info & Current Location
                VStack(spacing: 16) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(String.automationSelectedLocation.localized)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white.opacity(0.7))
                            let coord = selectedCoordinate ?? region.center
                            Text(String(format: "%.5f, %.5f", coord.latitude, coord.longitude))
                                .font(.system(.title3, design: .monospaced))
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                        }

                        Spacer()

                        Button(action: moveToCurrentLocation) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(.white.opacity(0.2))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 4)
                }

                // Radius Selection
                VStack(alignment: .leading, spacing: 12) {
                    Text(String.automationTriggerRange.localized)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.7))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(radiusOptions, id: \.1) { option in
                                let isSelected = radius == option.1
                                Button(action: { radius = option.1 }) {
                                    Text(option.0)
                                        .font(.system(size: 14, weight: .medium))
                                        .fontWeight(isSelected ? .semibold : .medium)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                        .background(isSelected ? .white : .white.opacity(0.15))
                                        .foregroundColor(isSelected ? .black : .white)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }

                // Confirm Button
                Button(action: confirmSelection) {
                    Text(String.automationConfirmSelection.localized)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(.white)
                        .clipShape(Capsule())
                        .shadow(color: .white.opacity(0.4), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(20)
            .background(Color.black.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 30))
            .padding(.horizontal)
            .padding(.bottom, 0)
        }
        .onAppear {
            locationManager.requestWhenInUseAuthorization()

            locationManager.onLocationUpdated = { location in
                if !hasSetInitialLocation {
                    withAnimation {
                        region.center = location.coordinate
                    }
                    hasSetInitialLocation = true
                }
            }

            locationManager.startMonitoring()

            if let location = locationManager.currentLocation, !hasSetInitialLocation {
                region.center = location.coordinate
                hasSetInitialLocation = true
            }
        }
        .onDisappear {
            locationManager.stopMonitoring()
        }
        .trackScreen(name: "AutomationLocationPicker")
    }

    private func searchLocation() {
        guard !searchText.isEmpty else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        request.region = region
        MKLocalSearch(request: request).start { response, _ in
            searchResults = response?.mapItems ?? []
        }
    }

    private func selectSearchResult(_ item: MKMapItem) {
        selectedCoordinate = item.placemark.coordinate
        region.center = item.placemark.coordinate
        searchResults = []
        searchText = item.name ?? ""
    }

    private func moveToCurrentLocation() {
        if let location = locationManager.currentLocation {
            selectedCoordinate = location.coordinate
            region.center = location.coordinate
        }
    }

    private func confirmSelection() {
        let coord = selectedCoordinate ?? region.center
        onSelect(.nearLocation(latitude: coord.latitude, longitude: coord.longitude, radiusMeters: radius))
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    LocationPickerView { condition in
        print("Selected condition: \(condition)")
    }
}
