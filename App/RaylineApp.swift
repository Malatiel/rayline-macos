import SwiftUI
import AppKit

private let menuBarConnectedAccent = connectedAccent

// MARK: - Entry point
// Requires macOS 13+. Set LSUIElement = YES in Info.plist to hide Dock icon.

@main
struct RaylineApp: App {
    @StateObject private var vpn            = VPNManager()
    @StateObject private var profileManager = ProfileManager()
    @StateObject private var subscriptionManager = SubscriptionManager()
    @StateObject private var toastManager   = ToastManager()
    @StateObject private var loginItem      = LoginItemManager()
    @ObservedObject private var lang  = LanguageManager.shared
    @ObservedObject private var theme = ThemeManager.shared

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(vpn)
                .environmentObject(lang)
                .environmentObject(profileManager)
                .environmentObject(subscriptionManager)
                .environmentObject(toastManager)
                .environmentObject(loginItem)
                // Give SwiftUI the scheme directly. NSApp.appearance alone only
                // reaches these views by inheritance, which lands too late for
                // the first frame of a screen that was just rebuilt.
                .preferredColorScheme(theme.theme.colorScheme)
                .onAppear {
                    // NSApp may not have existed when ThemeManager initialised,
                    // in which case its appearance was never actually set.
                    theme.applyTheme()
                    vpn.autoConnectOnLaunchIfNeeded(activeProfile: profileManager.activeProfile)
                    // The user can flip this in System Settings while the app
                    // runs, so re-read it rather than trusting the cached value.
                    loginItem.refresh()
                    subscriptionManager.startAutoRefresh(profileManager: profileManager)
                }
        } label: {
            StatusBarLabel(state: vpn.state)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Menu-bar icon

private struct StatusBarLabel: View {
    let state: VPNManager.State

    var body: some View {
        Image(systemName: iconName)
            .imageScale(.medium)
            .foregroundColor(color)
            .symbolRenderingMode(.hierarchical)
    }

    private var iconName: String {
        switch state {
        case .disconnected: return "shield"
        case .connecting:   return "shield.lefthalf.filled"
        case .disconnecting: return "shield.lefthalf.filled"
        case .connected:    return "shield.fill"
        case .error:        return "shield.slash"
        }
    }

    private var color: Color {
        switch state {
        case .disconnected: return .primary
        case .connecting:   return .orange
        case .disconnecting: return .orange
        case .connected:    return menuBarConnectedAccent
        case .error:        return .red
        }
    }
}
