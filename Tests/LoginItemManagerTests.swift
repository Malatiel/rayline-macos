import XCTest
@testable import RaylineCore

/// Stands in for the real LaunchServices registration, which cannot be
/// exercised from a test process. `reportedState` is what the system will claim
/// after a call, so tests can model the cases where registering succeeds but
/// does not actually enable the login item.
private final class FakeLoginItemService: LoginItemService {
    var state: LoginItemState
    var registerError: Error?
    var unregisterError: Error?
    var reportedStateAfterRegister: LoginItemState?
    var reportedStateAfterUnregister: LoginItemState?

    private(set) var registerCalls = 0
    private(set) var unregisterCalls = 0

    init(state: LoginItemState) {
        self.state = state
    }

    func register() throws {
        registerCalls += 1
        if let registerError { throw registerError }
        if let reportedStateAfterRegister { state = reportedStateAfterRegister }
    }

    func unregister() throws {
        unregisterCalls += 1
        if let unregisterError { throw unregisterError }
        if let reportedStateAfterUnregister { state = reportedStateAfterUnregister }
    }
}

private struct TestError: LocalizedError {
    var errorDescription: String? { "boom" }
}

@MainActor
final class LoginItemManagerTests: XCTestCase {

    func testGivenRegisteredServiceWhenManagerStartsThenItReportsEnabled() {
        let manager = LoginItemManager(service: FakeLoginItemService(state: .enabled))
        XCTAssertTrue(manager.isEnabled)
        XCTAssertNil(manager.lastError)
    }

    func testGivenEnablingWhenServiceRegistersThenStateBecomesEnabled() {
        let service = FakeLoginItemService(state: .disabled)
        service.reportedStateAfterRegister = .enabled
        let manager = LoginItemManager(service: service)

        manager.setEnabled(true)

        XCTAssertEqual(service.registerCalls, 1)
        XCTAssertEqual(manager.state, .enabled)
        XCTAssertNil(manager.lastError)
    }

    /// The important case: registering can succeed while macOS holds the item
    /// pending approval. The manager must report what the system says, not
    /// assume the request took effect.
    func testGivenRegisterSucceedsButApprovalPendingThenStateIsNotEnabled() {
        let service = FakeLoginItemService(state: .disabled)
        service.reportedStateAfterRegister = .requiresApproval
        let manager = LoginItemManager(service: service)

        manager.setEnabled(true)

        XCTAssertEqual(manager.state, .requiresApproval)
        XCTAssertFalse(manager.isEnabled, "Pending approval must not be shown as enabled")
        XCTAssertTrue(manager.state.needsUserAction)
    }

    func testGivenRegisterThrowsThenErrorIsSurfacedAndStateStaysDisabled() {
        let service = FakeLoginItemService(state: .disabled)
        service.registerError = TestError()
        let manager = LoginItemManager(service: service)

        manager.setEnabled(true)

        XCTAssertFalse(manager.isEnabled)
        XCTAssertNotNil(manager.lastError, "A failed registration must surface an error")
        XCTAssertTrue(manager.statusDescription.en.contains("boom"))
    }

    func testGivenDisablingWhenServiceUnregistersThenStateBecomesDisabled() {
        let service = FakeLoginItemService(state: .enabled)
        service.reportedStateAfterUnregister = .disabled
        let manager = LoginItemManager(service: service)

        manager.setEnabled(false)

        XCTAssertEqual(service.unregisterCalls, 1)
        XCTAssertEqual(manager.state, .disabled)
    }

    func testGivenPreviousErrorWhenLaterCallSucceedsThenErrorIsCleared() {
        let service = FakeLoginItemService(state: .disabled)
        service.registerError = TestError()
        let manager = LoginItemManager(service: service)
        manager.setEnabled(true)
        XCTAssertNotNil(manager.lastError)

        service.registerError = nil
        service.reportedStateAfterRegister = .enabled
        manager.setEnabled(true)

        XCTAssertNil(manager.lastError, "A later success must clear the stale error")
        XCTAssertTrue(manager.isEnabled)
    }

    func testGivenUnavailableServiceThenToggleIsDisabled() {
        let manager = LoginItemManager(service: FakeLoginItemService(state: .unavailable))
        XCTAssertFalse(manager.isToggleEnabled)
        XCTAssertFalse(manager.isEnabled)
    }

    func testGivenAvailableStatesThenToggleIsEnabled() {
        for state in [LoginItemState.enabled, .disabled, .requiresApproval] {
            let manager = LoginItemManager(service: FakeLoginItemService(state: state))
            XCTAssertTrue(manager.isToggleEnabled, "Toggle must be usable in state \(state)")
        }
    }

    func testStatusDescriptionIsAvailableInBothLanguages() {
        for state in [LoginItemState.enabled, .disabled, .requiresApproval, .unavailable] {
            let manager = LoginItemManager(service: FakeLoginItemService(state: state))
            XCTAssertFalse(manager.statusDescription.ru.isEmpty, "Missing ru text for \(state)")
            XCTAssertFalse(manager.statusDescription.en.isEmpty, "Missing en text for \(state)")
        }
    }
}
