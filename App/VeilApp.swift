import SwiftUI
import AppKit

// MARK: - Entry point
// Requires macOS 13+. Set LSUIElement = YES in Info.plist to hide Dock icon.

@main
struct VeilApp: App {
    @StateObject private var vpn  = VPNManager()
    @StateObject private var lang = LanguageManager.shared

    var body: some Scene {
        // MenuBarExtra gives a native status-bar popover window (like v2Box)
        MenuBarExtra {
            ContentView()
                .environmentObject(vpn)
                .environmentObject(lang)
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
        case .connected:    return .green
        case .error:        return .red
        }
    }
}
