import SwiftUI

@MainActor
final class ToastManager: ObservableObject {

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let style: Style

        enum Style: Equatable {
            case success, error, info
        }
    }

    @Published var currentToast: Toast?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, style: Toast.Style = .info) {
        dismissTask?.cancel()
        currentToast = Toast(message: message, style: style)
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            currentToast = nil
        }
    }
}
