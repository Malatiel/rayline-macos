import SwiftUI
import AppKit

struct StatusScreen: View {
    @EnvironmentObject var vpn: VPNManager
    @EnvironmentObject var lang: LanguageManager

    let displayConfig: ProxyConfig?
    let hasLaunchInput: Bool
    @Binding var connectPressed: Bool
    @Binding var shimmerPhase: CGFloat
    let toggleConnection: () -> Void
    let chooseSingBoxBinary: () -> Void

    private var summary: StatusSummary {
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
                    value: summary.profileMetric,
                    icon: "person.crop.square.filled.and.at.rectangle",
                    accent: .primary
                )

                MetricTile(
                    title: lang.t("Пинг", "Ping"),
                    value: summary.pingMetric,
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
                    value: summary.trafficMetric,
                    icon: "arrow.up.arrow.down",
                    accent: .primary
                )
            }

            if let displayConfig {
                profileSummaryCard(displayConfig)
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
                            isActive: summary.isConnectionActivityActive
                        )
                        Text(summary.stateLabel)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(stateColor)
                    }

                    Text(summary.statusText)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if let displayConfig {
                    Text(displayConfig.protoName.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(protocolColor(displayConfig.proto).opacity(0.14), in: Capsule())
                        .foregroundStyle(protocolColor(displayConfig.proto))
                }
            }

            Button(action: toggleConnection) {
                HStack(spacing: 8) {
                    Image(systemName: summary.toggleIcon)
                    Text(summary.toggleTitle)
                }
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(toggleButtonTint)
            .disabled(summary.isToggleDisabled)
            .scaleEffect(connectPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.14), value: connectPressed)
            .overlay(connectingShimmer)

            if let recoveryHint = summary.recoveryHint {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(recoveryHint)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }

            HStack(spacing: 14) {
                statusBadge(
                    title: lang.t("Профиль", "Profile"),
                    value: summary.profileBadge
                )

                statusBadge(
                    title: lang.t("Маршрут", "Route"),
                    value: summary.routeSummary
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

    @ViewBuilder
    private var connectingShimmer: some View {
        if vpn.state.isConnecting {
            RoundedRectangle(cornerRadius: 8)
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
        }
    }

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

                Button {
                    chooseSingBoxBinary()
                } label: {
                    Label(
                        lang.t("Выбрать локальный sing-box", "Choose local sing-box"),
                        systemImage: "folder"
                    )
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
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
        case .disconnecting:
            topColor = Color.orange.opacity(0.08)
            bottomColor = Color.primary.opacity(0.03)
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
        case .disconnecting:
            return Color.orange.opacity(0.22)
        case .error:
            return Color.red.opacity(0.24)
        case .disconnected:
            return Color.primary.opacity(0.06)
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

    private var toggleButtonTint: Color {
        if vpn.state.isConnected {
            return connectedAccent
        }
        if vpn.state.isConnecting || vpn.state.isDisconnecting {
            return .orange
        }
        return .accentColor
    }

    private var pingAccent: Color {
        guard let ping = vpn.pingMs, vpn.state.isConnected else { return .primary }
        return pingColor(ping)
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
}
