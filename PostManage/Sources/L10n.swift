import Foundation

enum L10n {
    static var selectedLanguage: String {
        UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
    }

    static func string(_ key: String, language: String, bundle: Bundle = .main) -> String {
        guard let path = bundle.path(forResource: language, ofType: "lproj"),
              let localizedBundle = Bundle(path: path) else { return key }
        return localizedBundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, language: String, _ arguments: CVarArg...,
                       bundle: Bundle = .main) -> String {
        String(format: string(key, language: language, bundle: bundle),
               locale: Locale(identifier: language), arguments: arguments)
    }
}
