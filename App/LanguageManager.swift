import Foundation
import SwiftUI

enum AppLanguage: String {
    case ru, en
}

final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "appLanguage") }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "appLanguage") ?? "ru"
        self.language = AppLanguage(rawValue: saved) ?? .ru
    }

    /// Returns the Russian or English string depending on current language.
    func t(_ ru: String, _ en: String) -> String {
        language == .en ? en : ru
    }

    func toggle() {
        language = language == .ru ? .en : .ru
    }
}
