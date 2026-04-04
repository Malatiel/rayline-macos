import SwiftUI
import AppKit

private let menuBarConnectedAccent = Color(
    red: 0x38 / 255,
    green: 0xE0 / 255,
    blue: 0xA0 / 255
)

// MARK: - Entry point
// Requires macOS 13+. Set LSUIElement = YES in Info.plist to hide Dock icon.

@main
struct VeilApp: App {
    @StateObject private var vpn            = VPNManager()
    @StateObject private var profileManager = ProfileManager()
    @StateObject private var toastManager   = ToastManager()
    @ObservedObject private var lang  = LanguageManager.shared
    @ObservedObject private var theme = ThemeManager.shared

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(vpn)
                .environmentObject(lang)
                .environmentObject(profileManager)
                .environmentObject(toastManager)
                .onAppear {
                    vpn.autoConnectOnLaunchIfNeeded(activeProfile: profileManager.activeProfile)
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
        case .connected:    return "shield.fill"
        case .error:        return "shield.slash"
        }
    }

    private var color: Color {
        switch state {
        case .disconnected: return .primary
        case .connecting:   return .orange
        case .connected:    return menuBarConnectedAccent
        case .error:        return .red
        }
    }
}
