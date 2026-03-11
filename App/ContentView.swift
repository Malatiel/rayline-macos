import SwiftUI

// MARK: - Main window

struct ContentView: View {
    @EnvironmentObject var vpn: VPNManager
    @State private var urlText    = ""
    @State private var parseInfo  = ""
    @State private var parseOK    = false

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
            Text(vpn.state.label)
                .font(.caption)
                .foregroundColor(stateColor)
            Divider().frame(height: 14)
            Button {
                if vpn.state.isConnected { vpn.disconnect() }
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "xmark.circle")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Выйти из приложения")
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
                        Text("VPN-движок не установлен")
                            .font(.callout.weight(.medium))
                    }
                    Text("sing-box нужен для работы VLESS/VMess/SS/Trojan. Скачается автоматически (~15 МБ).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button {
                        Task { await vpn.downloadSingBox() }
                    } label: {
                        Label("Скачать sing-box", systemImage: "arrow.down.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
            }
        } label: {
            Label("Требуется компонент", systemImage: "puzzlepiece")
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
                                Text("\(ms) мс")
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
                    Label(vpn.state.label, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.red)
                        .textSelection(.enabled)
                } else {
                    Text("Нет активного подключения")
                        .font(.caption).foregroundColor(.secondary)
                }

                Divider()

                HStack {
                    if vpn.state.isConnected {
                        Button(role: .destructive) { vpn.disconnect() } label: {
                            Label("Отключить", systemImage: "xmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(.red)
                    } else if vpn.state.isConnecting {
                        ProgressView().scaleEffect(0.7)
                        Text("Подключение…").font(.caption).foregroundColor(.orange)
                        Spacer()
                        Button("Отмена") { vpn.disconnect() }
                    } else {
                        Text("Вставьте ссылку ниже")
                            .font(.caption).foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }
        } label: {
            sectionLabel("Статус", icon: "antenna.radiowaves.left.and.right")
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
                    Button("Проверить") { checkURL() }
                        .disabled(trimmed.isEmpty)

                    Button("Вставить из буфера") { pasteFromClipboard() }
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
                            vpn.state.isConnected ? "Отключить" : "Подключить",
                            systemImage: vpn.state.isConnected ? "xmark.circle" : "play.circle.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(vpn.state.isConnected ? .red : .purple)
                    .disabled(trimmed.isEmpty && !vpn.state.isConnected)
                }
            }
        } label: {
            sectionLabel("Импорт ссылки", icon: "link")
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
                sectionLabel("Лог", icon: "terminal")
                Spacer()
                Button("Очистить") { vpn.clearLog() }
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
                    + (cfg.name.isEmpty || cfg.name == cfg.server ? "" : "\nПрофиль: \(cfg.name)")
                parseOK = true
            } else {
                parseInfo = "❌ Ссылка не содержит сервер или порт"; parseOK = false
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
