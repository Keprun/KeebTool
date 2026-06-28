import SwiftUI

/// Supported UI languages.
enum Lang: String, CaseIterable, Identifiable {
    case en, ru, zh, fa, de, fr, it
    var id: String { rawValue }

    var native: String {
        switch self {
        case .en: return "English"
        case .ru: return "Русский"
        case .zh: return "中文"
        case .fa: return "فارسی"
        case .de: return "Deutsch"
        case .fr: return "Français"
        case .it: return "Italiano"
        }
    }

    var english: String {
        switch self {
        case .en: return "English"
        case .ru: return "Russian"
        case .zh: return "Chinese"
        case .fa: return "Persian"
        case .de: return "German"
        case .fr: return "French"
        case .it: return "Italian"
        }
    }

    var flag: String {
        switch self {
        case .en: return "🇬🇧"
        case .ru: return "🇷🇺"
        case .zh: return "🇨🇳"
        case .fa: return "🇮🇷"
        case .de: return "🇩🇪"
        case .fr: return "🇫🇷"
        case .it: return "🇮🇹"
        }
    }
}

/// Runtime localization: holds the chosen language and looks strings up in the generated table.
/// Changing `lang` republishes, so SwiftUI views (which read `loc.t(...)` in their body) re-render live.
@MainActor
final class Loc: ObservableObject {
    static let shared = Loc()

    @Published var lang: Lang {
        didSet { UserDefaults.standard.set(lang.rawValue, forKey: "uiLang") }
    }

    init() {
        if let s = UserDefaults.standard.string(forKey: "uiLang"), let l = Lang(rawValue: s) {
            lang = l
        } else {
            let sys = String(Locale.preferredLanguages.first?.prefix(2) ?? "en")
            lang = Lang(rawValue: sys) ?? .en
        }
    }

    /// Localized string for `key`, falling back to English then the raw key.
    func t(_ key: String) -> String {
        LOC_TABLE[key]?[lang.rawValue] ?? LOC_TABLE[key]?["en"] ?? key
    }

    /// Localized + formatted (templates use %@ / %d).
    func tf(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), arguments: args)
    }

    /// Persian renders right-to-left.
    var layout: LayoutDirection { lang == .fa ? .rightToLeft : .leftToRight }
}
