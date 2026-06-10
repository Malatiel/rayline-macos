import XCTest
@testable import RaylineCore

final class ContentFeedbackTests: XCTestCase {

    // MARK: - importToast

    func testImportToastAllDuplicates() {
        let result = ProfileBatchAddResult(addedCount: 0, skippedDuplicateCount: 3)
        XCTAssertEqual(ContentFeedback.importToast(result, language: .ru), "Все профили уже добавлены")
        XCTAssertEqual(ContentFeedback.importToast(result, language: .en), "All profiles already added")
    }

    func testImportToastAddedWithDuplicates() {
        let result = ProfileBatchAddResult(addedCount: 2, skippedDuplicateCount: 1)
        XCTAssertEqual(ContentFeedback.importToast(result, language: .en), "Added: 2, duplicates: 1")
    }

    func testImportToastSingleSaved() {
        let result = ProfileBatchAddResult(addedCount: 1, skippedDuplicateCount: 0)
        XCTAssertEqual(ContentFeedback.importToast(result, language: .ru), "Профиль сохранён")
        XCTAssertEqual(ContentFeedback.importToast(result, language: .en), "Profile saved")
    }

    func testImportToastMultipleSaved() {
        let result = ProfileBatchAddResult(addedCount: 4, skippedDuplicateCount: 0)
        XCTAssertEqual(ContentFeedback.importToast(result, language: .en), "Profiles saved: 4")
    }

    // MARK: - importPreview

    func testImportPreviewEmptyUsesFirstFailureMessage() {
        let result = ProfileImportResult(
            profiles: [],
            failures: [ProfileImportFailure(input: "junk", message: "bad link")]
        )
        let banner = ContentFeedback.importPreview(result, language: .en)
        XCTAssertFalse(banner.ok)
        XCTAssertEqual(banner.text, "❌ bad link")
    }

    func testImportPreviewEmptyNoFailuresFallsBackToLocalizedText() {
        let result = ProfileImportResult(profiles: [], failures: [])
        XCTAssertEqual(ContentFeedback.importPreview(result, language: .ru).text,
                       "❌ Поддерживаемые ссылки не найдены")
        XCTAssertEqual(ContentFeedback.importPreview(result, language: .en).text,
                       "❌ No supported links found")
    }

    func testImportPreviewSingleProfileWithSecuritySniAndName() {
        let cfg = ProxyConfig(
            proto: .vless, uuid: "u", server: "v.example", port: 443,
            name: "MyNode", security: "tls", sni: "sni.example"
        )
        let banner = ContentFeedback.importPreview(
            ProfileImportResult(profiles: [cfg], failures: []),
            language: .ru
        )
        XCTAssertTrue(banner.ok)
        XCTAssertEqual(banner.text, "✅ VLESS · v.example:443 · TLS · SNI: sni.example\nПрофиль: MyNode")
    }

    func testImportPreviewSingleProfileNameEqualsServerOmitsProfileLine() {
        let cfg = ProxyConfig(
            proto: .trojan, uuid: "pw", server: "t.example", port: 8443,
            name: "t.example", security: "none"
        )
        let banner = ContentFeedback.importPreview(
            ProfileImportResult(profiles: [cfg], failures: []),
            language: .en
        )
        XCTAssertEqual(banner.text, "✅ Trojan · t.example:8443")
    }

    func testImportPreviewMultipleProfilesWithFailures() {
        let cfg = ProxyConfig(proto: .vless, server: "a.example", port: 443)
        let result = ProfileImportResult(
            profiles: [cfg, cfg],
            failures: [ProfileImportFailure(input: "x", message: "nope")]
        )
        XCTAssertEqual(ContentFeedback.importPreview(result, language: .en).text,
                       "✅ Profiles found: 2 · failed: 1")
    }

    // MARK: - subscriptionRefresh

    func testSubscriptionRefreshFailureOnly() {
        let result = SubscriptionRefreshResult(
            sourceId: UUID(), sourceName: "Work",
            addedCount: 0, skippedDuplicateCount: 0, failedCount: 1,
            fastestProfileName: nil, message: "HTTP 503"
        )
        let outcome = ContentFeedback.subscriptionRefresh(result, language: .en)
        XCTAssertFalse(outcome.banner.ok)
        XCTAssertEqual(outcome.banner.text, "❌ HTTP 503")
        XCTAssertEqual(outcome.toast, ContentFeedback.Toast(message: "HTTP 503", style: .error))
    }

    func testSubscriptionRefreshSuccessWithCounts() {
        let result = SubscriptionRefreshResult(
            sourceId: UUID(), sourceName: "Work",
            addedCount: 2, skippedDuplicateCount: 1, updatedCount: 1, removedCount: 1, failedCount: 0,
            fastestProfileName: "Fast", message: ""
        )
        let outcome = ContentFeedback.subscriptionRefresh(result, language: .en)
        XCTAssertTrue(outcome.banner.ok)
        XCTAssertEqual(outcome.banner.text, "✅ Work: added 2 · duplicates 1 · updated 1 · removed 1")
        XCTAssertEqual(outcome.toast, ContentFeedback.Toast(message: "Refreshed: Work", style: .success))
    }

    func testSubscriptionRefreshNoNewProfiles() {
        let result = SubscriptionRefreshResult(
            sourceId: UUID(), sourceName: "Work",
            addedCount: 0, skippedDuplicateCount: 3, failedCount: 0,
            fastestProfileName: nil, message: ""
        )
        let outcome = ContentFeedback.subscriptionRefresh(result, language: .ru)
        XCTAssertTrue(outcome.banner.ok)
        XCTAssertEqual(outcome.banner.text, "✅ Work: добавлено 0 · дубликатов 3")
        XCTAssertEqual(outcome.toast, ContentFeedback.Toast(message: "Новых профилей нет", style: .info))
    }
}
