import Foundation

func L(_ key: String) -> String {
    let locale = ConfigStore.shared.config.appLanguage.resolvedLocale
    let langCode = locale.language.languageCode?.identifier ?? "en"
    if let path = Bundle.main.path(forResource: langCode, ofType: "lproj"),
       let bundle = Bundle(path: path) {
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }
    return Bundle.main.localizedString(forKey: key, value: key, table: "Localizable")
}

func LMD(_ key: String) -> AttributedString {
    let str = L(key)
    return (try? AttributedString(markdown: str, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(str)
}
