import Foundation

struct StatusSummary {
    struct SetupStep: Equatable {
        let title: String
        let status: String
        let detail: String
        let isComplete: Bool
    }

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
    let recoveryHint: String?
    /// Shown only when the tunnel was checked and found not to carry traffic.
    /// A healthy or unchecked tunnel says nothing, so the card stays quiet.
    let tunnelWarning: String?
    let needsFirstRunSetup: Bool
    let firstRunTitle: String
    let setupSteps: [SetupStep]

    init(
        state: VPNManager.State,
        displayConfig: ProxyConfig?,
        hasLaunchInput: Bool,
        hasSingBox: Bool,
        pingMs: Int?,
        packetsSent: Int,
        packetsRecv: Int,
        tunnelVerified: Bool? = nil,
        language: AppLanguage
    ) {
        self.tunnelWarning = Self.tunnelWarning(
            state,
            tunnelVerified: tunnelVerified,
            language: language
        )
        self.stateLabel = Self.stateLabel(state, language: language)
        self.statusText = Self.statusText(
            state,
            hasLaunchInput: hasLaunchInput,
            hasSingBox: hasSingBox,
            language: language
        )
        self.recoveryHint = Self.recoveryHint(state, language: language)
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
        self.needsFirstRunSetup = !hasSingBox || !hasLaunchInput
        self.firstRunTitle = Self.text(ru: "Завершите настройку", en: "Finish setup", language: language)
        self.setupSteps = [
            SetupStep(
                title: "sing-box",
                status: hasSingBox
                    ? Self.text(ru: "Готов", en: "Ready", language: language)
                    : Self.text(ru: "Требуется", en: "Required", language: language),
                detail: hasSingBox
                    ? Self.text(
                        ru: "Компонент доступен для запуска подключений",
                        en: "Component is available for starting connections",
                        language: language
                    )
                    : Self.text(
                        ru: "Скачайте проверенную версию или выберите локальный файл",
                        en: "Download the verified binary or choose a local file",
                        language: language
                    ),
                isComplete: hasSingBox
            ),
            SetupStep(
                title: Self.text(ru: "Профиль", en: "Profile", language: language),
                status: hasLaunchInput
                    ? Self.text(ru: "Готов", en: "Ready", language: language)
                    : Self.text(ru: "Добавьте профиль", en: "Add profile", language: language),
                detail: hasLaunchInput
                    ? Self.text(
                        ru: "Профиль выбран или ссылка готова к подключению",
                        en: "A profile is selected or a link is ready to connect",
                        language: language
                    )
                    : Self.text(
                        ru: "Импортируйте или сохраните proxy-профиль перед подключением",
                        en: "Import or save a proxy profile before connecting",
                        language: language
                    ),
                isComplete: hasLaunchInput
            )
        ]
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

    private static func statusText(
        _ state: VPNManager.State,
        hasLaunchInput: Bool,
        hasSingBox: Bool,
        language: AppLanguage
    ) -> String {
        switch state {
        case .disconnected:
            if !hasSingBox || !hasLaunchInput {
                return text(
                    ru: "Подготовьте sing-box и профиль, затем подключение будет доступно с главного экрана.",
                    en: "Prepare sing-box and a profile, then connection is available from the main screen.",
                    language: language
                )
            }
            return text(
                ru: "На экране только главное: состояние туннеля, активный профиль и одна кнопка запуска.",
                en: "This screen stays focused: tunnel state, active profile, and one launch button.",
                language: language
            )
        case .connecting:
            return text(
                ru: "Rayline поднимает туннель и готовит системный прокси. Лог доступен отдельно, если понадобится диагностика.",
                en: "Rayline is bringing up the tunnel and preparing the system proxy. The log stays on its own tab for diagnostics.",
                language: language
            )
        case .disconnecting:
            return text(
                ru: "Rayline снимает системный прокси и завершает очистку. Лучше дождаться этого состояния перед выходом.",
                en: "Rayline is clearing the system proxy and finishing cleanup. It's best to let this complete before quitting.",
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

    /// A latency reading proves only that the server's port answers, so a
    /// connected state with a failed tunnel check must be called out — that is
    /// exactly the case where everything looks green and nothing works.
    private static func tunnelWarning(
        _ state: VPNManager.State,
        tunnelVerified: Bool?,
        language: AppLanguage
    ) -> String? {
        guard state.isConnected, tunnelVerified == false else { return nil }
        return text(
            ru: "Подключено, но трафик через туннель не проходит — проверьте профиль",
            en: "Connected, but no traffic passes through the tunnel — check the profile",
            language: language
        )
    }

    private static func recoveryHint(_ state: VPNManager.State, language: AppLanguage) -> String? {
        guard case .error(let message) = state else { return nil }
        let lower = message.lowercased()

        if lower.contains("10808") || lower.contains("порт") || lower.contains("port") {
            return text(
                ru: "Порт 127.0.0.1:10808 может быть занят. Остановите старый процесс или перезапустите Rayline.",
                en: "Port 127.0.0.1:10808 may be busy. Stop the old process or restart Rayline.",
                language: language
            )
        }
        if lower.contains("sing-box") {
            return text(
                ru: "Проверьте выбранный sing-box в настройках или скачайте встроенную версию заново.",
                en: "Check the selected sing-box in Settings or download the bundled version again.",
                language: language
            )
        }
        if lower.contains("proxy") || lower.contains("прокси") {
            return text(
                ru: "Проверьте системные сетевые настройки macOS и экспортируйте диагностику из лога, если ошибка повторяется.",
                en: "Check macOS network settings and export diagnostics from the log if the error repeats.",
                language: language
            )
        }
        return text(
            ru: "Откройте лог и экспортируйте диагностику, если нужна помощь без передачи секретов.",
            en: "Open the log and export diagnostics if you need help without sharing secrets.",
            language: language
        )
    }

    private static func text(ru: String, en: String, language: AppLanguage) -> String {
        language == .en ? en : ru
    }
}
