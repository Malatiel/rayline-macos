import Foundation

struct ProfilesSummary {
    struct Row {
        let id: UUID
        let displayName: String
        let protocolName: String
        let route: String
        let sourceLabel: String?
        let latencyText: String
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
                latencyText: Self.latencyText(for: profile, language: language),
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

    private static func latencyText(for profile: ProxyConfig, language: AppLanguage) -> String {
        if let latency = profile.latencyMs {
            return "\(latency) ms"
        }
        if profile.latencyUpdatedAt != nil {
            return text(ru: "timeout", en: "timeout", language: language)
        }
        return text(ru: "не проверено", en: "not checked", language: language)
    }
}

struct SubscriptionSourceDisplaySummary {
    let detail: String
    let profileCountText: String
    let statusIcon: String
    let isError: Bool

    init(source: SubscriptionSource, profileCount: Int, language: AppLanguage) {
        self.profileCountText = Self.profileCountText(profileCount, language: language)

        if let error = source.lastError, !error.isEmpty {
            self.detail = [
                profileCountText,
                Self.text(ru: "ошибка обновления", en: "Refresh failed", language: language),
                error
            ].joined(separator: " · ")
            self.statusIcon = "exclamationmark.triangle"
            self.isError = true
            return
        }

        if let summary = source.lastSummary, !summary.isEmpty {
            let refreshText = Self.refreshText(source.lastRefreshedAt, language: language)
            self.detail = [profileCountText, refreshText, summary].joined(separator: " · ")
            self.statusIcon = "checkmark.circle"
            self.isError = false
            return
        }

        self.detail = [
            profileCountText,
            Self.text(ru: "ещё не обновлялась", en: "Not refreshed yet", language: language),
            source.url
        ].joined(separator: " · ")
        self.statusIcon = "tray.full"
        self.isError = false
    }

    private static func profileCountText(_ count: Int, language: AppLanguage) -> String {
        if language == .en {
            return count == 1 ? "1 profile" : "\(count) profiles"
        }
        return "\(count) \(russianProfileWord(count))"
    }

    private static func russianProfileWord(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if mod10 == 1 && mod100 != 11 { return "профиль" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "профиля" }
        return "профилей"
    }

    private static func refreshText(_ date: Date?, language: AppLanguage) -> String {
        guard let date else {
            return text(ru: "обновление завершено", en: "Last refresh completed", language: language)
        }
        let prefix = text(ru: "последнее обновление", en: "Last refresh", language: language)
        return "\(prefix): \(DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short))"
    }

    private static func text(ru: String, en: String, language: AppLanguage) -> String {
        language == .en ? en : ru
    }
}
