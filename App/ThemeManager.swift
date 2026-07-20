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

    /// The same choice expressed for SwiftUI.
    ///
    /// Setting only `NSApp.appearance` leaves the SwiftUI hierarchy without a
    /// scheme of its own, so dynamic AppKit colours such as
    /// `NSColor.textBackgroundColor` have no appearance to resolve against on a
    /// view's first frame and briefly paint their default (dark) value. Handing
    /// the scheme to SwiftUI as well removes that race.
    ///
    /// `nil` means "follow the system", which is what `.system` should do.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
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
