import Foundation

struct ProfilesSummary {
    struct Row {
        let id: UUID
        let displayName: String
        let protocolName: String
        let route: String
        let sourceLabel: String?
        let isActive: Bool
        let activeBadge: String
        let isDeleteDisabled: Bool
        let deleteHelp: String
    }

    let isEmpty: Bool
    let shouldShowImportPanel: Bool
    let importButtonTitle: String
    let importButtonIcon: String
    let emptyTitle: String
    let emptySubtitle: String
    let rows: [Row]

    init(
        profiles: [ProxyConfig],
        activeProfileId: UUID?,
        isImportExpanded: Bool,
        importText: String,
        vpnState: VPNManager.State,
        language: AppLanguage
    ) {
        self.isEmpty = profiles.isEmpty
        self.shouldShowImportPanel = isImportExpanded || !importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        self.importButtonTitle = isImportExpanded
            ? Self.text(ru: "Скрыть импорт", en: "Hide import", language: language)
            : Self.text(ru: "Импорт", en: "Import", language: language)
        self.importButtonIcon = isImportExpanded ? "chevron.up" : "plus.circle"
        self.emptyTitle = Self.text(ru: "Пока нет профиля", en: "No profile yet", language: language)
        self.emptySubtitle = Self.text(
            ru: "Откройте импорт и вставьте `vless://`, `vmess://`, `ss://` или `trojan://` ссылку.",
            en: "Open import and paste a `vless://`, `vmess://`, `ss://`, or `trojan://` link.",
            language: language
        )

        let activeBadge = Self.text(ru: "активный", en: "active", language: language)
        let deleteHelp = Self.text(
            ru: "Отключитесь перед удалением активного профиля",
            en: "Disconnect before deleting the active profile",
            language: language
        )

        self.rows = profiles.map { profile in
            let isActive = activeProfileId == profile.id
            let isDeleteDisabled = isActive && (vpnState.isConnected || vpnState.isConnecting || vpnState.isDisconnecting)
            return Row(
                id: profile.id,
                displayName: profile.name.isEmpty ? profile.server : profile.name,
                protocolName: profile.protoName,
                route: "\(profile.server):\(profile.port)",
                sourceLabel: profile.sourceName,
                isActive: isActive,
                activeBadge: activeBadge,
                isDeleteDisabled: isDeleteDisabled,
                deleteHelp: isDeleteDisabled ? deleteHelp : ""
            )
        }
    }

    private static func text(ru: String, en: String, language: AppLanguage) -> String {
        language == .en ? en : ru
    }
}
