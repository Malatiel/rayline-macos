import Foundation

struct StatusSummary {
    let stateLabel: String
    let statusText: String
    let toggleTitle: String
    let toggleIcon: String
    let isToggleDisabled: Bool
    let isConnectionActivityActive: Bool
    let profileMetric: String
    let profileBadge: String
    let profileSummary: String
    let pingMetric: String
    let trafficMetric: String
    let routeSummary: String

    init(
        state: VPNManager.State,
        displayConfig: ProxyConfig?,
        hasLaunchInput: Bool,
        pingMs: Int?,
        packetsSent: Int,
        packetsRecv: Int,
        language: AppLanguage
    ) {
        self.stateLabel = Self.stateLabel(state, language: language)
        self.statusText = Self.statusText(state, language: language)
        self.toggleTitle = Self.toggleTitle(state, language: language)
        self.toggleIcon = state.isConnected || state.isConnecting || state.isDisconnecting ? "power" : "play.fill"
        self.isToggleDisabled = state == .disconnecting
            || (!state.isConnected && !state.isConnecting && !hasLaunchInput)
        self.isConnectionActivityActive = state.isConnected || state.isConnecting || state.isDisconnecting

        if let displayConfig {
            let fallbackName = displayConfig.name.isEmpty ? displayConfig.server : displayConfig.name
            self.profileMetric = fallbackName
            self.profileBadge = displayConfig.name
            self.profileSummary = fallbackName
            self.routeSummary = "\(displayConfig.server):\(displayConfig.port)"
        } else {
            self.profileMetric = Self.text(ru: "Не выбран", en: "Not selected", language: language)
            self.profileBadge = self.profileMetric
            self.profileSummary = Self.text(ru: "Без профиля", en: "No profile", language: language)
            self.routeSummary = Self.text(ru: "Не задан", en: "Not set", language: language)
        }

        if let pingMs, state.isConnected {
            self.pingMetric = "\(pingMs) \(Self.text(ru: "мс", en: "ms", language: language))"
        } else if state.isConnecting {
            self.pingMetric = "…"
        } else {
            self.pingMetric = "—"
        }

        self.trafficMetric = state.isConnected ? "↑\(packetsSent)  ↓\(packetsRecv)" : "—"
    }

    private static func stateLabel(_ state: VPNManager.State, language: AppLanguage) -> String {
        switch state {
        case .disconnected:
            return text(ru: "Отключено", en: "Disconnected", language: language)
        case .connecting:
            return text(ru: "Подключение…", en: "Connecting…", language: language)
        case .disconnecting:
            return text(ru: "Отключение…", en: "Disconnecting…", language: language)
        case .connected:
            return text(ru: "Подключено", en: "Connected", language: language)
        case .error(let message):
            return message
        }
    }

    private static func statusText(_ state: VPNManager.State, language: AppLanguage) -> String {
        switch state {
        case .disconnected:
            return text(
                ru: "На экране только главное: состояние туннеля, активный профиль и одна кнопка запуска.",
                en: "This screen stays focused: tunnel state, active profile, and one launch button.",
                language: language
            )
        case .connecting:
            return text(
                ru: "Veil поднимает туннель и готовит системный прокси. Лог доступен отдельно, если понадобится диагностика.",
                en: "Veil is bringing up the tunnel and preparing the system proxy. The log stays on its own tab for diagnostics.",
                language: language
            )
        case .disconnecting:
            return text(
                ru: "Veil снимает системный прокси и завершает очистку. Лучше дождаться этого состояния перед выходом.",
                en: "Veil is clearing the system proxy and finishing cleanup. It's best to let this complete before quitting.",
                language: language
            )
        case .connected:
            return text(
                ru: "Соединение активно. Зелёный акцент используется только здесь, чтобы статус подключения читался мгновенно.",
                en: "The connection is active. Green is used only here so the connected state reads instantly.",
                language: language
            )
        case .error(let message):
            return message
        }
    }

    private static func toggleTitle(_ state: VPNManager.State, language: AppLanguage) -> String {
        if state.isConnected {
            return text(ru: "Отключить", en: "Disconnect", language: language)
        }
        if state == .disconnecting {
            return text(ru: "Отключение…", en: "Disconnecting…", language: language)
        }
        if state.isConnecting {
            return text(ru: "Остановить подключение", en: "Stop connecting", language: language)
        }
        return text(ru: "Подключить", en: "Connect", language: language)
    }

    private static func text(ru: String, en: String, language: AppLanguage) -> String {
        language == .en ? en : ru
    }
}
