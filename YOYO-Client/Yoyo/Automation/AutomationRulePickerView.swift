import AVFoundation
import MapKit
import SwiftUI
import UIKit

// MARK: - Picker Types

enum AutomationRulePickerType {
    case condition
    case action
}

struct AutomationCategory: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let icon: String
    let type: CategoryType

    enum CategoryType {
        /// Condition Categories
        case scene, lighting, composition, subject, motion, exposureCondition, color, time, location, altitude, capture
        /// Action Categories
        case zoom, exposureAction, flash, focus, filter, whiteBalance, iso, shutterSpeed, toast
    }
}

// MARK: - Main Picker View

struct AutomationRulePickerView: View {
    let selectionType: AutomationRulePickerType
    var onSelectCondition: ((AutomationCondition) -> Void)?
    var onSelectAction: ((AutomationAction) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: AutomationCategory?

    // Dark Theme Colors
    private let backgroundColor = Color.black
    private let accentColor = Color.accentColor

    private var categories: [AutomationCategory] {
        switch selectionType {
        case .condition:
            return [
                .init(name: String.categoryScene.localized, icon: "camera.macro", type: .scene),
                .init(name: String.categoryLighting.localized, icon: "sun.max.fill", type: .lighting),
                .init(name: String.categoryComposition.localized, icon: "grid", type: .composition),
                .init(name: String.categorySubject.localized, icon: "person.fill", type: .subject),
                .init(name: String.categoryMotion.localized, icon: "figure.run", type: .motion),
                .init(name: String.categoryExposureCondition.localized, icon: "camera.aperture", type: .exposureCondition),
                .init(name: String.categoryColor.localized, icon: "paintpalette.fill", type: .color),
                .init(name: String.categoryTime.localized, icon: "clock.fill", type: .time),
                .init(name: String.categoryLocation.localized, icon: "location.fill", type: .location),
                .init(name: String.categoryAltitude.localized, icon: "mountain.2.fill", type: .altitude),
                .init(name: String.categoryCapture.localized, icon: "camera.shutter.button.fill", type: .capture),
            ]
        case .action:
            return [
                .init(name: String.categoryZoom.localized, icon: "plus.magnifyingglass", type: .zoom),
                .init(name: String.categoryExposureAction.localized, icon: "slider.horizontal.3", type: .exposureAction),
                .init(name: String.categoryFlash.localized, icon: "bolt.fill", type: .flash),
                .init(name: String.categoryFocus.localized, icon: "scope", type: .focus),
                .init(name: String.categoryFilter.localized, icon: "camera.filters", type: .filter),
                .init(name: String.categoryWhiteBalance.localized, icon: "thermometer.sun", type: .whiteBalance),
                .init(name: String.categoryIso.localized, icon: "camera.aperture", type: .iso),
                .init(name: String.categoryShutter.localized, icon: "timer", type: .shutterSpeed),
                .init(name: String.categoryToast.localized, icon: "message", type: .toast),
            ]
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left Sidebar
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(categories) { category in
                            Button {
                                selectedCategory = category
                            } label: {
                                CategoryRow(
                                    category: category,
                                    isSelected: selectedCategory?.id == category.id,
                                    accentColor: accentColor
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical)
                }
            }
            .background(backgroundColor)
            .frame(width: 88)

            // Right Content
            VStack(spacing: 0) {
                if let category = selectedCategory {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(category.name)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.top)

                            optionsView(for: category)
                        }
                        .padding()
                    }
                } else {
                    VStack {
                        Image(systemName: "arrow.left")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                        Text(String.automationSelectCategory.localized)
                            .foregroundColor(.gray)
                    }
                }
            }
            .background(backgroundColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(selectionType == .condition ? String.automationIfTitle.localized : String.automationThenTitle.localized)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.white)
                }
                .buttonStyle(.borderless)
            }
        }
        .onAppear {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            if selectedCategory == nil { selectedCategory = categories.first }
        }
        .preferredColorScheme(.dark)
        .trackScreen(name: selectionType == .condition ? "AutomationConditionPicker" : "AutomationActionPicker")
    }

    // MARK: - Option Builders

    private func option(_ condition: AutomationCondition) -> OptionRow {
        let title = condition.detailText.isEmpty ? condition.titleText : "\(condition.titleText) \(condition.detailText)"
        return OptionRow(title: title) {
            onSelectCondition?(condition)
            dismiss()
        }
    }

    private func option(_ action: AutomationAction) -> OptionRow {
        let title = action.detailText.isEmpty ? action.titleText : "\(action.titleText) \(action.detailText)"
        return OptionRow(title: title) {
            onSelectAction?(action)
            dismiss()
        }
    }

    @ViewBuilder
    private func optionsView(for category: AutomationCategory) -> some View {
        switch category.type {
        // Conditions
        case .scene:
            ForEach(SceneType.allCases, id: \.self) { type in
                option(.sceneIs(type))
            }
        case .lighting:
            ForEach(LightingCondition.allCases, id: \.self) { type in
                option(.lightingIs(type))
            }
        case .composition:
            Group {
                option(.ruleOfThirdsAlignmentAbove(0.8))
                option(.visualBalanceAbove(0.7))
                option(.leadingLineStrengthAbove(0.6))
                option(.backgroundIsSimple)
                option(.backgroundIsComplex)
            }
        case .subject:
            Group {
                option(.subjectTypeIs(.face))
                option(.hasMainSubject)
                option(.subjectSizeAbove(0.3))
                option(.subjectSizeBelow(0.1))
                option(.objectCountAbove(2))
            }
        case .motion:
            Group {
                option(.motionLevelBelow(0.1))
                option(.motionLevelAbove(0.2))
                option(.motionLevelAbove(0.6))
            }
        case .exposureCondition:
            Group {
                option(.isOverexposed)
                option(.highlightRatioAbove(0.2))
                option(.highlightRatioBelow(0.05))
            }
        case .color:
            ColorConditionOptionsView(onSelect: { onSelectCondition?($0); dismiss() })
        case .time:
            TimeConditionOptionsView(onSelect: { onSelectCondition?($0); dismiss() })
        case .location:
            LocationConditionOptionsView(onSelect: { onSelectCondition?($0); dismiss() })
        case .altitude:
            AltitudeConditionOptionsView(onSelect: { onSelectCondition?($0); dismiss() })
        case .capture:
            Group {
                option(.beforeCapture)
                option(.afterCapture)
            }
        // Actions
        case .zoom:
            Group {
                option(.setZoom(1.0))
                option(.setZoom(2.0))
                option(.setZoom(3.0))
                option(.setZoom(5.0))
                option(.setZoom(10.0))
                option(.multiplyZoom(1.5))
                option(.multiplyZoom(2.0))
            }
        case .exposureAction:
            Group {
                option(.addExposureBias(0.5))
                option(.addExposureBias(1.0))
                option(.addExposureBias(-0.5))
                option(.addExposureBias(-1.0))
                option(.setExposureBias(0))
            }
        case .flash:
            Group {
                option(.setFlashMode(.on))
                option(.setFlashMode(.off))
            }
        case .focus:
            Group {
                option(.focusOnSubject)
                option(.focusOnRuleOfThirds)
            }
        case .filter:
            FilterActionOptionsView(onSelect: { onSelectAction?($0); dismiss() })
        case .whiteBalance:
            WhiteBalanceActionOptionsView(onSelect: { onSelectAction?($0); dismiss() })
        case .iso:
            ISOActionOptionsView(onSelect: { onSelectAction?($0); dismiss() })
        case .shutterSpeed:
            ShutterSpeedActionOptionsView(onSelect: { onSelectAction?($0); dismiss() })
        case .toast:
            ToastActionOptionsView(onSelect: { onSelectAction?($0); dismiss() })
        }
    }
}

struct CategoryRow: View {
    let category: AutomationCategory
    let isSelected: Bool
    let accentColor: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: category.icon)
                .font(.system(size: 24))
                .foregroundColor(isSelected ? accentColor : .gray)

            Text(category.name)
                .font(.caption)
                .foregroundColor(isSelected ? accentColor : .gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(isSelected ? accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(8)
        .contentShape(Rectangle())
    }
}

struct OptionRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    init(title: String, isSelected: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center) {
                Text(title)
                    .foregroundColor(.white)
                    .font(.system(size: 16))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Circle()
                    .strokeBorder(Color.gray, lineWidth: 2)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Circle()
                            .fill(isSelected ? Color.accentColor : Color.clear)
                            .padding(4)
                    )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(red: 0.16, green: 0.16, blue: 0.18))
            .cornerRadius(12)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Shared UI Components & Constants

private struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundColor(.white.opacity(0.6))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top)
    }
}

struct PickerSheetWrapper<Content: View>: View {
    let title: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
    let isConfirmDisabled: Bool
    @ViewBuilder let content: Content

    init(title: String, isConfirmDisabled: Bool = false, onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.isConfirmDisabled = isConfirmDisabled
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self.content = content()
    }

    var body: some View {
        NavigationView {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String.automationConfirmButton.localized, action: onConfirm)
                            .disabled(isConfirmDisabled)
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String.commonCancel.localized, action: onCancel)
                    }
                }
        }
    }
}

// MARK: - Time Condition Options

struct TimeConditionOptionsView: View {
    let onSelect: (AutomationCondition) -> Void
    @State private var showingTimePicker = false
    @State private var showingTimeRangePicker = false
    @State private var showingWeekdayPicker = false
    @State private var showingDatePicker = false
    @State private var showingNthWeekdayPicker = false

    private func option(_ condition: AutomationCondition) -> OptionRow {
        OptionRow(title: condition.displayText) { onSelect(condition) }
    }

    var body: some View {
        VStack(spacing: 12) {
            Group {
                SectionHeader(title: String.automationTimeCommonPeriods.localized)
                option(.timeInRange(startHour: 6, startMinute: 0, endHour: 18, endMinute: 0))
                option(.timeInRange(startHour: 18, startMinute: 0, endHour: 6, endMinute: 0))
            }

            Group {
                SectionHeader(title: String.automationTimeCommonWeekdays.localized)
                option(.weekdayIn([2, 3, 4, 5, 6]))
                option(.weekdayIn([1, 7]))
            }

            Group {
                SectionHeader(title: String.commonCustom.localized)
                OptionRow(title: String.automationTimeCustomRange.localized) { showingTimeRangePicker = true }
                OptionRow(title: String.automationTimeCustomPoint.localized) { showingTimePicker = true }
                OptionRow(title: String.automationTimeCustomWeekday.localized) { showingWeekdayPicker = true }
                OptionRow(title: String.automationTimeCustomDate.localized) { showingDatePicker = true }
                OptionRow(title: String.automationTimeNthWeekday.localized) { showingNthWeekdayPicker = true }
            }
        }
        .sheet(isPresented: $showingTimeRangePicker) { TimeRangePickerView(onSelect: onSelect) }
        .sheet(isPresented: $showingTimePicker) { SingleTimePickerView(onSelect: onSelect) }
        .sheet(isPresented: $showingWeekdayPicker) { WeekdayPickerView(onSelect: onSelect) }
        .sheet(isPresented: $showingDatePicker) { DatePickerView(onSelect: onSelect) }
        .sheet(isPresented: $showingNthWeekdayPicker) { NthWeekdayPickerView(onSelect: onSelect) }
    }
}

// MARK: - Location Condition Options

struct LocationConditionOptionsView: View {
    let onSelect: (AutomationCondition) -> Void
    @State private var showingMapPicker = false

    var body: some View {
        VStack(spacing: 12) {
            Button(action: { showingMapPicker = true }) {
                HStack {
                    Image(systemName: "map.fill")
                        .font(.system(size: 18))
                    Text(String.automationSelectLocation.localized)
                        .font(.headline)
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(.white)
                .cornerRadius(12)
            }
        }
        .fullScreenCover(isPresented: $showingMapPicker) {
            LocationPickerView(onSelect: onSelect)
        }
    }
}

// MARK: - Altitude Condition Options

struct AltitudeConditionOptionsView: View {
    let onSelect: (AutomationCondition) -> Void
    @State private var showingAltitudePicker = false

    private func option(_ condition: AutomationCondition) -> OptionRow {
        OptionRow(title: condition.displayText) { onSelect(condition) }
    }

    var body: some View {
        VStack(spacing: 12) {
            option(.altitudeAbove(2000))
            option(.altitudeBelow(500))
            OptionRow(title: String.automationAltitudeCustom.localized) { showingAltitudePicker = true }
        }
        .sheet(isPresented: $showingAltitudePicker) {
            AltitudePickerView(onSelect: onSelect)
        }
    }
}

// MARK: - Time Range Picker

struct TimeRangePickerView: View {
    let onSelect: (AutomationCondition) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var startHour = 9
    @State private var startMinute = 0
    @State private var endHour = 17
    @State private var endMinute = 0

    var body: some View {
        PickerSheetWrapper(
            title: String.automationSelectTime.localized,
            onConfirm: {
                onSelect(.timeInRange(startHour: startHour, startMinute: startMinute, endHour: endHour, endMinute: endMinute))
                dismiss()
            },
            onCancel: { dismiss() }
        ) {
            Form {
                Section(header: Text(String.automationStartTime.localized)) {
                    HStack {
                        Picker(String.automationHour.localized, selection: $startHour) { ForEach(0 ..< 24) { Text("\($0)").tag($0) } }.pickerStyle(.wheel)
                        Picker(String.automationMinute.localized, selection: $startMinute) { ForEach(0 ..< 60) { Text("\($0)").tag($0) } }.pickerStyle(.wheel)
                    }
                }
                Section(header: Text(String.automationEndTime.localized)) {
                    HStack {
                        Picker(String.automationHour.localized, selection: $endHour) { ForEach(0 ..< 24) { Text("\($0)").tag($0) } }.pickerStyle(.wheel)
                        Picker(String.automationMinute.localized, selection: $endMinute) { ForEach(0 ..< 60) { Text("\($0)").tag($0) } }.pickerStyle(.wheel)
                    }
                }
            }
        }
    }
}

// MARK: - Single Time Picker

struct SingleTimePickerView: View {
    let onSelect: (AutomationCondition) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var hour = 9
    @State private var minute = 0
    @State private var isAfter = true

    var body: some View {
        PickerSheetWrapper(
            title: String.automationSelectTime.localized,
            onConfirm: {
                onSelect(isAfter ? .timeAfter(hour: hour, minute: minute) : .timeBefore(hour: hour, minute: minute))
                dismiss()
            },
            onCancel: { dismiss() }
        ) {
            Form {
                Section(header: Text(String.automationTime.localized)) {
                    HStack {
                        Picker(String.automationHour.localized, selection: $hour) { ForEach(0 ..< 24) { Text("\($0)").tag($0) } }.pickerStyle(.wheel)
                        Picker(String.automationMinute.localized, selection: $minute) { ForEach(0 ..< 60) { Text("\($0)").tag($0) } }.pickerStyle(.wheel)
                    }
                }
                Section {
                    Picker(String.automationCondition.localized, selection: $isAfter) {
                        Text(String.automationConditionAfter.localized).tag(true)
                        Text(String.automationConditionBefore.localized).tag(false)
                    }.pickerStyle(.segmented)
                }
            }
        }
    }
}

// MARK: - Weekday Picker

struct WeekdayPickerView: View {
    let onSelect: (AutomationCondition) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedWeekdays: Set<Int> = []
    private var weekdays: [(Int, String)] { AutomationFormatters.weekdays }

    var body: some View {
        PickerSheetWrapper(
            title: String.automationSelectWeekday.localized,
            isConfirmDisabled: selectedWeekdays.isEmpty,
            onConfirm: {
                if selectedWeekdays.count == 1, let weekday = selectedWeekdays.first {
                    onSelect(.weekdayIs(weekday))
                } else if !selectedWeekdays.isEmpty {
                    onSelect(.weekdayIn(Array(selectedWeekdays).sorted()))
                }
                dismiss()
            },
            onCancel: { dismiss() }
        ) {
            List {
                ForEach(weekdays, id: \.0) { weekday in
                    Button(action: {
                        if selectedWeekdays.contains(weekday.0) { selectedWeekdays.remove(weekday.0) }
                        else { selectedWeekdays.insert(weekday.0) }
                    }) {
                        HStack {
                            Text(weekday.1).foregroundColor(.white)
                            Spacer()
                            if selectedWeekdays.contains(weekday.0) {
                                Image(systemName: "checkmark").foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Altitude Picker

struct AltitudePickerView: View {
    let onSelect: (AutomationCondition) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var altitude: String = "1000"
    @State private var conditionType = 0 // 0: above, 1: below

    var body: some View {
        PickerSheetWrapper(
            title: String.automationSelectAltitude.localized,
            isConfirmDisabled: altitude.isEmpty,
            onConfirm: {
                if let alt = Double(altitude) {
                    onSelect(conditionType == 0 ? .altitudeAbove(alt) : .altitudeBelow(alt))
                    dismiss()
                }
            },
            onCancel: { dismiss() }
        ) {
            Form {
                Section(header: Text(String.automationAltitudeMeters.localized)) {
                    TextField(String.automationAltitudeInputPlaceholder.localized, text: $altitude).keyboardType(.numberPad)
                }
                Section {
                    Picker(String.automationCondition.localized, selection: $conditionType) {
                        Text(String.automationConditionAltitudeAbove.localized).tag(0)
                        Text(String.automationConditionAltitudeBelow.localized).tag(1)
                    }.pickerStyle(.segmented)
                }
            }
        }
    }
}

// MARK: - Date Picker

struct DatePickerView: View {
    let onSelect: (AutomationCondition) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var month = 1
    @State private var day = 1
    private let months = Array(1 ... 12)

    var body: some View {
        PickerSheetWrapper(
            title: String.automationSelectDate.localized,
            onConfirm: {
                onSelect(.dateIs(month: month, day: day))
                dismiss()
            },
            onCancel: { dismiss() }
        ) {
            Form {
                Section(header: Text(String.automationSelectDate.localized)) {
                    HStack {
                        Picker(String.automationMonth.localized, selection: $month) {
                            ForEach(months, id: \.self) { m in Text("\(m)").tag(m) }
                        }.pickerStyle(.wheel)
                        Picker(String.automationDay.localized, selection: $day) {
                            ForEach(daysInMonth, id: \.self) { d in Text("\(d)").tag(d) }
                        }.pickerStyle(.wheel)
                    }
                }
            }
        }
    }

    private var daysInMonth: [Int] {
        let maxDays = AutomationFormatters.daysInMonth(month)
        if day > maxDays { DispatchQueue.main.async { day = maxDays } }
        return Array(1 ... maxDays)
    }
}

// MARK: - Nth Weekday Picker

struct NthWeekdayPickerView: View {
    let onSelect: (AutomationCondition) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var month = 1
    @State private var weekday = 2
    @State private var nth = 1
    private let months = Array(1 ... 12)
    private let nthOptions = Array(1 ... 5)
    private var weekdays: [(Int, String)] { AutomationFormatters.weekdays }

    var body: some View {
        PickerSheetWrapper(
            title: String.automationDateRule.localized,
            onConfirm: {
                onSelect(.nthWeekdayOfMonth(month: month, weekday: weekday, nth: nth))
                dismiss()
            },
            onCancel: { dismiss() }
        ) {
            Form {
                Section(header: Text(String.automationDateRule.localized)) {
                    Picker(String.automationMonth.localized, selection: $month) {
                        ForEach(months, id: \.self) { m in Text("\(m)").tag(m) }
                    }
                    Picker(String.automationNth.localized, selection: $nth) {
                        ForEach(nthOptions, id: \.self) { n in Text("\(n)").tag(n) }
                    }
                    Picker(String.automationWeekday.localized, selection: $weekday) {
                        ForEach(weekdays, id: \.0) { wd in Text(wd.1).tag(wd.0) }
                    }
                }
            }
        }
    }
}

// MARK: - White Balance Action Options

struct WhiteBalanceActionOptionsView: View {
    let onSelect: (AutomationAction) -> Void
    @State private var showingCustomPicker = false

    private func option(_ action: AutomationAction) -> OptionRow {
        OptionRow(title: action.displayText) { onSelect(action) }
    }

    var body: some View {
        VStack(spacing: 12) {
            Group {
                SectionHeader(title: String.automationWhiteBalancePresets.localized)
                option(.setWhiteBalanceTemperature(5500))
                option(.setWhiteBalanceTemperature(6500))
                option(.setWhiteBalanceTemperature(3200))
            }

            Group {
                SectionHeader(title: String.automationWhiteBalanceAdjustments.localized)
                option(.adjustWhiteBalanceTemperature(500))
                option(.adjustWhiteBalanceTemperature(-500))
            }

            Group {
                SectionHeader(title: String.commonCustom.localized)
                OptionRow(title: String.commonCustom.localized) { showingCustomPicker = true }
            }
        }
        .sheet(isPresented: $showingCustomPicker) { WhiteBalanceCustomPickerView(onSelect: onSelect) }
    }
}

// MARK: - White Balance Custom Picker

struct WhiteBalanceCustomPickerView: View {
    let onSelect: (AutomationAction) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var temperature: Float = 5500
    @State private var tint: Float = 0

    var body: some View {
        PickerSheetWrapper(
            title: String.automationWhiteBalanceTitle.localized,
            onConfirm: {
                onSelect(.setWhiteBalance(temperature: temperature, tint: tint))
                dismiss()
            },
            onCancel: { dismiss() }
        ) {
            Form {
                Section(header: Text(String.automationColorTemperatureRange.localized)) {
                    HStack {
                        Text("\(Int(temperature))K").frame(width: 80, alignment: .leading)
                        Slider(value: $temperature, in: 2000 ... 8000, step: 100)
                    }
                }
                Section(header: Text(String.automationTintRange.localized)) {
                    HStack {
                        Text("\(Int(tint))").frame(width: 80, alignment: .leading)
                        Slider(value: $tint, in: -150 ... 150, step: 5)
                    }
                }
            }
        }
    }
}

// MARK: - ISO Action Options

struct ISOActionOptionsView: View {
    let onSelect: (AutomationAction) -> Void
    @State private var showingCustomPicker = false

    private func option(_ action: AutomationAction) -> OptionRow {
        OptionRow(title: action.displayText) { onSelect(action) }
    }

    var body: some View {
        VStack(spacing: 12) {
            Group {
                SectionHeader(title: String.automationIsoCommon.localized)
                option(.setISO(100))
                option(.setISO(400))
                option(.setISO(1600))
            }

            Group {
                SectionHeader(title: String.automationIsoAdjustments.localized)
                option(.adjustISO(100))
                option(.adjustISO(-100))
            }

            Group {
                SectionHeader(title: String.commonCustom.localized)
                OptionRow(title: String.commonCustom.localized) { showingCustomPicker = true }
            }
        }
        .sheet(isPresented: $showingCustomPicker) { ISOCustomPickerView(onSelect: onSelect) }
    }
}

// MARK: - ISO Custom Picker

struct ISOCustomPickerView: View {
    let onSelect: (AutomationAction) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var iso: String = "400"
    @State private var isAdjust = false

    var body: some View {
        PickerSheetWrapper(
            title: isAdjust ? String.actionAdjustIso.localized : String.actionSetIso.localized,
            isConfirmDisabled: iso.isEmpty,
            onConfirm: {
                if let isoValue = Int(iso) {
                    onSelect(isAdjust ? .adjustISO(isoValue) : .setISO(isoValue))
                    dismiss()
                }
            },
            onCancel: { dismiss() }
        ) {
            Form {
                Section {
                    Picker(String.automationMode.localized, selection: $isAdjust) {
                        Text(String.automationIsoModeSet.localized).tag(false)
                        Text(String.automationIsoModeAdjust.localized).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: isAdjust) { _, newValue in
                        if newValue {
                            iso = "100"
                        } else {
                            iso = "400"
                        }
                    }
                }
                Section(header: Text(String.automationIsoValue.localized)) {
                    TextField(isAdjust ? String.automationIsoInputAdjust.localized : String.automationIsoInputSet.localized, text: $iso)
                        .keyboardType(isAdjust ? .numbersAndPunctuation : .numberPad)
                }
                Section(header: Text(String.automationHint.localized)) {
                    Text(isAdjust ? String.automationPositiveIncreaseNegativeDecrease.localized : String.automationIsoTypicalValues.localized)
                        .font(.caption).foregroundColor(.gray)
                }
            }
        }
    }
}

// MARK: - Shutter Speed Action Options

struct ShutterSpeedActionOptionsView: View {
    let onSelect: (AutomationAction) -> Void
    @State private var showingFractionPicker = false

    private func option(_ action: AutomationAction) -> OptionRow {
        OptionRow(title: action.displayText) { onSelect(action) }
    }

    var body: some View {
        VStack(spacing: 12) {
            Group {
                SectionHeader(title: String.automationShutterCommon.localized)
                option(.setShutterSpeedFraction(numerator: 1, denominator: 1000))
                option(.setShutterSpeedFraction(numerator: 1, denominator: 125))
                option(.setShutterSpeedFraction(numerator: 1, denominator: 30))
            }

            Group {
                SectionHeader(title: String.commonCustom.localized)
                OptionRow(title: String.commonCustom.localized) { showingFractionPicker = true }
            }
        }
        .sheet(isPresented: $showingFractionPicker) { ShutterSpeedFractionPickerView(onSelect: onSelect) }
    }
}

// MARK: - Shutter Speed Fraction Picker

struct ShutterSpeedFractionPickerView: View {
    let onSelect: (AutomationAction) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var numerator = 1
    @State private var denominator = 125

    var body: some View {
        PickerSheetWrapper(
            title: String.automationShutterTitle.localized,
            onConfirm: {
                onSelect(.setShutterSpeedFraction(numerator: numerator, denominator: denominator))
                dismiss()
            },
            onCancel: { dismiss() }
        ) {
            Form {
                Section(header: Text(String.automationShutterSpeed.localized)) {
                    HStack {
                        Picker(String.automationNumerator.localized, selection: $numerator) {
                            ForEach(1 ... 10, id: \.self) { n in Text("\(n)").tag(n) }
                        }.pickerStyle(.wheel).frame(width: 80)
                        Text("/").font(.title)
                        Picker(String.automationDenominator.localized, selection: $denominator) {
                            ForEach(AutomationFormatters.shutterDenominators, id: \.self) { d in Text("\(d)").tag(d) }
                        }.pickerStyle(.wheel)
                    }
                }
            }
        }
    }
}

// MARK: - Filter Action Options

struct FilterActionOptionsView: View {
    let onSelect: (AutomationAction) -> Void
    @State private var showingURLImportPicker = false
    @ObservedObject private var customFilterManager = CustomFilterManager.shared

    private func option(_ action: AutomationAction) -> OptionRow {
        OptionRow(title: action.displayText) { onSelect(action) }
    }

    var body: some View {
        VStack(spacing: 12) {
            Group {
                SectionHeader(title: String.automationFilterImportFromUrl.localized)
                OptionRow(title: String.automationFilterImportUrl.localized) { showingURLImportPicker = true }
            }

            Group {
                SectionHeader(title: String.automationFilterBuiltin.localized)
                ForEach(BuiltinFilterRegistry.shared.allNames, id: \.self) { filterName in
                    option(.setFilter(.builtin(filterName)))
                }
            }

            if !customFilterManager.customFilters.isEmpty {
                Group {
                    SectionHeader(title: String.automationFilterCustomFilters.localized)
                    ForEach(customFilterManager.customFilters) { filter in
                        option(.setFilter(.custom(filter.name)))
                    }
                }
            }
        }
        .sheet(isPresented: $showingURLImportPicker) {
            FilterURLImportPickerView(onSelect: onSelect)
        }
    }
}

// MARK: - Filter URL Import Picker

struct FilterURLImportPickerView: View {
    let onSelect: (AutomationAction) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var urlString: String = ""
    @State private var displayName: String = ""

    var body: some View {
        PickerSheetWrapper(
            title: String.automationImportFilter.localized,
            isConfirmDisabled: urlString.isEmpty,
            onConfirm: {
                let name: String? = displayName.isEmpty ? nil : displayName
                onSelect(.importFilterFromURL(url: urlString, displayName: name))
                dismiss()
            },
            onCancel: { dismiss() }
        ) {
            Form {
                Section(header: Text(String.automationFilterUrlTitle.localized)) {
                    TextField(String.filterImportUrlPlaceholder.localized, text: $urlString)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                Section(header: Text(String.automationFilterCustomName.localized)) {
                    TextField(String.automationFilterCustomNamePlaceholder.localized, text: $displayName)
                }
                Section(header: Text(String.automationFilterUrlMessage.localized)) {
                    Text(String.filterImportUrlMessage.localized)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
        }
    }
}

// MARK: - Color Condition Options

struct ColorConditionOptionsView: View {
    let onSelect: (AutomationCondition) -> Void

    private func option(_ condition: AutomationCondition) -> OptionRow {
        OptionRow(title: condition.displayText) { onSelect(condition) }
    }

    var body: some View {
        VStack(spacing: 12) {
            Group {
                SectionHeader(title: String.automationColorTemperature.localized)
                option(.colorTemperatureIs(.warm))
                option(.colorTemperatureIs(.cool))
            }

            Group {
                SectionHeader(title: String.automationColorSaturation.localized)
                option(.colorSaturationAbove(0.7))
                option(.colorSaturationBelow(0.3))
            }

            Group {
                SectionHeader(title: String.automationColorBrightness.localized)
                option(.colorBrightnessAbove(0.7))
                option(.colorBrightnessBelow(0.3))
            }
        }
    }
}

// MARK: - Toast Action Options

struct ToastActionOptionsView: View {
    let onSelect: (AutomationAction) -> Void
    @State private var showingCustomPicker = false

    private func option(_ action: AutomationAction) -> OptionRow {
        OptionRow(title: action.displayText) { onSelect(action) }
    }

    var body: some View {
        VStack(spacing: 12) {
            Group {
                SectionHeader(title: String.automationToastCommon.localized)
                option(.showToast(type: .success, message: String.automationToastSuccessCompleteMessage.localized))
                option(.showToast(type: .warning, message: String.automationToastWarningLightMessage.localized))
                option(.showToast(type: .info, message: String.automationToastInfoCompositionMessage.localized))
            }

            Group {
                SectionHeader(title: String.commonCustom.localized)
                OptionRow(title: String.automationToastCustomMessage.localized) { showingCustomPicker = true }
            }
        }
        .sheet(isPresented: $showingCustomPicker) { ToastCustomPickerView(onSelect: onSelect) }
    }
}

// MARK: - Toast Custom Picker

struct ToastCustomPickerView: View {
    let onSelect: (AutomationAction) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var message: String = ""
    @State private var toastType: ToastType = .info
    @State private var duration: Double = 2.0

    private let toastTypes = AutomationFormatters.toastTypeOptions
    /// Optional durations: 1s to 5s, step 1s
    private let durationOptions: [Double] = [1.0, 2.0, 3.0, 4.0, 5.0]

    var body: some View {
        PickerSheetWrapper(
            title: String.automationToastCustomTitle.localized,
            isConfirmDisabled: message.isEmpty,
            onConfirm: {
                onSelect(.showToast(type: toastType, message: message, duration: duration))
                dismiss()
            },
            onCancel: { dismiss() }
        ) {
            Form {
                Section(header: Text(String.automationToastType.localized)) {
                    Picker(String.automationToastType.localized, selection: $toastType) {
                        ForEach(toastTypes, id: \.0) { type in Text(type.1).tag(type.0) }
                    }.pickerStyle(.segmented)
                }
                Section(header: Text(String.automationToastMessageContent.localized)) {
                    TextField(String.automationToastInputPlaceholder.localized, text: $message)
                }
                Section(header: Text(String.automationToastDuration.localized)) {
                    Picker(String.automationToastDuration.localized, selection: $duration) {
                        ForEach(durationOptions, id: \.self) { value in
                            Text("\(AutomationFormatters.trimNumber(value))s").tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 120)
                }
            }
        }
    }
}

private extension AutomationCondition {
    var displayText: String {
        detailText.isEmpty ? titleText : "\(titleText) \(detailText)"
    }
}

private extension AutomationAction {
    var displayText: String {
        detailText.isEmpty ? titleText : "\(titleText) \(detailText)"
    }
}
