import SwiftUI
import AppKit

let connectedAccent = Color(
    red: 0x38 / 255,
    green: 0xE0 / 255,
    blue: 0xA0 / 255
)

private enum AppSection: String, CaseIterable, Hashable {
    case status
    case profiles
    case log
    case settings
}

enum LogFilter: String, CaseIterable {
    case all
    case error
    case warning
    case info
}

// MARK: - Sidebar UI

private struct SidebarItemLabel: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Main window

struct ContentView: View {
    @EnvironmentObject var vpn: VPNManager
    @EnvironmentObject var lang: LanguageManager
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var toastManager: ToastManager

    @State private var selectedSection: AppSection = .status
    @State private var urlText = ""
    @State private var parseInfo = ""
    @State private var parseOK = false
    @State private var connectPressed = false
    @State private var isImportExpanded = false
    @State private var renamingProfileId: UUID?
    @State private var renameText = ""
    @State private var profileNameText = ""
    @State private var shimmerPhase: CGFloat = 0
    @State private var logSearchText = ""
    @State private var logFilter: LogFilter = .all
    @State private var previousVpnState: VPNManager.State = .disconnected

    private var trimmed: String { urlText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var draftConfig: ProxyConfig? { try? ProxyParser.parse(trimmed) }
    private var displayConfig: ProxyConfig? { vpn.config ?? profileManager.activeProfile ?? draftConfig }
    private var hasLaunchInput: Bool { profileManager.activeProfile != nil || !trimmed.isEmpty }
    private var statusSummary: StatusSummary {
        StatusSummary(
            state: vpn.state,
            displayConfig: displayConfig,
            hasLaunchInput: hasLaunchInput,
            pingMs: vpn.pingMs,
            packetsSent: vpn.packetsSent,
            packetsRecv: vpn.packetsRecv,
            language: lang.language
        )
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailContent
        }
        .frame(minWidth: 860, idealWidth: 920, minHeight: 560, idealHeight: 620)
        .animation(.easeInOut(duration: 0.22), value: selectedSection)
        .animation(.easeInOut(duration: 0.22), value: vpn.state)
        .onAppear {
            if !trimmed.isEmpty {
                isImportExpanded = true
            }
            previousVpnState = vpn.state
        }
        .onChange(of: vpn.state) { newState in
            handleStateToast(newState)
            previousVpnState = newState
        }
        .onChange(of: profileManager.lastError) { error in
            if let error {
                toastManager.show(error, style: .error)
            }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedSection) {
                navigationRow(
                    section: .status,
                    title: lang.t("Статус", "Status"),
                    subtitle: statusSummary.stateLabel,
                    icon: "waveform.path.ecg",
                    tint: stateColor
                )

                navigationRow(
                    section: .profiles,
                    title: lang.t("Профили", "Profiles"),
                    subtitle: displayConfig?.name ?? lang.t("Импорт и выбор", "Import and review"),
                    icon: "square.stack.3d.up",
                    tint: .secondary
                )

                navigationRow(
                    section: .log,
                    title: lang.t("Лог", "Log"),
                    subtitle: vpn.logs.isEmpty
                        ? lang.t("Пусто", "Empty")
                        : "\(vpn.logs.count)",
                    icon: "terminal",
                    tint: .secondary
                )

                navigationRow(
                    section: .settings,
                    title: lang.t("Настройки", "Settings"),
                    subtitle: lang.t("Прокси и система", "Proxy and system"),
                    icon: "gearshape",
                    tint: .secondary
                )
            }
            .listStyle(.sidebar)

            Divider()

            compactConnectionStatus
                .padding(14)
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 280)
    }

    private func navigationRow(
        section: AppSection,
        title: String,
        subtitle: String,
        icon: String,
        tint: Color
    ) -> some View {
        SidebarItemLabel(title: title, subtitle: subtitle, icon: icon, tint: tint)
            .tag(section)
    }

    private var compactConnectionStatus: some View {
        HStack(spacing: 10) {
            PulsingDot(
                color: stateColor,
                isActive: statusSummary.isConnectionActivityActive
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(statusSummary.stateLabel)
                    .font(.system(size: 12, weight: .semibold))
                Text(statusSummary.profileSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: Detail

    @ViewBuilder
    private var detailContent: some View {
        VStack(spacing: 0) {
            detailHeader
            Divider()

            ZStack(alignment: .top) {
                Group {
                    switch selectedSection {
                    case .status:
                        StatusScreen(
                            displayConfig: displayConfig,
                            hasLaunchInput: hasLaunchInput,
                            connectPressed: $connectPressed,
                            shimmerPhase: $shimmerPhase,
                            toggleConnection: toggleConnection,
                            chooseSingBoxBinary: chooseSingBoxBinary
                        )
                    case .profiles:
                        ProfilesScreen(
                            urlText: $urlText,
                            parseInfo: $parseInfo,
                            parseOK: $parseOK,
                            isImportExpanded: $isImportExpanded,
                            renamingProfileId: $renamingProfileId,
                            renameText: $renameText,
                            profileNameText: $profileNameText,
                            displayConfig: displayConfig,
                            checkURL: checkURL,
                            saveProfile: saveProfile,
                            pasteFromClipboard: pasteFromClipboard,
                            openStatus: { selectedSection = .status }
                        )
                    case .log:
                        LogScreen(logSearchText: $logSearchText, logFilter: $logFilter)
                    case .settings:
                        SettingsScreen(chooseSingBoxBinary: chooseSingBoxBinary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                toastOverlay
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(NSColor.windowBackgroundColor),
                        Color.primary.opacity(0.018)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast = toastManager.currentToast {
            HStack(spacing: 8) {
                Image(systemName: toastIcon(toast.style))
                Text(toast.message)
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(toastColor(toast.style).opacity(0.15), in: Capsule())
            .overlay(Capsule().stroke(toastColor(toast.style).opacity(0.3), lineWidth: 1))
            .foregroundStyle(toastColor(toast.style))
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.25), value: toastManager.currentToast?.id)
        }
    }

    private var detailHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Veil")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text(sectionTitle(selectedSection))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                lang.toggle()
            } label: {
                Text(lang.language == .ru ? "EN" : "RU")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .help(lang.t("Переключить язык", "Switch language"))

            Button {
                Task {
                    if vpn.state.isConnected || vpn.state.isConnecting || vpn.state.isDisconnecting {
                        await vpn.disconnectAndWait()
                    }
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(lang.t("Выйти из приложения", "Quit application"))
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(.bar)
    }

    // MARK: Actions

    private func checkURL() {
        let url = trimmed

        do {
            let cfg = try ProxyParser.parse(url)
            if cfg.isValid {
                parseInfo = "✅ \(cfg.protoName) · \(cfg.server):\(cfg.port)"
                    + (cfg.security.isEmpty || cfg.security == "none" ? "" : " · \(cfg.security.uppercased())")
                    + (cfg.sni.isEmpty ? "" : " · SNI: \(cfg.sni)")
                    + (cfg.name.isEmpty || cfg.name == cfg.server
                        ? ""
                        : "\n\(lang.t("Профиль", "Profile")): \(cfg.name)")
                parseOK = true
            } else {
                parseInfo = "❌ \(lang.t("Ссылка не содержит сервер или порт", "Link has no server or port"))"
                parseOK = false
            }
        } catch {
            parseInfo = "❌ \(error.localizedDescription)"
            parseOK = false
        }
    }

    private func connectVPN() {
        if let profile = profileManager.activeProfile {
            vpn.connect(config: profile)
        } else if !trimmed.isEmpty {
            vpn.connect(urlString: trimmed)
        }
    }

    private func chooseSingBoxBinary() {
        let panel = NSOpenPanel()
        panel.title = lang.t("Выберите sing-box", "Choose sing-box")
        panel.message = lang.t(
            "Выберите исполняемый файл sing-box на этом Mac.",
            "Choose the sing-box executable on this Mac."
        )
        panel.prompt = lang.t("Выбрать", "Choose")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true

        if panel.runModal() == .OK, let url = panel.url {
            vpn.setCustomSingBoxPath(url.path)
        }
    }

    private func toggleConnection() {
        connectPressed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            connectPressed = false
        }

        if vpn.state.isConnected || vpn.state.isConnecting || vpn.state.isDisconnecting {
            vpn.disconnect()
        } else {
            connectVPN()
        }
    }

    private func saveProfile() {
        guard var cfg = draftConfig, cfg.isValid else { return }
        let customName = profileNameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !customName.isEmpty {
            cfg.name = customName
        }
        profileManager.addProfile(cfg)
        urlText = ""
        profileNameText = ""
        parseInfo = ""
        parseOK = false
        isImportExpanded = false
        toastManager.show(lang.t("Профиль сохранён", "Profile saved"), style: .success)
    }

    private func handleStateToast(_ newState: VPNManager.State) {
        switch newState {
        case .connected:
            toastManager.show(lang.t("Подключено", "Connected"), style: .success)
        case .disconnected where previousVpnState.isConnected || previousVpnState == .disconnecting:
            toastManager.show(lang.t("Отключено", "Disconnected"), style: .info)
        case .error(let msg):
            toastManager.show(msg, style: .error)
        default: break
        }
    }

    private func toastIcon(_ style: ToastManager.Toast.Style) -> String {
        switch style {
        case .success: return "checkmark.circle.fill"
        case .error:   return "xmark.circle.fill"
        case .info:    return "info.circle.fill"
        }
    }

    private func toastColor(_ style: ToastManager.Toast.Style) -> Color {
        switch style {
        case .success: return connectedAccent
        case .error:   return .red
        case .info:    return .blue
        }
    }

    private func pasteFromClipboard() {
        if let str = NSPasteboard.general.string(forType: .string) {
            let stripped = str.trimmingCharacters(in: .whitespacesAndNewlines)
            if stripped.hasPrefix("vless://") || stripped.hasPrefix("vmess://")
                || stripped.hasPrefix("ss://") || stripped.hasPrefix("trojan://") {
                urlText = stripped
                isImportExpanded = true
            }
        }
    }

    // MARK: Helpers

    private func sectionTitle(_ section: AppSection) -> String {
        switch section {
        case .status:
            return lang.t("Главный экран", "Main screen")
        case .profiles:
            return lang.t("Импорт и просмотр профиля", "Import and profile review")
        case .log:
            return lang.t("Диагностика", "Diagnostics")
        case .settings:
            return lang.t("Параметры приложения", "Application settings")
        }
    }

    private var stateColor: Color {
        switch vpn.state {
        case .disconnected:
            return .secondary
        case .connecting, .disconnecting:
            return .orange
        case .connected:
            return connectedAccent
        case .error:
            return .red
        }
    }

}
