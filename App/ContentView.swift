import SwiftUI
import AppKit

private let connectedAccent = Color(
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

// MARK: - Pulsating status dot

private struct PulsingDot: View {
    let color: Color
    let isActive: Bool

    @State private var pulse = false

    var body: some View {
        ZStack {
            if isActive {
                Circle()
                    .fill(color.opacity(0.28))
                    .frame(width: 14, height: 14)
                    .scaleEffect(pulse ? 1.0 : 0.45)
                    .opacity(pulse ? 0.0 : 0.8)
            }

            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
        .frame(width: 14, height: 14)
        .onAppear { updateAnimation(isActive) }
        .onChange(of: isActive) { newValue in
            updateAnimation(newValue)
        }
    }

    private func updateAnimation(_ active: Bool) {
        pulse = false
        guard active else { return }
        withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: false)) {
            pulse = true
        }
    }
}

// MARK: - Shared UI

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

private struct SectionHeaderText: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let icon: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderText(title: title, icon: icon)
            VStack(spacing: 0) {
                content
            }
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

private struct SettingsRow<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var trailing: Content

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct PlaceholderPanel: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(.secondary.opacity(0.7))
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct DetailSurface<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                content
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(22)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(NSColor.windowBackgroundColor),
                    Color.primary.opacity(0.02)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

// MARK: - Main window

struct ContentView: View {
    @EnvironmentObject var vpn: VPNManager
    @EnvironmentObject var lang: LanguageManager
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var toastManager: ToastManager
    @ObservedObject private var themeManager = ThemeManager.shared

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

    private enum LogFilter: String, CaseIterable { case all, error, warning, info }

    private var trimmed: String { urlText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var draftConfig: ProxyConfig? { try? ProxyParser.parse(trimmed) }
    private var displayConfig: ProxyConfig? { vpn.config ?? profileManager.activeProfile ?? draftConfig }

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
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedSection) {
                navigationRow(
                    section: .status,
                    title: lang.t("Статус", "Status"),
                    subtitle: stateLabel(vpn.state),
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
                isActive: vpn.state.isConnected || vpn.state.isConnecting
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(stateLabel(vpn.state))
                    .font(.system(size: 12, weight: .semibold))
                Text(profileSummaryText)
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
                        statusScreen
                    case .profiles:
                        profilesScreen
                    case .log:
                        logScreen
                    case .settings:
                        settingsScreen
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
                if vpn.state.isConnected { vpn.disconnect() }
                NSApplication.shared.terminate(nil)
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

    // MARK: Status

    private var statusScreen: some View {
        DetailSurface {
                if !vpn.hasSingBox {
                    singBoxBanner
                }

                statusHeroCard

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    MetricTile(
                        title: lang.t("Активный профиль", "Active profile"),
                        value: profileMetricValue,
                        icon: "person.crop.square.filled.and.at.rectangle",
                        accent: .primary
                    )

                    MetricTile(
                        title: lang.t("Пинг", "Ping"),
                        value: pingMetricValue,
                        icon: "antenna.radiowaves.left.and.right",
                        accent: pingAccent
                    )
                    .overlay(alignment: .topTrailing) {
                        if vpn.state.isConnected {
                            Button { vpn.refreshPing() } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .padding(10)
                        }
                    }

                    MetricTile(
                        title: lang.t("Трафик", "Traffic"),
                        value: trafficMetricValue,
                        icon: "arrow.up.arrow.down",
                        accent: .primary
                    )
                }

                if let cfg = displayConfig {
                    profileSummaryCard(cfg)
                } else {
                    PlaceholderPanel(
                        title: lang.t("Профиль не выбран", "No profile selected"),
                        subtitle: lang.t(
                            "Импортируйте ссылку на вкладке «Профили», и на главном экране останется только кнопка подключения и текущий статус.",
                            "Import a link on the Profiles tab, and the main screen stays focused on connection state."
                        ),
                        icon: "square.stack.3d.up.slash"
                    )
                }
        }
    }

    private var statusHeroCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        PulsingDot(
                            color: stateColor,
                            isActive: vpn.state.isConnected || vpn.state.isConnecting
                        )
                        Text(stateLabel(vpn.state))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(stateColor)
                    }

                    Text(statusSummaryText)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if let cfg = displayConfig {
                    Text(cfg.protoName.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(protocolColor(cfg.proto).opacity(0.14), in: Capsule())
                        .foregroundStyle(protocolColor(cfg.proto))
                }
            }

            Button(action: toggleConnection) {
                HStack(spacing: 8) {
                    Image(systemName: toggleButtonIcon)
                    Text(toggleButtonTitle)
                }
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(toggleButtonTint)
            .disabled(isToggleDisabled)
            .scaleEffect(connectPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.14), value: connectPressed)
            .overlay(
                vpn.state.isConnecting
                    ? RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.25), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .offset(x: shimmerPhase)
                        .clipped()
                        .onAppear {
                            shimmerPhase = -200
                            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                                shimmerPhase = 200
                            }
                        }
                    : nil
            )

            HStack(spacing: 14) {
                statusBadge(
                    title: lang.t("Профиль", "Profile"),
                    value: displayConfig?.name ?? lang.t("Не выбран", "Not selected")
                )

                statusBadge(
                    title: lang.t("Маршрут", "Route"),
                    value: routeSummaryText
                )
            }
        }
        .padding(24)
        .background(heroBackground, in: RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(heroBorderColor, lineWidth: 1)
        )
    }

    private var heroBackground: LinearGradient {
        let topColor: Color
        let bottomColor: Color

        switch vpn.state {
        case .connected:
            topColor = connectedAccent.opacity(0.14)
            bottomColor = Color.primary.opacity(0.035)
        case .connecting:
            topColor = Color.orange.opacity(0.12)
            bottomColor = Color.primary.opacity(0.035)
        case .error:
            topColor = Color.red.opacity(0.08)
            bottomColor = Color.primary.opacity(0.035)
        case .disconnected:
            topColor = Color.primary.opacity(0.055)
            bottomColor = Color.primary.opacity(0.03)
        }

        return LinearGradient(colors: [topColor, bottomColor], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var heroBorderColor: Color {
        switch vpn.state {
        case .connected:
            return connectedAccent.opacity(0.35)
        case .connecting:
            return Color.orange.opacity(0.3)
        case .error:
            return Color.red.opacity(0.24)
        case .disconnected:
            return Color.primary.opacity(0.06)
        }
    }

    private func statusBadge(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
    }

    private func profileSummaryCard(_ cfg: ProxyConfig) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeaderText(title: lang.t("Детали профиля", "Profile details"), icon: "server.rack")

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(cfg.name)
                        .font(.system(size: 18, weight: .semibold))
                    Text("\(cfg.server):\(cfg.port)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    profileTag(cfg.protoName)
                    if !cfg.security.isEmpty && cfg.security != "none" {
                        profileTag(cfg.security.uppercased())
                    }
                    if !cfg.sni.isEmpty {
                        profileTag("SNI")
                    }
                }
            }

            Divider()

            HStack(spacing: 24) {
                detailLine(
                    title: lang.t("Сеть", "Network"),
                    value: cfg.network.uppercased()
                )
                detailLine(
                    title: "SOCKS5",
                    value: "127.0.0.1:\(VPNManager.socksPort)"
                )
                if !cfg.sni.isEmpty {
                    detailLine(title: "SNI", value: cfg.sni)
                }
            }
        }
        .padding(20)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
    }

    private func profileTag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.06), in: Capsule())
    }

    private func detailLine(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
        }
    }

    // MARK: Profiles

    private var profilesScreen: some View {
        DetailSurface {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(lang.t("Профили", "Profiles"))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text(lang.t(
                            "Управляйте профилями: добавляйте, переименовывайте, удаляйте и переключайтесь между ними.",
                            "Manage profiles: add, rename, delete, and switch between them."
                        ))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isImportExpanded.toggle()
                        }
                    } label: {
                        Label(
                            isImportExpanded
                                ? lang.t("Скрыть импорт", "Hide import")
                                : lang.t("Импорт", "Import"),
                            systemImage: isImportExpanded ? "chevron.up" : "plus.circle"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                }

                if profileManager.profiles.isEmpty {
                    PlaceholderPanel(
                        title: lang.t("Пока нет профиля", "No profile yet"),
                        subtitle: lang.t(
                            "Откройте импорт и вставьте `vless://`, `vmess://`, `ss://` или `trojan://` ссылку.",
                            "Open import and paste a `vless://`, `vmess://`, `ss://`, or `trojan://` link."
                        ),
                        icon: "link.badge.plus"
                    )
                } else {
                    ForEach(profileManager.profiles) { profile in
                        profileRowCard(profile)
                    }
                }

                if isImportExpanded || !trimmed.isEmpty {
                    importPanel
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
        }
    }

    private func profileRowCard(_ cfg: ProxyConfig) -> some View {
        let isActive = profileManager.activeProfileId == cfg.id
        return VStack(spacing: 0) {
            // Main row — tap to select
            Button {
                profileManager.selectProfile(id: cfg.id)
            } label: {
                HStack(spacing: 14) {
                    // Selection indicator
                    Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(isActive ? connectedAccent : .secondary.opacity(0.5))

                    VStack(alignment: .leading, spacing: 6) {
                        if renamingProfileId == cfg.id {
                            TextField(lang.t("Имя профиля", "Profile name"), text: $renameText, onCommit: {
                                profileManager.renameProfile(id: cfg.id, name: renameText)
                                renamingProfileId = nil
                            })
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: 220)
                            .onExitCommand {
                                renamingProfileId = nil
                            }
                        } else {
                            Text(cfg.name.isEmpty ? cfg.server : cfg.name)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                        }

                        HStack(spacing: 8) {
                            Text(cfg.protoName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(protocolColor(cfg.proto))

                            Text("·")
                                .foregroundStyle(.secondary)

                            Text("\(cfg.server):\(cfg.port)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)

                            if isActive {
                                Text(lang.t("активный", "active"))
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(connectedAccent.opacity(0.15), in: Capsule())
                                    .foregroundStyle(connectedAccent)
                            }
                        }
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Action bar
            HStack(spacing: 2) {
                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cfg.toURL(), forType: .string)
                    toastManager.show(lang.t("Ссылка скопирована", "Link copied"), style: .success)
                } label: {
                    Label(lang.t("Копировать", "Copy"), systemImage: "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)

                Text("·").foregroundStyle(.quaternary)

                Button {
                    renameText = cfg.name
                    renamingProfileId = cfg.id
                } label: {
                    Label(lang.t("Переименовать", "Rename"), systemImage: "pencil")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)

                Text("·").foregroundStyle(.quaternary)

                Button {
                    profileManager.deleteProfile(id: cfg.id)
                } label: {
                    Label(lang.t("Удалить", "Delete"), systemImage: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red.opacity(0.6))
            }
            .padding(.top, 10)
        }
        .padding(18)
        .background(
            isActive
                ? connectedAccent.opacity(0.06)
                : Color.primary.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 18)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    isActive ? connectedAccent.opacity(0.3) : Color.primary.opacity(0.08),
                    lineWidth: isActive ? 1.5 : 1
                )
        )
    }

    private var importPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderText(title: lang.t("Импорт ссылки", "Import link"), icon: "link")

            ZStack(alignment: .topLeading) {
                if urlText.isEmpty {
                    Text("vless://  vmess://  ss://  trojan://")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $urlText)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 98)
                    .scrollContentBackground(.hidden)
                    .padding(6)
            }
            .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        trimmed.isEmpty ? Color.secondary.opacity(0.22) : Color.accentColor.opacity(0.45),
                        lineWidth: trimmed.isEmpty ? 1 : 1.4
                    )
            )

            if !parseInfo.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: parseOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                    Text(
                        parseInfo
                            .replacingOccurrences(of: "✅ ", with: "")
                            .replacingOccurrences(of: "❌ ", with: "")
                    )
                    .font(.system(size: 12, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(parseOK ? connectedAccent : .red)
            }

            if parseOK {
                HStack(spacing: 8) {
                    Text(lang.t("Название:", "Name:"))
                        .font(.system(size: 13, weight: .medium))
                    TextField(
                        draftConfig?.name ?? lang.t("Название профиля", "Profile name"),
                        text: $profileNameText
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                }
            }

            HStack(spacing: 10) {
                Button {
                    checkURL()
                } label: {
                    Label(lang.t("Проверить", "Check"), systemImage: "checkmark.magnifyingglass")
                }
                .buttonStyle(.bordered)
                .disabled(trimmed.isEmpty)

                Button {
                    saveProfile()
                } label: {
                    Label(lang.t("Сохранить", "Save"), systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(draftConfig == nil || !parseOK)

                Button {
                    pasteFromClipboard()
                } label: {
                    Label(lang.t("Вставить", "Paste"), systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    selectedSection = .status
                } label: {
                    Text(lang.t("Открыть статус", "Open status"))
                }
                .buttonStyle(.bordered)
                .disabled(displayConfig == nil)
            }
        }
        .padding(20)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onChange(of: urlText) { _ in
            parseInfo = ""
            parseOK = false
            profileNameText = ""
        }
    }

    // MARK: Log

    private var filteredLogs: [(offset: Int, element: String)] {
        Array(vpn.logs.enumerated()).filter { (_, line) in
            let lower = line.lowercased()
            let matchesFilter: Bool
            switch logFilter {
            case .all: matchesFilter = true
            case .error: matchesFilter = lower.contains("error") || lower.contains("fail") || lower.contains("fatal") || lower.contains("ошибка")
            case .warning: matchesFilter = lower.contains("warn") || lower.contains("⚠")
            case .info: matchesFilter = !lower.contains("error") && !lower.contains("fail") && !lower.contains("warn") && !lower.contains("⚠")
            }
            let matchesSearch = logSearchText.isEmpty || lower.contains(logSearchText.lowercased())
            return matchesFilter && matchesSearch
        }
    }

    private var logScreen: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(lang.t("Лог", "Log"))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text(lang.t(
                            "Диагностика и события подключения.",
                            "Diagnostics and connection events."
                        ))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(lang.t("Копировать", "Copy")) {
                        let text = filteredLogs.map(\.element).joined(separator: "\n")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        toastManager.show(lang.t("Лог скопирован", "Log copied"), style: .info)
                    }
                    .buttonStyle(.bordered)
                    .disabled(filteredLogs.isEmpty)

                    Button(lang.t("Очистить", "Clear")) {
                        vpn.clearLog()
                    }
                    .buttonStyle(.bordered)
                    .disabled(vpn.logs.isEmpty)
                }

                HStack(spacing: 10) {
                    TextField(lang.t("Поиск…", "Search…"), text: $logSearchText)
                        .textFieldStyle(.roundedBorder)

                    Picker("", selection: $logFilter) {
                        Text(lang.t("Все", "All")).tag(LogFilter.all)
                        Text(lang.t("Ошибки", "Errors")).tag(LogFilter.error)
                        Text(lang.t("Пред.", "Warn")).tag(LogFilter.warning)
                        Text("Info").tag(LogFilter.info)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }
            }
            .padding(22)

            Divider()

            Group {
                if filteredLogs.isEmpty {
                    PlaceholderPanel(
                        title: lang.t("Лог пуст", "Log is empty"),
                        subtitle: lang.t(
                            "Как только появятся события подключения или ошибки, они будут видны здесь.",
                            "Connection events and errors will appear here as soon as they happen."
                        ),
                        icon: "terminal"
                    )
                    .padding(22)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 3) {
                                ForEach(filteredLogs, id: \.offset) { index, line in
                                    Text(line)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(logLineColor(line))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 18)
                                        .id(index)
                                }
                            }
                            .padding(.vertical, 18)
                        }
                        .background(Color.primary.opacity(0.035))
                        .overlay(
                            RoundedRectangle(cornerRadius: 0)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                        .onChange(of: vpn.logs.count) { _ in
                            if logFilter == .all && logSearchText.isEmpty,
                               let lastIndex = vpn.logs.indices.last {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    proxy.scrollTo(lastIndex, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Settings

    private var settingsScreen: some View {
        DetailSurface {
                Text(lang.t("Настройки", "Settings"))
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                SettingsGroup(title: lang.t("Прокси", "Proxy"), icon: "network") {
                    SettingsRow(
                        title: "SOCKS5",
                        subtitle: lang.t("Локальный порт для приложений", "Local port for apps")
                    ) {
                        Text("127.0.0.1:\(VPNManager.socksPort)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .textSelection(.enabled)
                    }

                    Divider()
                        .padding(.leading, 16)

                    SettingsRow(
                        title: lang.t("Системный прокси", "System proxy"),
                        subtitle: lang.t(
                            "Включается автоматически во время соединения",
                            "Turns on automatically while connected"
                        )
                    ) {
                        Text(vpn.state.isConnected ? lang.t("Активен", "Active") : lang.t("Неактивен", "Inactive"))
                            .foregroundStyle(vpn.state.isConnected ? connectedAccent : .secondary)
                    }
                }

                SettingsGroup(title: lang.t("Защита", "Protection"), icon: "shield") {
                    SettingsRow(
                        title: "Kill Switch",
                        subtitle: lang.t(
                            "Блокирует трафик, если VPN внезапно оборвался",
                            "Blocks traffic if the VPN drops unexpectedly"
                        )
                    ) {
                        Toggle("", isOn: $vpn.killSwitchEnabled)
                            .labelsHidden()
                    }
                }

                SettingsGroup(title: lang.t("Подключение", "Connection"), icon: "bolt.horizontal") {
                    SettingsRow(
                        title: lang.t("Автоподключение", "Auto-connect"),
                        subtitle: lang.t(
                            "Подключаться при запуске, если есть активный профиль",
                            "Connect on launch if an active profile exists"
                        )
                    ) {
                        Toggle("", isOn: $vpn.autoConnectEnabled)
                            .labelsHidden()
                    }
                }

                SettingsGroup(title: lang.t("Оформление", "Appearance"), icon: "paintbrush") {
                    SettingsRow(
                        title: lang.t("Тема", "Theme"),
                        subtitle: nil
                    ) {
                        Picker("", selection: $themeManager.theme) {
                            Text(lang.t("Система", "System")).tag(AppTheme.system)
                            Text(lang.t("Светлая", "Light")).tag(AppTheme.light)
                            Text(lang.t("Тёмная", "Dark")).tag(AppTheme.dark)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                    }
                }

                SettingsGroup(title: lang.t("Система", "System"), icon: "gearshape.2") {
                    SettingsRow(
                        title: lang.t("Язык интерфейса", "Interface language"),
                        subtitle: lang.t("Переключение применяется сразу", "Switches instantly")
                    ) {
                        Button(lang.language == .ru ? "EN" : "RU") {
                            lang.toggle()
                        }
                        .buttonStyle(.bordered)
                    }

                    Divider()
                        .padding(.leading, 16)

                    SettingsRow(
                        title: lang.t("Приложение", "Application"),
                        subtitle: lang.t("Закрыть Veil", "Quit Veil")
                    ) {
                        Button(lang.t("Выйти", "Quit")) {
                            if vpn.state.isConnected { vpn.disconnect() }
                            NSApplication.shared.terminate(nil)
                        }
                        .buttonStyle(.bordered)
                    }
                }
        }
    }

    // MARK: sing-box banner

    private var singBoxBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeaderText(title: lang.t("Требуется компонент", "Component required"), icon: "puzzlepiece")

            if vpn.isDownloading {
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(vpn.downloadStatus)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(lang.t("VPN-движок не установлен", "VPN engine not installed"))
                    .font(.system(size: 16, weight: .semibold))

                Text(lang.t(
                    "sing-box нужен для VLESS, VMess, Shadowsocks и Trojan. Он скачается автоматически и после этого интерфейс останется таким же простым.",
                    "sing-box is required for VLESS, VMess, Shadowsocks, and Trojan. It will download automatically, then the UI stays just as simple."
                ))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Button {
                    Task { await vpn.downloadSingBox() }
                } label: {
                    Label(
                        lang.t("Скачать sing-box", "Download sing-box"),
                        systemImage: "arrow.down.circle.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .padding(20)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
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

    private func toggleConnection() {
        connectPressed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            connectPressed = false
        }

        if vpn.state.isConnected || vpn.state.isConnecting {
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
        case .disconnected where previousVpnState.isConnected:
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

    private func stateLabel(_ state: VPNManager.State) -> String {
        switch state {
        case .disconnected:
            return lang.t("Отключено", "Disconnected")
        case .connecting:
            return lang.t("Подключение…", "Connecting…")
        case .connected:
            return lang.t("Подключено", "Connected")
        case .error(let message):
            return message
        }
    }

    private var stateColor: Color {
        switch vpn.state {
        case .disconnected:
            return .secondary
        case .connecting:
            return .orange
        case .connected:
            return connectedAccent
        case .error:
            return .red
        }
    }

    private var toggleButtonTitle: String {
        if vpn.state.isConnected {
            return lang.t("Отключить", "Disconnect")
        }
        if vpn.state.isConnecting {
            return lang.t("Остановить подключение", "Stop connecting")
        }
        return lang.t("Подключить", "Connect")
    }

    private var toggleButtonIcon: String {
        if vpn.state.isConnected || vpn.state.isConnecting {
            return "power"
        }
        return "play.fill"
    }

    private var toggleButtonTint: Color {
        if vpn.state.isConnected {
            return connectedAccent
        }
        if vpn.state.isConnecting {
            return .orange
        }
        return .accentColor
    }

    private var isToggleDisabled: Bool {
        if vpn.state.isConnected || vpn.state.isConnecting {
            return false
        }
        return profileManager.activeProfile == nil && trimmed.isEmpty
    }

    private var statusSummaryText: String {
        switch vpn.state {
        case .disconnected:
            return lang.t(
                "На экране только главное: состояние туннеля, активный профиль и одна кнопка запуска.",
                "This screen stays focused: tunnel state, active profile, and one launch button."
            )
        case .connecting:
            return lang.t(
                "Veil поднимает туннель и готовит системный прокси. Лог доступен отдельно, если понадобится диагностика.",
                "Veil is bringing up the tunnel and preparing the system proxy. The log stays on its own tab for diagnostics."
            )
        case .connected:
            return lang.t(
                "Соединение активно. Зелёный акцент используется только здесь, чтобы статус подключения читался мгновенно.",
                "The connection is active. Green is used only here so the connected state reads instantly."
            )
        case .error(let message):
            return message
        }
    }

    private var profileMetricValue: String {
        if let cfg = displayConfig {
            return cfg.name.isEmpty ? cfg.server : cfg.name
        }
        return lang.t("Не выбран", "Not selected")
    }

    private var pingMetricValue: String {
        if let ping = vpn.pingMs, vpn.state.isConnected {
            return "\(ping) \(lang.t("мс", "ms"))"
        }
        if vpn.state.isConnecting {
            return "…"
        }
        return "—"
    }

    private var pingAccent: Color {
        guard let ping = vpn.pingMs, vpn.state.isConnected else { return .primary }
        return pingColor(ping)
    }

    private var trafficMetricValue: String {
        if vpn.state.isConnected {
            return "↑\(vpn.packetsSent)  ↓\(vpn.packetsRecv)"
        }
        return "—"
    }

    private var routeSummaryText: String {
        if let cfg = displayConfig {
            return "\(cfg.server):\(cfg.port)"
        }
        return lang.t("Не задан", "Not set")
    }

    private var profileSummaryText: String {
        if let cfg = displayConfig {
            return cfg.name.isEmpty ? cfg.server : cfg.name
        }
        return lang.t("Без профиля", "No profile")
    }

    private func pingColor(_ ms: Int) -> Color {
        ms < 100 ? connectedAccent : ms < 250 ? .orange : .red
    }

    private func protocolColor(_ proto: ProxyProtocol) -> Color {
        switch proto {
        case .vless:
            return .blue
        case .vmess:
            return .indigo
        case .shadowsocks:
            return .teal
        case .trojan:
            return .orange
        }
    }

    private func logLineColor(_ line: String) -> Color {
        let lower = line.lowercased()
        if lower.contains("ошибка") || lower.contains("error") || lower.contains("fail") {
            return .red.opacity(0.85)
        }
        if lower.contains("подключено") || lower.contains("connected") || lower.contains("sha256 ✓") {
            return connectedAccent
        }
        if lower.contains("⚠") || lower.contains("warn") {
            return .orange.opacity(0.85)
        }
        return .secondary
    }
}
