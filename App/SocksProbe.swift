import Foundation
import Network

/// Checks that the local SOCKS proxy can actually open a connection through the
/// tunnel, rather than only that the remote server's port accepts TCP.
///
/// This exists because a plain TCP probe to the proxy server says nothing about
/// whether the proxy works: an expired UUID or a wrong REALITY key still leaves
/// the port open and the handshake fast, so a latency reading alone can look
/// perfectly healthy while no traffic passes.
///
/// It is deliberately *not* wired into the frequent RTT ping. That runs every
/// few seconds, and sending a real connection through a third-party host at that
/// rate would be its own privacy problem for an app that ships no telemetry.
enum SocksProbe {

    /// Target used to prove the tunnel carries traffic. `example.com` is run by
    /// IANA for exactly this kind of use and sees no meaningful load from it.
    /// One `HEAD` request is sent and its status line read; nothing else.
    static let defaultTargetHost = "example.com"
    static let defaultTargetPort = 80

    // MARK: - Protocol encoding

    /// SOCKS5 greeting offering only the "no authentication" method.
    static func greeting() -> Data {
        Data([0x05, 0x01, 0x00])
    }

    /// A greeting is accepted when the proxy answers SOCKS5 / no-auth.
    static func isGreetingAccepted(_ data: Data) -> Bool {
        let bytes = Array(data)
        return bytes.count >= 2 && bytes[0] == 0x05 && bytes[1] == 0x00
    }

    /// SOCKS5 CONNECT request addressed by domain name, so the tunnel's own name
    /// resolution is exercised too.
    static func connectRequest(host: String, port: Int) -> Data? {
        let hostBytes = Array(host.utf8)
        guard !hostBytes.isEmpty,
              hostBytes.count <= 255,
              let portValue = UInt16(exactly: port) else {
            return nil
        }
        var data = Data([0x05, 0x01, 0x00, 0x03, UInt8(hostBytes.count)])
        data.append(contentsOf: hostBytes)
        data.append(UInt8(portValue >> 8))
        data.append(UInt8(portValue & 0xFF))
        return data
    }

    /// Reply byte 1 is the status code; `0x00` means the proxy accepted the
    /// CONNECT. This is necessary but **not** sufficient evidence that the
    /// tunnel works: sing-box answers the CONNECT optimistically, before the
    /// upstream connection exists, so a dead server still produces `0x00` here.
    /// Proof requires bytes coming back through the tunnel — see `httpRequest`.
    static func isConnectSucceeded(_ data: Data) -> Bool {
        let bytes = Array(data)
        return bytes.count >= 2 && bytes[0] == 0x05 && bytes[1] == 0x00
    }

    /// Minimal request whose response proves data actually traversed the tunnel.
    /// `HEAD` keeps the reply to headers only, and `Connection: close` means the
    /// far side hangs up rather than leaving a socket idle.
    static func httpRequest(host: String) -> Data {
        Data("HEAD / HTTP/1.1\r\nHost: \(host)\r\nConnection: close\r\n\r\n".utf8)
    }

    /// Any well-formed status line means the request reached a real server and
    /// the answer came back — which is the only thing that proves the tunnel.
    static func isHTTPResponse(_ data: Data) -> Bool {
        Array(data).starts(with: Array("HTTP/".utf8))
    }

    // MARK: - Probe

    /// Returns the milliseconds taken to complete a SOCKS5 CONNECT through the
    /// local proxy, or `nil` if the tunnel could not carry the connection.
    static func measure(
        socksPort: Int,
        targetHost: String = defaultTargetHost,
        targetPort: Int = defaultTargetPort,
        timeout: TimeInterval
    ) async -> Int? {
        guard let portValue = UInt16(exactly: socksPort),
              let endpointPort = NWEndpoint.Port(rawValue: portValue),
              let request = connectRequest(host: targetHost, port: targetPort) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let start = Date()
            let connection = NWConnection(
                host: NWEndpoint.Host("127.0.0.1"),
                port: endpointPort,
                using: .tcp
            )
            let resume = ProbeResumeOnce(connection: connection, continuation: continuation)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    sendGreeting(
                        on: connection,
                        request: request,
                        targetHost: targetHost,
                        start: start,
                        resume: resume
                    )
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

    private static func sendGreeting(
        on connection: NWConnection,
        request: Data,
        targetHost: String,
        start: Date,
        resume: ProbeResumeOnce
    ) {
        connection.send(content: greeting(), completion: .contentProcessed { error in
            guard error == nil else { return resume.finish(nil) }

            connection.receive(minimumIncompleteLength: 2, maximumLength: 2) { data, _, _, error in
                guard error == nil, let data, isGreetingAccepted(data) else {
                    return resume.finish(nil)
                }
                sendConnect(
                    on: connection,
                    request: request,
                    targetHost: targetHost,
                    start: start,
                    resume: resume
                )
            }
        })
    }

    private static func sendConnect(
        on connection: NWConnection,
        request: Data,
        targetHost: String,
        start: Date,
        resume: ProbeResumeOnce
    ) {
        connection.send(content: request, completion: .contentProcessed { error in
            guard error == nil else { return resume.finish(nil) }

            // A reply is 10 bytes for IPv4 and up to 262 for a domain, but the
            // status is in byte 1, so two bytes are enough to decide.
            connection.receive(minimumIncompleteLength: 2, maximumLength: 262) { data, _, _, error in
                guard error == nil, let data, isConnectSucceeded(data) else {
                    return resume.finish(nil)
                }
                exchangeRequest(on: connection, targetHost: targetHost, start: start, resume: resume)
            }
        })
    }

    /// The step that actually proves the tunnel: send a request and require a
    /// reply. Without this the probe reports success against a dead server,
    /// because the CONNECT above is answered before the upstream is dialled.
    private static func exchangeRequest(
        on connection: NWConnection,
        targetHost: String,
        start: Date,
        resume: ProbeResumeOnce
    ) {
        connection.send(content: httpRequest(host: targetHost), completion: .contentProcessed { error in
            guard error == nil else { return resume.finish(nil) }

            connection.receive(minimumIncompleteLength: 5, maximumLength: 256) { data, _, _, error in
                guard error == nil, let data, isHTTPResponse(data) else {
                    return resume.finish(nil)
                }
                resume.finish(Int(Date().timeIntervalSince(start) * 1000))
            }
        })
    }
}
