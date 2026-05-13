import Foundation
import SwiftUI

enum Language: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case chinese = "zh-Hans"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            return String.localizedStringWithFormat(NSLocalizedString("system_default", comment: "System Default"))
        case .english: return "English"
        case .chinese: return "简体中文"
        }
    }

    var webLanguageCode: String {
        switch self {
        case .chinese: return "zh"
        case .english: return "en"
        case .system:
            let code = Locale.current.language.languageCode?.identifier ?? "en"
            return code == "zh" ? "zh" : "en"
        }
    }

    var isChinese: Bool {
        switch self {
        case .chinese: return true
        case .english: return false
        case .system:
            return Locale.current.language.languageCode?.identifier == "zh"
        }
    }
}

final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    @Published var currentLanguage: Language {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: "selectedLanguage")
            updateBundle()
        }
    }

    /// ID used to force-refresh the view
    @Published var uuid = UUID()

    var bundle: Bundle = .main

    var locale: Locale {
        if currentLanguage == .system {
            return .current
        } else {
            return Locale(identifier: currentLanguage.rawValue)
        }
    }

    private init() {
        if let savedLanguage = UserDefaults.standard.string(forKey: "selectedLanguage"),
           let language = Language(rawValue: savedLanguage)
        {
            currentLanguage = language
        } else {
            currentLanguage = .system
        }
        updateBundle()
    }

    private func updateBundle() {
        if currentLanguage == .system {
            bundle = .main
        } else {
            if let path = Bundle.main.path(forResource: currentLanguage.rawValue, ofType: "lproj"),
               let bundle = Bundle(path: path)
            {
                self.bundle = bundle
            } else {
                bundle = .main
            }
        }
        // update uuid triggerviewupdate
        uuid = UUID()
    }

    func setLanguage(_ language: Language) {
        currentLanguage = language
    }
}
