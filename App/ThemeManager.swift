import SwiftUI
import AppKit

enum AppTheme: String, CaseIterable {
    case system, light, dark

    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }
}

final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: "appTheme")
            applyTheme()
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "appTheme") ?? "system"
        self.theme = AppTheme(rawValue: saved) ?? .system
        applyTheme()
    }

    func applyTheme() {
        NSApp?.appearance = theme.appearance
    }
}
