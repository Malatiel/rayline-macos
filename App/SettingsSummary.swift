import Foundation

struct SettingsSummary {
    let socksEndpoint: String
    let systemProxyStatus: String
    let isSystemProxyActive: Bool
    let singBoxDescription: String
    let languageToggleTitle: String
    let canResetSystemProxy: Bool
    let proxyResetButtonTitle: String
    let proxyResetDescription: String

    init(
        state: VPNManager.State,
        customSingBoxPath: String,
        language: AppLanguage,
        isResettingSystemProxy: Bool = false
    ) {
        self.socksEndpoint = "127.0.0.1:\(VPNManager.socksPort)"
        self.isSystemProxyActive = state.isConnected
        self.systemProxyStatus = Self.text(
            ru: state.isConnected ? "Активен" : "Неактивен",
            en: state.isConnected ? "Active" : "Inactive",
            language: language
        )
        self.singBoxDescription = customSingBoxPath.isEmpty
            ? Self.text(
                ru: "Используется встроенный, скачанный или системный бинарник",
                en: "Uses bundled, downloaded, or system binary",
                language: language
            )
            : customSingBoxPath
        self.languageToggleTitle = language == .ru ? "EN" : "RU"

        let isConnectionBusy = state.isConnected || state.isConnecting || state.isDisconnecting
        self.canResetSystemProxy = !isConnectionBusy && !isResettingSystemProxy
        self.proxyResetButtonTitle = isResettingSystemProxy
            ? Self.text(ru: "Сброс…", en: "Resetting…", language: language)
            : Self.text(ru: "Сбросить", en: "Reset", language: language)

        if isResettingSystemProxy {
            self.proxyResetDescription = Self.text(
                ru: "Сброс системного SOCKS-прокси выполняется",
                en: "System SOCKS proxy reset is in progress",
                language: language
            )
        } else if isConnectionBusy {
            self.proxyResetDescription = Self.text(
                ru: "Отключитесь перед сбросом системного proxy",
                en: "Disconnect before resetting system proxy settings",
                language: language
            )
        } else {
            self.proxyResetDescription = Self.text(
                ru: "Отключить SOCKS proxy для всех активных сетевых служб",
                en: "Disable SOCKS proxy for all active network services",
                language: language
            )
        }
    }

    private static func text(ru: String, en: String, language: AppLanguage) -> String {
        language == .en ? en : ru
    }
}
