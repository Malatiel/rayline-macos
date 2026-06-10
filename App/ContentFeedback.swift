import Foundation

/// Pure, testable presentation logic extracted from ContentView's glue methods.
/// It takes the current `AppLanguage` explicitly, so the message/banner building
/// that used to live inside the SwiftUI view can be unit-tested in both
/// languages without the view layer or the `LanguageManager` singleton.
enum ContentFeedback {

    /// An inline status line shown under the import field (the `parseInfo` /
    /// `parseOK` pair in ContentView).
    struct Banner: Equatable {
        let text: String
        let ok: Bool
    }

    struct Toast: Equatable {
        let message: String
        let style: ToastManager.Toast.Style
    }

    /// Outcome of a subscription refresh: the inline banner plus the toast.
    struct RefreshOutcome: Equatable {
        let banner: Banner
        let toast: Toast
    }

    // MARK: - Import preview (ContentView.checkURL)

    static func importPreview(_ result: ProfileImportResult, language: AppLanguage) -> Banner {
        guard !result.profiles.isEmpty else {
            let text = result.failures.first.map { "❌ \($0.message)" }
                ?? "❌ \(t("Поддерживаемые ссылки не найдены", "No supported links found", language))"
            return Banner(text: text, ok: false)
        }

        if result.profiles.count == 1, let cfg = result.profiles.first {
            let text = "✅ \(cfg.protoName) · \(cfg.server):\(cfg.port)"
                + (cfg.security.isEmpty || cfg.security == "none" ? "" : " · \(cfg.security.uppercased())")
                + (cfg.sni.isEmpty ? "" : " · SNI: \(cfg.sni)")
                + (cfg.name.isEmpty || cfg.name == cfg.server
                    ? ""
                    : "\n\(t("Профиль", "Profile", language)): \(cfg.name)")
            return Banner(text: text, ok: true)
        }

        let warning = result.failures.isEmpty
            ? ""
            : " · \(t("ошибок", "failed", language)): \(result.failureCount)"
        let text = "✅ \(t("Профилей найдено", "Profiles found", language)): \(result.validCount)\(warning)"
        return Banner(text: text, ok: true)
    }

    // MARK: - Saved-profiles toast (ContentView.importToastMessage)

    static func importToast(_ result: ProfileBatchAddResult, language: AppLanguage) -> String {
        if result.addedCount == 0, result.skippedDuplicateCount > 0 {
            return t("Все профили уже добавлены", "All profiles already added", language)
        }
        if result.skippedDuplicateCount > 0 {
            return t(
                "Добавлено: \(result.addedCount), дубликатов: \(result.skippedDuplicateCount)",
                "Added: \(result.addedCount), duplicates: \(result.skippedDuplicateCount)",
                language
            )
        }
        return result.addedCount == 1
            ? t("Профиль сохранён", "Profile saved", language)
            : t("Профилей сохранено: \(result.addedCount)", "Profiles saved: \(result.addedCount)", language)
    }

    // MARK: - Subscription refresh outcome (ContentView.showSubscriptionRefreshResult)

    static func subscriptionRefresh(_ result: SubscriptionRefreshResult, language: AppLanguage) -> RefreshOutcome {
        if result.failedCount > 0, result.addedCount == 0, result.skippedDuplicateCount == 0 {
            return RefreshOutcome(
                banner: Banner(text: "❌ \(result.message)", ok: false),
                toast: Toast(message: result.message, style: .error)
            )
        }

        let text = "✅ \(result.sourceName): \(t("добавлено", "added", language)) \(result.addedCount)"
            + " · \(t("дубликатов", "duplicates", language)) \(result.skippedDuplicateCount)"
            + (result.updatedCount > 0 ? " · \(t("обновлено", "updated", language)) \(result.updatedCount)" : "")
            + (result.removedCount > 0 ? " · \(t("удалено", "removed", language)) \(result.removedCount)" : "")
            + (result.failedCount > 0 ? " · \(t("ошибок", "failed", language)) \(result.failedCount)" : "")

        let toast: Toast
        if result.addedCount > 0 || result.updatedCount > 0 || result.removedCount > 0 {
            toast = Toast(
                message: t("Обновлено: \(result.sourceName)", "Refreshed: \(result.sourceName)", language),
                style: .success
            )
        } else {
            toast = Toast(
                message: t("Новых профилей нет", "No new profiles", language),
                style: .info
            )
        }
        return RefreshOutcome(banner: Banner(text: text, ok: true), toast: toast)
    }

    // MARK: - Helpers

    private static func t(_ ru: String, _ en: String, _ language: AppLanguage) -> String {
        language == .en ? en : ru
    }
}
