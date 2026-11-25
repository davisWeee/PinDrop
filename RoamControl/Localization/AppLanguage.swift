import Foundation
import Observation
import SwiftUI

/// Languages PinDrop ships translations for. `.system` follows the device setting.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case arabic = "ar"
    case french = "fr"
    case german = "de"
    case hebrew = "he"
    case japanese = "ja"
    case simplifiedChinese = "zh-Hans"
    case spanish = "es"
    case traditionalChinese = "zh-Hant"
    case vietnamese = "vi"

    var id: Self { self }

    /// Endonym, deliberately NOT localized so users can always find their own language.
    var nativeName: String? {
        switch self {
        case .system: nil
        case .english: "English"
        case .arabic: "العربية"
        case .french: "Français"
        case .german: "Deutsch"
        case .hebrew: "עברית"
        case .japanese: "日本語"
        case .simplifiedChinese: "简体中文"
        case .spanish: "Español"
        case .traditionalChinese: "繁體中文"
        case .vietnamese: "Tiếng Việt"
        }
    }
}

/// App-wide language selection with immediate effect (no relaunch):
/// - SwiftUI `Text("literal")` is localized through `\.locale` set at the app root,
/// - layout direction (RTL for Arabic / Hebrew) through `\.layoutDirection`,
/// - code-built strings through `L10n.tr(_:)`, which reads the chosen `.lproj` bundle.
/// The choice is also written to `AppleLanguages` so system dialogs follow on next launch.
@MainActor
@Observable
final class LanguageSettings {
    static let shared = LanguageSettings()

    private static let storageKey = "appLanguage"

    private(set) var selection: AppLanguage

    private init() {
        // First launch defaults to Simplified Chinese; the Settings picker can switch to any language or System.
        let raw = UserDefaults.standard.string(forKey: Self.storageKey) ?? AppLanguage.simplifiedChinese.rawValue
        selection = AppLanguage(rawValue: raw) ?? .simplifiedChinese
    }

    func select(_ language: AppLanguage) {
        selection = language
        UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey)
        if language == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        }
    }

    /// Language code actually in effect (resolves `.system` against the bundle's localizations).
    var effectiveCode: String {
        if selection != .system { return selection.rawValue }
        return Bundle.main.preferredLocalizations.first ?? "en"
    }

    var locale: Locale {
        selection == .system ? .autoupdatingCurrent : Locale(identifier: selection.rawValue)
    }

    var layoutDirection: LayoutDirection {
        Locale.Language(identifier: effectiveCode).characterDirection == .rightToLeft
            ? .rightToLeft
            : .leftToRight
    }

    var bundle: Bundle {
        guard
            selection != .system,
            let path = Bundle.main.path(forResource: selection.rawValue, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else { return .main }
        return bundle
    }
}

/// Localization for strings built in code (errors, names, status text).
/// Reading `LanguageSettings.shared.selection` inside a view body makes that view refresh on language change.
enum L10n {
    /// For literals / interpolations: `L10n.tr("Resume \(name)")` -> catalog key "Resume %@".
    @MainActor
    static func tr(_ value: String.LocalizationValue) -> String {
        let settings = LanguageSettings.shared
        _ = settings.selection
        return String(localized: value, bundle: settings.bundle, locale: settings.locale)
    }

    /// For English message strings produced by non-UI layers (they double as lookup keys).
    /// Returns the text unchanged when no translation exists (e.g. messages with embedded values).
    @MainActor
    static func lookup(_ message: String) -> String {
        let settings = LanguageSettings.shared
        _ = settings.selection
        let translated = settings.bundle.localizedString(forKey: message, value: message, table: nil)
        if translated != message { return translated }
        // Messages with one embedded integer (e.g. "(Keychain error -34018)") are catalogued with %lld.
        if let range = message.range(of: #"-?\d+"#, options: .regularExpression) {
            let template = message.replacingCharacters(in: range, with: "%lld")
            let localizedTemplate = settings.bundle.localizedString(forKey: template, value: template, table: nil)
            if localizedTemplate != template {
                return localizedTemplate.replacingOccurrences(of: "%lld", with: String(message[range]))
            }
        }
        return message
    }
}

extension String {
    /// Localizes an English message created outside the view layer.
    @MainActor
    var localizedMessage: String { L10n.lookup(self) }
}
