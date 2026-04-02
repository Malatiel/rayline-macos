import SwiftUI

// MARK: - Main window

struct ContentView: View {
    @EnvironmentObject var vpn:  VPNManager
    @EnvironmentObject var lang: LanguageManager
    @State private var urlText   = ""
    @State private var parseInfo = ""
    @State private var parseOK   = false

    private var trimmed: String { urlText.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            ScrollView {
                VStack(spacing: 10) {
                    if !vpn.hasSingBox { singBoxBanner }
                    statusCard
                    if vpn.hasSingBox || vpn.isDownloading { importCard }
                    logCard
                }
                .padding(12)
            }
        }
        .frame(width: 420, height: 540)
    }

    // MARK: Header

    var headerBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "shield.fill")
                .foregroundColor(.purple)
            Text("**Veil**")
                .font(.headline)
            Spacer()
            Circle()
                .fill(stateColor)
                .frame(width: 8, height: 8)
            Text(stateLabel(vpn.state))
                .font(.caption)
                .foregroundColor(stateColor)
            Divider().frame(height: 14)
            Button {
                lang.toggle()
            } label: {
                Text(lang.language == .ru ? "EN" : "RU")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.8))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .help(lang.t("Переключить язык", "Switch language"))
            Divider().frame(height: 14)
            Button {
                if vpn.state.isConnected { vpn.disconnect() }
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "xmark.circle")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(lang.t("Выйти из приложения", "Quit application"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.bar)
    }

    // MARK: sing-box banner

    var singBoxBanner: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if vpn.isDownloading {
                    HStack(spacing: 10) {
                        ProgressView().scaleEffect(0.8)
                        Text(vpn.downloadStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(lang.t("VPN-движок не установлен", "VPN engine not installed"))
                            .font(.callout.weight(.medium))
                    }
                    Text(lang.t(
                        "sing-box нужен для работы VLESS/VMess/SS/Trojan. Скачается автоматически (~15 МБ).",
                        "sing-box is required for VLESS/VMess/SS/Trojan. Will be downloaded automatically (~15 MB)."
                    ))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    Button {
                        Task { await vpn.downloadSingBox() }
                    } label: {
                        Label(
                            lang.t("Скачать sing-box", "Download sing-box"),
                            systemImage: "arrow.down.circle.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
            }
        } label: {
            Label(
                lang.t("Требуется компонент", "Component required"),
                systemImage: "puzzlepiece"
            )
            .font(.caption.weight(.semibold))
            .foregroundColor(.orange)
        }
    }

    // MARK: Status card

    var statusCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if let cfg = vpn.config, vpn.state.isConnected || vpn.state.isConnecting {
                    HStack {
                        Label(cfg.protoName, systemImage: "lock.shield.fill")
                            .font(.callout.weight(.medium))
                        Spacer()
                        Text("\(cfg.server):\(cfg.port)")
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 4) {
                        Text("SOCKS5").font(.caption2).foregroundColor(.secondary)
                        Text("127.0.0.1:\(VPNManager.socksPort)")
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                        if !cfg.name.isEmpty && cfg.name != cfg.server {
                            Text("·").foregroundColor(.secondary)
                            Text(cfg.name).font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    if !cfg.sni.isEmpty {
                        Text("SNI: \(cfg.sni)").font(.caption2).foregroundColor(.secondary)
                    }
                    if vpn.state.isConnected {
                        Divider()
                        HStack(spacing: 0) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .frame(width: 18)
                            if let ms = vpn.pingMs {
                                Text("\(ms) \(lang.t("мс", "ms"))")
                                    .font(.caption2.monospaced().weight(.medium))
                                    .foregroundColor(ms < 100 ? .green : ms < 250 ? .orange : .red)
                            } else {
                                Text("…")
                                    .font(.caption2.monospaced())
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("↑\(vpn.packetsSent)  ↓\(vpn.packetsRecv)")
                                .font(.caption2.monospaced())
                                .foregroundColor(.secondary)
                        }
                    }
                } else if vpn.state.isError {
                    Label(stateLabel(vpn.state), systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.red)
                        .textSelection(.enabled)
                } else {
                    Text(lang.t("Нет активного подключения", "No active connection"))
                        .font(.caption).foregroundColor(.secondary)
                }

                Divider()

                HStack(spacing: 6) {
                    Image(systemName: vpn.killSwitchEnabled ? "shield.slash.fill" : "shield.slash")
                        .font(.caption)
                        .foregroundColor(vpn.killSwitchEnabled ? .red : .secondary)
                    Text("Kill Switch")
                        .font(.caption)
                        .foregroundColor(vpn.killSwitchEnabled ? .primary : .secondary)
                    Spacer()
                    Toggle("", isOn: $vpn.killSwitchEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                }
                .help(lang.t(
                    "Блокирует весь трафик при обрыве VPN-соединения",
                    "Blocks all traffic if the VPN connection drops"
                ))

                Divider()

                HStack {
                    if vpn.state.isConnected {
                        Button(role: .destructive) { vpn.disconnect() } label: {
                            Label(
                                lang.t("Отключить", "Disconnect"),
                                systemImage: "xmark.circle.fill"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(.red)
                    } else if vpn.state.isConnecting {
                        ProgressView().scaleEffect(0.7)
                        Text(lang.t("Подключение…", "Connecting…"))
                            .font(.caption).foregroundColor(.orange)
                        Spacer()
                        Button(lang.t("Отмена", "Cancel")) { vpn.disconnect() }
                    } else {
                        Text(lang.t("Вставьте ссылку ниже", "Paste a link below"))
                            .font(.caption).foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }
        } label: {
            sectionLabel(lang.t("Статус", "Status"), icon: "antenna.radiowaves.left.and.right")
        }
    }

    // MARK: Import card

    var importCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    if urlText.isEmpty {
                        Text("vless://  vmess://  ss://  trojan://")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $urlText)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(height: 72)
                        .scrollContentBackground(.hidden)
                        .padding(2)
                }
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))

                if !parseInfo.isEmpty {
                    Text(parseInfo)
                        .font(.caption.monospaced())
                        .foregroundColor(parseOK ? .green : .red)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    Button(lang.t("Проверить", "Check")) { checkURL() }
                        .disabled(trimmed.isEmpty)

                    Button(lang.t("Вставить из буфера", "Paste from clipboard")) {
                        pasteFromClipboard()
                    }
                    .foregroundColor(.secondary)

                    Spacer()

                    Button {
                        if vpn.state.isConnected || vpn.state.isConnecting {
                            vpn.disconnect()
                        } else {
                            connectVPN()
                        }
                    } label: {
                        Label(
                            vpn.state.isConnected
                                ? lang.t("Отключить", "Disconnect")
                                : lang.t("Подключить", "Connect"),
                            systemImage: vpn.state.isConnected ? "xmark.circle" : "play.circle.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(vpn.state.isConnected ? .red : .purple)
                    .disabled(trimmed.isEmpty && !vpn.state.isConnected)
                }
            }
        } label: {
            sectionLabel(lang.t("Импорт ссылки", "Import link"), icon: "link")
        }
    }

    // MARK: Log card

    var logCard: some View {
        GroupBox {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(vpn.logs.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Color.clear.frame(height: 1).id("logBottom")
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 110)
                .onChange(of: vpn.logs.count) { _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("logBottom")
                    }
                }
            }
        } label: {
            HStack {
                sectionLabel(lang.t("Лог", "Log"), icon: "terminal")
                Spacer()
                Button(lang.t("Очистить", "Clear")) { vpn.clearLog() }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
            }
        }
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
            parseInfo = "❌ \(error.localizedDescription)"; parseOK = false
        }
    }

    private func connectVPN() {
        vpn.connect(urlString: trimmed)
    }

    private func pasteFromClipboard() {
        if let str = NSPasteboard.general.string(forType: .string) {
            let stripped = str.trimmingCharacters(in: .whitespacesAndNewlines)
            if stripped.hasPrefix("vless://") || stripped.hasPrefix("vmess://")
                || stripped.hasPrefix("ss://") || stripped.hasPrefix("trojan://") {
                urlText = stripped
                parseInfo = ""; parseOK = false
            }
        }
    }

    // MARK: Helpers

    private func stateLabel(_ state: VPNManager.State) -> String {
        switch state {
        case .disconnected: return lang.t("Отключено", "Disconnected")
        case .connecting:   return lang.t("Подключение…", "Connecting…")
        case .connected:    return lang.t("Подключено", "Connected")
        case .error(let e): return e
        }
    }

    private var stateColor: Color {
        switch vpn.state {
        case .disconnected: return .secondary
        case .connecting:   return .orange
        case .connected:    return .green
        case .error:        return .red
        }
    }

    private func sectionLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)
    }
}
