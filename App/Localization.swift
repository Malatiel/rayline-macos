import Foundation

enum AppLanguage: String {
    case ru, en
}

/// A message available in both supported languages, carried as plain data with
/// no dependency on the UI language singleton. Model and parsing types expose a
/// `LocalizedMessage` instead of resolving a concrete string at throw time, so
/// the same error can be rendered in either language at the presentation layer
/// and unit-tested without mutating global state.
struct LocalizedMessage: Equatable, Sendable {
    let ru: String
    let en: String

    func resolved(_ language: AppLanguage) -> String {
        language == .en ? en : ru
    }
}

/// Errors that carry a bilingual message as data. Resolution to a concrete
/// `String` happens at the presentation layer via `resolved(_:)`, or through the
/// `LocalizedError` bridge below for legacy `error.localizedDescription` call
/// sites. The dependency on the language singleton lives here, in one place,
/// rather than being embedded in every error type.
protocol LocalizableError: LocalizedError {
    var localizedMessage: LocalizedMessage { get }
}

extension LocalizableError {
    var errorDescription: String? {
        localizedMessage.resolved(LanguageManager.shared.language)
    }
}
