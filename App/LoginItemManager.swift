import Foundation
import ServiceManagement

/// Whether Rayline is registered to start when the user logs in.
///
/// `requiresApproval` is a real, reachable state on macOS 13+: registration can
/// succeed while the item stays inactive until the user approves it in System
/// Settings, so it must be shown rather than collapsed into enabled/disabled.
enum LoginItemState: Equatable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable

    var isEnabled: Bool { self == .enabled }

    /// Approval is still pending, so the user has asked for launch at login but
    /// the system is not honouring it yet.
    var needsUserAction: Bool { self == .requiresApproval }
}

/// The system side of launch-at-login, behind a protocol so the manager's
/// policy can be unit-tested without touching the real LaunchServices
/// registration (which is unavailable in a test process).
protocol LoginItemService {
    var state: LoginItemState { get }
    func register() throws
    func unregister() throws
}

/// Backed by `SMAppService.mainApp`, which registers the running app bundle.
struct SystemLoginItemService: LoginItemService {
    var state: LoginItemState {
        switch SMAppService.mainApp.status {
        case .enabled:          return .enabled
        case .notRegistered:    return .disabled
        case .requiresApproval: return .requiresApproval
        case .notFound:         return .unavailable
        @unknown default:       return .unavailable
        }
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}

@MainActor
final class LoginItemManager: ObservableObject {

    @Published private(set) var state: LoginItemState
    @Published private(set) var lastError: LocalizedMessage?

    private let service: LoginItemService

    init(service: LoginItemService = SystemLoginItemService()) {
        self.service = service
        self.state = service.state
    }

    var isEnabled: Bool { state.isEnabled }

    /// Applies the requested setting and then re-reads the system state.
    ///
    /// `register()` succeeding does not mean the login item is active — macOS
    /// can hold it pending user approval — so the published state always comes
    /// from reading the service back, never from assuming the call worked.
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            lastError = nil
        } catch {
            lastError = LocalizedMessage(
                ru: "Не удалось изменить автозапуск: \(error.localizedDescription)",
                en: "Failed to change launch at login: \(error.localizedDescription)"
            )
        }
        refresh()
    }

    func refresh() {
        state = service.state
    }

    /// Description for the settings row, resolved at the presentation layer.
    var statusDescription: LocalizedMessage {
        if let lastError {
            return lastError
        }
        switch state {
        case .enabled:
            return LocalizedMessage(
                ru: "Rayline будет запускаться при входе в систему",
                en: "Rayline will start when you log in"
            )
        case .disabled:
            return LocalizedMessage(
                ru: "Запускать Rayline при входе в систему",
                en: "Start Rayline when you log in"
            )
        case .requiresApproval:
            return LocalizedMessage(
                ru: "Требуется подтверждение в Системных настройках → Основные → Объекты входа",
                en: "Needs approval in System Settings → General → Login Items"
            )
        case .unavailable:
            return LocalizedMessage(
                ru: "Недоступно для этой сборки — установите Rayline в «Программы»",
                en: "Unavailable for this build — install Rayline in Applications"
            )
        }
    }

    /// The toggle is pointless when the system cannot register this bundle at
    /// all, which is the normal case for a build run straight from the build
    /// directory rather than from Applications.
    var isToggleEnabled: Bool { state != .unavailable }
}
