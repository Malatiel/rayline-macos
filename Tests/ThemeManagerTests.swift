import XCTest
import SwiftUI
@testable import RaylineCore

/// The theme now has two representations — one for AppKit, one for SwiftUI —
/// and they have to agree. If they drift, the window chrome and the view
/// contents render in different schemes, which is worse than the flicker this
/// was added to fix.
final class ThemeManagerTests: XCTestCase {

    func testSystemFollowsTheSystemInBothRepresentations() {
        XCTAssertNil(AppTheme.system.appearance, "AppKit: nil means follow the system")
        XCTAssertNil(AppTheme.system.colorScheme, "SwiftUI: nil means follow the system")
    }

    func testLightMapsToLightInBothRepresentations() {
        XCTAssertEqual(AppTheme.light.appearance?.name, .aqua)
        XCTAssertEqual(AppTheme.light.colorScheme, .light)
    }

    func testDarkMapsToDarkInBothRepresentations() {
        XCTAssertEqual(AppTheme.dark.appearance?.name, .darkAqua)
        XCTAssertEqual(AppTheme.dark.colorScheme, .dark)
    }

    /// Catches a case added to the enum without a SwiftUI counterpart: an
    /// explicit theme silently falling back to "follow the system" would be a
    /// quiet regression rather than a build error.
    func testOnlySystemDefersToTheSystem() {
        for theme in AppTheme.allCases where theme != .system {
            XCTAssertNotNil(
                theme.colorScheme,
                "\(theme.rawValue) is an explicit choice and must not defer to the system"
            )
            XCTAssertNotNil(theme.appearance, "\(theme.rawValue) must pin an AppKit appearance")
        }
    }

    func testEveryThemeRoundTripsThroughItsRawValue() {
        for theme in AppTheme.allCases {
            XCTAssertEqual(AppTheme(rawValue: theme.rawValue), theme)
        }
    }
}
