import Foundation

struct SettingsSummary {
    let socksEndpoint: String
    let systemProxyStatus: String
    let isSystemProxyActive: Bool
    let singBoxDescription: String
    let languageToggleTitle: String

    init(state: VPNManager.State, customSingBoxPath: String, language: AppLanguage) {
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
    }

    private static func text(ru: String, en: String, language: AppLanguage) -> String {
        language == .en ? en : ru
    }
}
