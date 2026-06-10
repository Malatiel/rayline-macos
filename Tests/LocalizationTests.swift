import XCTest
@testable import RaylineCore

final class LocalizationTests: XCTestCase {

    func testLocalizedMessageResolvesPerLanguageWithoutGlobalState() {
        let message = LocalizedMessage(ru: "Привет", en: "Hello")
        XCTAssertEqual(message.resolved(.ru), "Привет")
        XCTAssertEqual(message.resolved(.en), "Hello")
    }

    func testModelErrorsCarryBilingualDataWithoutTouchingTheSingleton() {
        // Pure-data errors expose both languages and can be resolved explicitly,
        // so localization is decided at the presentation layer, not at throw time.
        let parse: LocalizableError = ParseError.invalidPort
        XCTAssertEqual(parse.localizedMessage.resolved(.ru), "Неверный порт")
        XCTAssertEqual(parse.localizedMessage.resolved(.en), "Invalid port")

        let fetch: LocalizableError = SubscriptionFetchError.httpStatus(503)
        XCTAssertTrue(fetch.localizedMessage.resolved(.ru).contains("503"))
        XCTAssertTrue(fetch.localizedMessage.resolved(.en).contains("503"))
    }

    func testLocalizedDescriptionBridgeMatchesActiveLanguage() {
        let previousLanguage = LanguageManager.shared.language
        defer { LanguageManager.shared.language = previousLanguage }

        LanguageManager.shared.language = .en
        XCTAssertEqual((SubscriptionError.duplicateURL as Error).localizedDescription,
                       "This subscription is already added")

        LanguageManager.shared.language = .ru
        XCTAssertEqual((SubscriptionError.duplicateURL as Error).localizedDescription,
                       "Такая подписка уже добавлена")
    }
}
