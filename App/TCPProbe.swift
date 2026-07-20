import Foundation
import Network

/// A single TCP reachability/RTT probe shared by the connection readiness check,
/// the connected-state ping, and subscription latency measurement.
enum TCPProbe {
    /// Opens a TCP connection to `host:port` and returns the time-to-ready in
    /// milliseconds, or `nil` if the connection fails, is cancelled, or does not
    /// become ready within `timeout`. Out-of-range ports return `nil` instead of
    /// trapping.
    static func measure(host: String, port: Int, timeout: TimeInterval) async -> Int? {
        guard let portValue = UInt16(exactly: port),
              let endpointPort = NWEndpoint.Port(rawValue: portValue) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let start = Date()
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: endpointPort,
                using: .tcp
            )
            let resume = ProbeResumeOnce(connection: connection, continuation: continuation)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    resume.finish(Int(Date().timeIntervalSince(start) * 1000))
                case .failed, .cancelled:
                    resume.finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .utility))
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                resume.finish(nil)
            }
        }
    }
}

/// Resumes a probe's continuation exactly once and cancels the connection,
/// regardless of which of the racing events (ready / failed / timeout) fires
/// first. Shared with `SocksProbe`, which races the same way across more steps.
final class ProbeResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false
    private let connection: NWConnection
    private let continuation: CheckedContinuation<Int?, Never>

    init(connection: NWConnection, continuation: CheckedContinuation<Int?, Never>) {
        self.connection = connection
        self.continuation = continuation
    }

    func finish(_ value: Int?) {
        lock.lock()
        guard !didResume else {
            lock.unlock()
            return
        }
        didResume = true
        lock.unlock()

        connection.cancel()
        continuation.resume(returning: value)
    }
}
